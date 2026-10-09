#!/usr/bin/env python3
"""Build a read-only Kazakhstan address index from verified public OSM extracts.
Requires osmium==4.1.1 and shapely==2.1.1. See geo/DATA_LICENSE.md.
"""
import argparse, gzip, hashlib, json, math, re, sqlite3, unicodedata, zipfile
from pathlib import Path
import osmium
from shapely.geometry import Polygon, Point, shape as from_geojson
from shapely.ops import unary_union
from shapely.prepared import prep

parser=argparse.ArgumentParser()
parser.add_argument('--raw-dir',type=Path,required=True)
parser.add_argument('--output-dir',type=Path,default=Path(__file__).resolve().parents[1]/'backend/src/geo/data')
args=parser.parse_args();raw=args.raw_dir;out=args.output_dir;out.mkdir(parents=True,exist_ok=True)
repo=Path(__file__).resolve().parents[1]
# The source archive is checked against its publisher's checksum before parsing.
expected=(raw/'kazakhstan-latest.osm.pbf.md5').read_text().split()[0]
actual=hashlib.file_digest((raw/'kazakhstan-latest.osm.pbf').open('rb'),'md5').hexdigest()
if actual!=expected:raise SystemExit('OSM source checksum mismatch')
lines=(raw/'kazakhstan.poly').read_text().splitlines();rings=[];holes=[];points=[];hole=False
for line in lines[1:]:
 s=line.strip()
 if s=='END':
  if points:(holes if hole else rings).append(Polygon(points));points=[]
 elif len(s.split())==2:
  try:points.append(tuple(map(float,s.split())))
  except ValueError:pass
 elif s:hole=s.startswith('!')
country=unary_union(rings)
if holes:country=country.difference(unary_union(holes))
boundary=json.loads((raw/'kz-boundary.json').read_text())[0]
assert boundary['osm_id']==214665, 'Unexpected national boundary source'
country=from_geojson(boundary['geojson'])
assert country.is_valid and not country.is_empty, 'Invalid national boundary'
inside=prep(country)
def norm(s):return re.sub(r'\s+',' ',str(s).lower().replace('ё','е').replace('-',' ')).strip()
def km(a,b):
 x=(a['lat']-b['lat'])*111;y=(a['lng']-b['lng'])*111*math.cos(math.radians(a['lat']));return math.hypot(x,y)
regions={
 '07':'Западно-Казахстанская область','09':'Мангистауская область','06':'Атырауская область','04':'Актюбинская область','15':'Восточно-Казахстанская область','03':'Акмолинская область','16':'Северо-Казахстанская область','11':'Павлодарская область','14':'Кызылординская область','13':'Костанайская область','12':'Карагандинская область','17':'Жамбылская область','10':'Туркестанская область','02':'Алматы','01':'Алматинская область','1537272':'Шымкент','08':'Байконур','05':'Астана','12510143':'Абайская область','12510144':'Жетысуская область','12510145':'Улытауская область'}
geo=[]
with zipfile.ZipFile(raw/'geonames-cities500.zip') as z:
 for line in z.read('cities500.txt').decode().splitlines():
  f=line.split('\t')
  if len(f)>10 and f[8]=='KZ':geo.append({'name':f[1],'lat':float(f[4]),'lng':float(f[5]),'region':regions.get(f[10]),'aliases':[f[1],f[2],*f[3].split(',')]})
source=(repo/'backend/src/geo/city-catalog.ts').read_text();base=[c for c in json.loads(source[source.index(' = ')+3:].strip().rstrip(';')) if c['countryCode']=='KZ']
for c in base:
 match=min(geo,key=lambda x:km(c,x));c['region']=(match.get('region') if km(c,match)<5 else None)
places=json.loads((raw/'kz-osm-places.json').read_text());catalog=[]
for p in sorted(places,key=lambda x:x['osmType']!='node'):
 if re.search(r'[\u4e00-\u9fff]',p['name'] or '') or (p['name'] or '').isdigit():continue
 if not p['name'] or not inside.covers(Point(p['lng'],p['lat'])):continue
 # Geofabrik includes a buffered border: discard Chinese-only place labels from neighbouring China.
 if any(re.search(r'[\u4e00-\u9fff]',n) for n in p['aliases']) and not any(re.search(r'[а-яА-ЯәғқңөұүһіӘҒҚҢӨҰҮҺІ]',n) for n in p['aliases']):continue
 if any(norm(c['name'])==norm(p['name']) and km(c,p)<5 for c in catalog):continue
 aliases={n for n in p['aliases']+[p['name']] if norm(n)};keys={norm(n) for n in aliases}
 matches=[c for c in base if km(c,p)<10 and keys.intersection(norm(n) for n in [c['name'],*c['aliases']])]
 for c in matches:aliases.update(c['aliases']);aliases.add(c['name'])
 nearest=min(geo,key=lambda x:km(p,x))
 region=next((c.get('region') for c in matches if c.get('region')),None) or (nearest.get('region') if km(p,nearest)<5 else None)
 catalog.append({'name':p['name'],'aliases':sorted(aliases),'countryCode':'KZ','region':region,'lat':p['lat'],'lng':p['lng'],'source':f"https://www.openstreetmap.org/{p['osmType']}/{p['osmId']}"})
for c in base:
 if not inside.covers(Point(c['lng'],c['lat'])):continue
 keys={norm(n) for n in [c['name'],*c['aliases']]}
 if any(km(c,p)<10 and keys.intersection(norm(n) for n in [p['name'],*p['aliases']]) for p in catalog):continue
 catalog.append(c)
