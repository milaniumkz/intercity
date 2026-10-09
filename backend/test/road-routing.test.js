const {test}=require('node:test');
const assert=require('node:assert/strict');
const {GeoService}=require('../dist/src/geo/geo.service');
const makeGeo=()=>new GeoService({city:{findMany:async()=>[],findFirst:async()=>null}}, {get:()=>undefined});
const road={code:'Ok',routes:[{distance:8300,duration:900,geometry:{type:'LineString',coordinates:[[82.61,49.95],[82.62,49.94],[82.609,49.90]]},legs:[]}]};
test('router failure uses independent road provider and coalesces/cache successful geometry',async()=>{
 const geo=makeGeo();let calls=0;const urls=[];
 geo.fetchGeo=async(url)=>{calls++;urls.push(url);if(calls===1)throw Error('timeout');return {json:async()=>road};};
 const [a,b]=await Promise.all([geo.getRoute(49.95,82.61,49.90,82.609),geo.getRoute(49.95,82.61,49.90,82.609)]);
 assert.equal(calls,2);assert.match(urls[0],/^https:/);assert.match(urls[1],/routing.openstreetmap.de/);
 assert.equal(a.distance,8.3);assert.deepEqual(a.geometry,road.routes[0].geometry);assert.deepEqual(a,b);
 await geo.getRoute(49.95,82.61,49.90,82.609);assert.equal(calls,2);
});
test('invalid geometry is rejected, failure is not cached and a later request can succeed',async()=>{
 const geo=makeGeo();let failed=true;
 geo.fetchGeo=async()=>({json:async()=>failed?{code:'Ok',routes:[{...road.routes[0],geometry:null}]}:road});
 await assert.rejects(geo.getRoute(49.95,82.61,49.90,82.609),e=>e.getStatus()===503);
 failed=false;assert.equal((await geo.getRoute(49.95,82.61,49.90,82.609)).geometry.coordinates.length,3);
 await assert.rejects(geo.getRoute(NaN,82,49,83),e=>e.getStatus()===400);
});
test('Ust-Kamenogorsk spaces, Kazakh alias, Latin alias and a single typo find one canonical city',async()=>{
 const geo=makeGeo();geo.fetchCitySearchResults=async()=>{throw Error('must be local')};
 for(const q of ['усть каменогорск','Өскемен','Ust Kamenogorsk','Уст Каменогорск','Усть Каменогрск']){
  const rows=await geo.searchCities(q);
  assert.equal(rows.filter(x=>x.name==='Усть-Каменогорск').length,1,q);
  assert(!rows.some(x=>x.name==='Ост-Каменогорск'),q);
 }
});
test('independent address search keeps Oskemen aliases and excludes other cities/countries',async()=>{
 const geo=makeGeo();const city={name:'Усть-Каменогорск',countryCode:'KZ',lat:49.948986,lng:82.627945};
 geo.fetchGeo=async()=>({json:async()=>({features:[
  {geometry:{coordinates:[82.627,49.948]},properties:{name:'проспект Казыбек Би',osm_key:'highway',city:'Өскемен',countrycode:'KZ'}},
  {geometry:{coordinates:[82.627,49.948]},properties:{name:'wrong',street:'wrong',city:'Алматы',countrycode:'KZ'}},
  {geometry:{coordinates:[82.627,49.948]},properties:{name:'wrong country',street:'wrong',city:'Өскемен',countrycode:'RU'}},
 ]})});
 const rows=await geo.fetchPhotonSearchResults('Казыбек Би',city);
 assert.equal(rows.length,1);assert.match(rows[0].displayName,/Казыбек Би/);assert.equal(rows[0].road,'проспект Казыбек Би');
});
test('rate limited address provider is skipped while independent search keeps working',async()=>{
 const geo=makeGeo();const city={name:'Усть-Каменогорск',countryCode:'KZ',lat:49.948986,lng:82.627945};
 geo.findNearestCity=async()=>city;let osmCalls=0,photonCalls=0;
 geo.fetchGeo=async(url)=>{
  if(new URL(url).hostname.includes('nominatim')){osmCalls++;throw Error('HTTP 429');}
  photonCalls++;return {json:async()=>({features:[{geometry:{coordinates:[82.627,49.948]},properties:{name:'проспект Казыбек Би',osm_key:'highway',city:'Өскемен',countrycode:'KZ'}}]})};
 };
 for(const q of ['Казыбек Би','Аль-Фараби'])assert((await geo.searchLocations(q,city.lat,city.lng)).length>0);
 assert.equal(osmCalls,1);assert.equal(photonCalls,2);
});
