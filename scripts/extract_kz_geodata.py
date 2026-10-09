import osmium,json,time,argparse
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument('--raw-dir',type=Path,required=True)
root=parser.parse_args().raw_dir; places=[];addresses=[];roads=[]
class Handler(osmium.SimpleHandler):
 def capture(self,obj,lat,lng):
  tags=dict(obj.tags)
  place=tags.get('place')
  if place in ('city','town','village','hamlet'):
   aliases=[]
   for key,value in tags.items():
    if key=='name' or key.startswith(('name:','old_name','alt_name','int_name','official_name','short_name')):aliases.extend(value.split(';'))
   places.append({'name':tags.get('name:ru') or tags.get('name'),'aliases':list(dict.fromkeys(aliases)),'place':place,'lat':lat,'lng':lng,'osmType':'node' if isinstance(obj,osmium.osm.Node) else 'way','osmId':obj.id})
  if tags.get('addr:housenumber') and (tags.get('addr:street') or tags.get('addr:place')):
   addresses.append({'street':tags.get('addr:street') or tags.get('addr:place'),'house':tags['addr:housenumber'],'city':tags.get('addr:city'),'country':tags.get('addr:country'),'lat':lat,'lng':lng,'osmType':'node' if isinstance(obj,osmium.osm.Node) else 'way','osmId':obj.id})
  if tags.get('highway') and tags.get('name'):
   aliases=[]
   for key,value in tags.items():
    if key=='name' or key.startswith(('name:','old_name','alt_name')):aliases.extend(value.split(';'))
   if len(aliases)>1:roads.append({'name':tags['name'],'aliases':list(dict.fromkeys(aliases)),'lat':lat,'lng':lng})
 def node(self,n):
  if n.tags and n.location.valid():self.capture(n,n.location.lat,n.location.lon)
 def way(self,w):
  tags=w.tags
  if not (tags.get('addr:housenumber') or tags.get('place') in ('city','town','village','hamlet') or (tags.get('highway') and tags.get('name'))):return
  nodes=[n for n in w.nodes if n.location.valid()]
  if nodes:self.capture(w,sum(n.lat for n in nodes)/len(nodes),sum(n.lon for n in nodes)/len(nodes))
start=time.time();Handler().apply_file(str(root/'kazakhstan-latest.osm.pbf'),locations=True)
for name,data in [('places',places),('settlements',places),('addresses',addresses),('roads',roads)]:
 (root/f'kz-osm-{name}.json').write_text(json.dumps(data,ensure_ascii=False))
 print(name,len(data),flush=True)
print('seconds',round(time.time()-start,1),flush=True)