catalog.sort(key=lambda c:(c['name'],c['lat'],c['lng']))
(out/'kz-cities.json').write_text(json.dumps(catalog,ensure_ascii=False,separators=(',',':')))
# City names are disambiguated by coordinates, not collapsed globally.
by_name={}
for c in catalog:
 for n in [c['name'],*c['aliases']]:
  if norm(n):by_name.setdefault(norm(n),[]).append(c)
grid={}
for c in catalog:grid.setdefault((int(c['lat']*2),int(c['lng']*2)),[]).append(c)
def city_for(a):
 candidates=by_name.get(norm(a['city'] or ''),[])
 if not candidates:
  x,y=int(a['lat']*2),int(a['lng']*2)
  candidates=[c for dx in [-1,0,1] for dy in [-1,0,1] for c in grid.get((x+dx,y+dy),[])]
 if not candidates:return a['city'] or ''
 nearest=min(candidates,key=lambda c:km(a,c))
 return nearest['name'] if km(a,nearest)<(50 if a['city'] else 15) else a['city'] or ''
fold=str.maketrans({'ә':'а','ғ':'г','қ':'к','ң':'н','ө':'о','ұ':'у','ү':'у','һ':'х','і':'и','ё':'е','ь':'','ъ':''})
types={'улица','ул','проспект','пр','прт','переулок','пер','площадь','көшесі','көшесi','кошеси','даңғылы','дангылы','микрорайон','мкр','бульвар','шоссе'}
def street_key(s):
 words=re.findall(r'[^\W_]+',unicodedata.normalize('NFKC',s).lower())
 words=[w.translate(fold) for w in words if w not in types]
 words=[re.sub(r'([ое]в)а$',r'\1',w).replace('сатпаев','сатбаев') for w in words]
 return ' '.join(words)
def house_key(s):return re.sub(r'\s+','',unicodedata.normalize('NFKC',s).lower().replace('a','а'))
db_path=raw/'kazakhstan-addresses.sqlite';db_path.unlink(missing_ok=True)
con=sqlite3.connect(db_path);con.executescript('''PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;
CREATE TABLE addresses(id INTEGER PRIMARY KEY, street TEXT NOT NULL, house TEXT NOT NULL, city TEXT NOT NULL, lat REAL NOT NULL, lng REAL NOT NULL, osm_type TEXT NOT NULL, osm_id INTEGER NOT NULL, house_key TEXT NOT NULL, street_key TEXT NOT NULL);
CREATE VIRTUAL TABLE street_search USING fts5(street_key,content='addresses',content_rowid='id',tokenize='unicode61 remove_diacritics 2');''')
addresses=json.loads((raw/'kz-osm-addresses.json').read_text());batch=[];samples={};count=0;excluded=0
for a in addresses:
 if a['country'] and a['country'].upper() not in ('KZ','КАЗАХСТАН'):excluded+=1;continue
 if not inside.covers(Point(a['lng'],a['lat'])):excluded+=1;continue
 city=city_for(a);key=street_key(a['street'])
 if not key:continue
 batch.append((a['street'],a['house'],city,a['lat'],a['lng'],a['osmType'],a['osmId'],house_key(a['house']),key));count+=1
 if len(batch)>=5000:con.executemany('INSERT INTO addresses(street,house,city,lat,lng,osm_type,osm_id,house_key,street_key) VALUES (?,?,?,?,?,?,?,?,?)',batch);batch=[]
 if count%100000==0:print('Indexed',count,flush=True)
 if re.fullmatch(r'\d+[\w]?(?:/\d+[\w]?)?',a['house']):
  names=by_name.get(norm(city),[])
  for c in names:
   d=km(a,c)
   if d>10:continue
   sid=f"{c['name']}:{c['lat']}:{c['lng']}";current=samples.setdefault(sid,{'city':c,'addresses':[]})['addresses']
   if not any(x['street']==a['street'] for x in current):current.append({**a,'city':city,'distance_km':d})
   current.sort(key=lambda x:x['distance_km']);del current[3:]
if batch:con.executemany('INSERT INTO addresses(street,house,city,lat,lng,osm_type,osm_id,house_key,street_key) VALUES (?,?,?,?,?,?,?,?,?)',batch)
con.execute("INSERT INTO street_search(street_search) VALUES ('rebuild')");con.commit()
assert con.execute('PRAGMA quick_check').fetchone()[0]=='ok';con.close()
with db_path.open('rb') as src,gzip.open(out/'kazakhstan-addresses.sqlite.gz','wb',compresslevel=9) as dst:
 import shutil;shutil.copyfileobj(src,dst)
compressed=out/'kazakhstan-addresses.sqlite.gz';sha=hashlib.file_digest(compressed.open('rb'),'sha256').hexdigest()
header=osmium.io.Reader(str(raw/'kazakhstan-latest.osm.pbf')).header()
meta={'snapshot':header.get('osmosis_replication_timestamp'),'source':'https://download.geofabrik.de/asia/kazakhstan.html','license':'ODbL 1.0','attribution':'© OpenStreetMap contributors','addresses':count,'excluded_outside_kz':excluded,'cities':len(catalog),'compressed_sha256':sha,'source_pbf_md5':actual}
(out/'kz-metadata.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2))
all_samples=[samples.get(f"{c['name']}:{c['lat']}:{c['lng']}",{'city':c,'addresses':[]}) for c in catalog]
(raw/'kz-address-audit-samples.json').write_text(json.dumps(all_samples,ensure_ascii=False))
print(json.dumps(meta,ensure_ascii=False),flush=True)
print('Sample coverage',sum(bool(s['addresses']) for s in all_samples),'/',len(all_samples),flush=True)
