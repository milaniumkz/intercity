#!/usr/bin/env python3
"""Expand versioned settlement catalogs from OSM and GeoNames public extracts.
Input archives KZ.zip and RU.zip: https://download.geonames.org/export/dump/
KZ includes populated cities, villages and hamlets; RU includes cities500 coverage.
"""
import argparse,json,zipfile,re,math,hashlib
from pathlib import Path
from shapely.geometry import Point,Polygon,shape as from_geojson
from shapely.ops import unary_union
from shapely.prepared import prep
p=argparse.ArgumentParser();p.add_argument('--raw-dir',type=Path,required=True);args=p.parse_args();raw=args.raw_dir
repo=Path(__file__).resolve().parents[1];out=repo/'backend/src/geo/data'
def norm(s):return re.sub(r'\s+',' ',s.lower().replace('ё','е').replace('-',' ')).strip()
def km(a,b):return math.hypot((a['lat']-b['lat'])*111,(a['lng']-b['lng'])*111*math.cos(math.radians(a['lat'])))
def russian(names,fallback):
 words=[n for n in names if re.search('[а-яА-Я]',n) and not re.search('[ієїґ]',n.lower())]
 words.sort(key=lambda n:(bool(re.search(r'[ѣъ]$',n)),len(n)))
 return words[0] if words else fallback
source=(repo/'backend/src/geo/city-catalog.ts').read_text();original=json.loads(source[source.index(' = ')+3:].strip().rstrip(';'))
polys=[];holes=[];points=[];hole=False
for line in (raw/'kazakhstan.poly').read_text().splitlines()[1:]:
 s=line.strip()
 if s=='END':
  if points:(holes if hole else polys).append(Polygon(points));points=[]
 elif len(s.split())==2:
  try:points.append(tuple(map(float,s.split())))
  except ValueError:pass
 elif s:hole=s.startswith('!')
shape=unary_union(polys)
if holes:shape=shape.difference(unary_union(holes))
boundary=json.loads((raw/'kz-boundary.json').read_text())[0]
assert boundary['osm_id']==214665, 'Unexpected national boundary source'
country=from_geojson(boundary['geojson'])
assert country.is_valid and not country.is_empty, 'Invalid national boundary'
inside=prep(country)
for cc in ['KZ','RU']:
 names={}
 with zipfile.ZipFile(raw/(cc+'-alternatenames.zip')) as z:
  for line in z.read(cc+'.txt').decode().splitlines():
   f=line.split('\t')
   if len(f)>7 and f[2]=='ru' and f[7]!='1':names.setdefault(f[1],[]).append(f)
 names={gid:sorted(rows,key=lambda f:(f[4]!='1',f[5]=='1',f[6]=='1',len(f[3])))[0][3] for gid,rows in names.items()}
 with zipfile.ZipFile(raw/(cc+'.zip')) as z:records=[line.split('\t') for line in z.read(cc+'.txt').decode().splitlines()]
 regions={f[10]:names.get(f[0]) or russian([f[1],*f[3].split(',')],f[1]) for f in records if f[7]=='ADM1'}
 old={}
 for c in original:
  if c['countryCode']==cc:old.setdefault(norm(c['name']),[]).append(c)
 catalog=[c for c in json.loads((out/'kz-cities.json').read_text()) if inside.covers(Point(c['lng'],c['lat']))] if cc=='KZ' else []
 byname={}
 def remember(c):
  for a in [c['name'],*c['aliases']]:
   if norm(a):byname.setdefault(norm(a),[]).append(c)
 for c in catalog:remember(c)
 def add(c):
  candidates=[x for a in [c['name'],*c['aliases']] for x in byname.get(norm(a),[])]
  nearest=min(candidates,key=lambda x:km(x,c)) if candidates else None
  if nearest and km(nearest,c)<3:
   nearest['aliases']=sorted(set(nearest['aliases']+c['aliases']+[c['name']]))
   nearest['region']=nearest.get('region') or c.get('region');nearest['population']=max(nearest.get('population',0),c.get('population',0));remember(nearest);return
  catalog.append(c);remember(c)
 features={'PPL','PPLA','PPLA2','PPLA3','PPLA4','PPLC','PPLG'}
 for f in records:
  if f[6]!='P' or f[7] not in features:continue
  if cc=='RU' and int(f[14] or 0)<500 and f[7] not in {'PPLA','PPLA2','PPLC'}:continue
  aliases=list(filter(None,[f[1],f[2],*f[3].split(',')]));c={'name':names.get(f[0]) or russian(aliases,f[1]),'aliases':sorted(set(aliases)),'countryCode':cc,'population':int(f[14] or 0),'region':regions.get(f[10]),'lat':float(f[4]),'lng':float(f[5]),'source':'https://www.geonames.org/'+f[0]}
  oldmatch=next((x for a in aliases for x in old.get(norm(a),[]) if km(x,c)<3),None)
  if oldmatch:c['aliases']=sorted(set(c['aliases']+oldmatch['aliases']+[oldmatch['name']]))
  if cc=='KZ' and not inside.covers(Point(c['lng'],c['lat'])):continue
  add(c)
 if cc=='KZ':
  places=json.loads((raw/'kz-osm-settlements.json').read_text())
  for c in places:
   if re.search(r'[\u4e00-\u9fff]',c['name'] or '') or (c['name'] or '').isdigit():continue
   if c.get('country') and c['country'].upper() not in ('KZ','КАЗАХСТАН'):continue
   if not inside.covers(Point(c['lng'],c['lat'])):continue
   if any(re.search(r'[\u4e00-\u9fff]',n) for n in c['aliases']) and not any(re.search('[а-яА-Яәғқңөұүһі]',n,re.I) for n in c['aliases']):continue
   add({k:v for k,v in c.items() if k in ['name','aliases','lat','lng']}|{'countryCode':'KZ','region':None,'source':f"https://www.openstreetmap.org/node/{c['osmId']}"})
 catalog.sort(key=lambda c:(c['name'],c['lat'],c['lng']))
 (out/(cc.lower()+'-cities.json')).write_text(json.dumps(catalog,ensure_ascii=False,separators=(',',':')))
 print(cc,len(catalog),flush=True)
meta={cc:{'url':f'https://download.geonames.org/export/dump/{cc}.zip','sha256':hashlib.file_digest((raw/(cc+'.zip')).open('rb'),'sha256').hexdigest(),'license':'CC BY 4.0'} for cc in ['KZ','RU']}
meta['boundary']={'url':'https://nominatim.openstreetmap.org/lookup?osm_ids=R214665&format=json&polygon_geojson=1','sha256':hashlib.file_digest((raw/'kz-boundary.json').open('rb'),'sha256').hexdigest(),'license':'ODbL 1.0'}
for cc in ['KZ','RU']:
 meta[cc]['russian_names']={'url':f'https://download.geonames.org/export/dump/alternatenames/{cc}.zip','sha256':hashlib.file_digest((raw/(cc+'-alternatenames.zip')).open('rb'),'sha256').hexdigest()}
(out/'settlement-sources.json').write_text(json.dumps(meta,indent=2))
