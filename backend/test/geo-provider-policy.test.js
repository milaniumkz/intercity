const {test}=require('node:test'),assert=require('node:assert/strict');
const {GeoProviderGate,routeProviderAllowed}=require('../dist/src/geo/provider-policy');
const {GeoService}=require('../dist/src/geo/geo.service');
const cities=[{id:'omsk',name:'Омск',region:'Омская область',countryCode:'RU',lat:54.989,lng:73.368},{id:'ust',name:'Усть-Каменогорск',region:'Казахстан',countryCode:'KZ',lat:49.948986,lng:82.627945}];
const make=(settings={},index)=>new GeoService({city:{findMany:async()=>cities,findFirst:async({where})=>cities.find(c=>c.id===where.id)||null}},{get:k=>settings[k]},index);
const feature={properties:{name:'улица Ленина',street:'улица Ленина',housenumber:'10',city:'Омск',country:'Россия',countrycode:'RU'},geometry:{coordinates:[73.37,54.99]}};
const road={code:'Ok',routes:[{distance:2100,duration:240,geometry:{type:'LineString',coordinates:[[73.368,54.989],[73.375,54.995],[73.38,55.0]]},legs:[]}]};
test('autocomplete never calls public Nominatim, including implicit city reverse',async()=>{
 const geo=make();const urls=[];geo.fetchGeo=async url=>{urls.push(url);assert.notEqual(new URL(url).searchParams.get('lang'),'ru');return {json:async()=>({features:[feature]})}};
 const results=await geo.searchLocations('Ленина 10',54.989,73.368);assert.equal(results[0].houseNumber,'10');assert.match(results[0].displayName,/Омск/);
 await geo.fetchSearchResults('Ленина','ru',cities[0]);await geo.fetchCitySearchResults('Омск');assert.equal(urls.length,1);assert(urls[0].startsWith('https://photon.komoot.io/api/'));
});
test('Kazakhstan index is preserved while all outside providers are offline',async()=>{
 const geo=make({}, {search:async()=>[{displayName:'Индексная 10',lat:49.95,lng:82.63}]});geo.fetchGeo=async()=>{throw Error('unnecessary outside call')};
 assert.equal((await geo.searchLocations('Индексная 10',49.948986,82.627945))[0].displayName,'Индексная 10');
});
test('Yandex key alone never enables requests',async()=>{
 for(const flag of [undefined,'false']){const geo=make({YANDEX_GEOCODER_API_KEY:'fixture-not-real',YANDEX_GEOCODER_FALLBACK_ENABLED:flag});let calls=0;geo.fetchGeo=async()=>{calls++;throw Error('unexpected')};assert.deepEqual(await geo.fetchYandexSearchResults('Ленина',cities[0]),[]);assert.deepEqual(await geo.fetchYandexCitySearchResults('Омск'),[]);assert.equal(calls,0);}
});
test('provider outage is distinct from a valid empty search and does not prevent recovery',async()=>{
 const geo=make();let offline=true;geo.fetchGeo=async()=>{if(offline)throw Error('offline');return {json:async()=>({features:[feature]})}};
 await assert.rejects(geo.searchLocations('Ленина 10',54.989,73.368),e=>e.getStatus()===503&&e.getResponse().code==='ADDRESS_SEARCH_UNAVAILABLE');offline=false;assert.equal((await geo.searchLocations('Ленина 10',54.989,73.368)).length,1);
});
test('reverse uses Photon and shares concurrent lookup results',async()=>{
 const geo=make();let calls=0;geo.fetchGeo=async url=>{calls++;assert.match(url,/photon\.komoot\.io\/reverse/);return {json:async()=>({features:[feature]})}};
 const rows=await Promise.all([geo.reverseGeocode(54.989,73.368),geo.reverseGeocode(54.989,73.368)]);assert.equal(calls,1);assert.equal(rows[0].currency,'RUB');assert.equal(rows[0].addressResolved,true);
});
test('public limits and Retry-After are global, not per phone',async()=>{
 let now=0;const times=[],gate=new GeoProviderGate(()=>now,async ms=>{now+=ms});await Promise.all([1,2,3].map(()=>gate.run('https://photon.komoot.io/api/',async()=>{times.push(now);return new Response('{}')})));assert.deepEqual(times,[0,1100,2200]);
 await gate.run('https://photon.komoot.io/api/',async()=>new Response('',{status:429,headers:{'retry-after':'120'}}));let called=false;await assert.rejects(gate.run('https://photon.komoot.io/reverse',async()=>{called=true;return new Response('{}')}));assert.equal(called,false);now+=121000;await gate.run('https://photon.komoot.io/api/',async()=>new Response('{}'));
});
test('commercial demo routing requires operator permission, not only an enable flag',async()=>{
 assert.equal(routeProviderAllowed('https://router.project-osrm.org','true'),false);assert.equal(routeProviderAllowed('https://routing.openstreetmap.de/routed-car','true'),false);
 const geo=make();let calls=0;geo.fetchGeo=async()=>{calls++;return {json:async()=>road}};await assert.rejects(geo.getRoute(54.989,73.368,55,73.38),e=>e.getResponse().reason==='PROVIDER_POLICY');assert.equal(calls,0);
});
test('approved owner-controlled routers fail over once and preserve actual road geometry',async()=>{
 const geo=make({OSRM_URL:'http://router.internal',OSRM_FALLBACK_URL:'http://reserve.internal',OSRM_FALLBACK_ENABLED:'true'});const calls=[];geo.fetchGeo=async url=>{calls.push(url);if(url.startsWith('http://router.internal'))throw Error('offline');return {json:async()=>road}};
 const result=await geo.getRoute(54.989,73.368,55,73.38);assert.equal(calls.length,2);assert.equal(result.distance,2.1);assert.equal(result.geometry.coordinates.length,3);
});
test('disabled reserve and malformed road responses never invent a fare',async()=>{
 for(const data of [{code:'NoRoute',routes:[]},{code:'Ok',routes:[{distance:2,duration:3,geometry:{type:'LineString',coordinates:[[73.368,54.989],[null,55]]}}]}]){const geo=make({OSRM_URL:'http://router.internal',OSRM_FALLBACK_URL:'http://reserve.internal',OSRM_FALLBACK_ENABLED:'false'});let calls=0;geo.fetchGeo=async url=>{calls++;assert(url.startsWith('http://router.internal'));return {json:async()=>data}};await assert.rejects(geo.getRoute(54.989,73.368,55,73.38),e=>e.getStatus()===503);assert.equal(calls,1);}
});
test('intercity road distances and geometry are retained for Kazakhstan and Russia',async()=>{
 for(const [a,b,metres] of [[[49.95,82.61],[50.34,83.51],128000],[[55.75,37.62],[59.93,30.31],710000]]){
  const geo=make({OSRM_URL:'http://router.internal'});
  const coordinates=[[a[1],a[0]],[(a[1]+b[1])/2,(a[0]+b[0])/2+.01],[b[1],b[0]]];
  geo.fetchGeo=async()=>({json:async()=>({code:'Ok',routes:[{distance:metres,duration:7200,geometry:{type:'LineString',coordinates},legs:[]}]})});
  const result=await geo.getRoute(...a,...b);assert.equal(result.distance,metres/1000);assert.deepEqual(result.geometry.coordinates,coordinates);
 }
});
test('both configured routing sources fail with only one attempt per source',async()=>{
 const geo=make({OSRM_URL:'http://router.internal',OSRM_FALLBACK_URL:'http://reserve.internal',OSRM_FALLBACK_ENABLED:'true'});
 let calls=0;geo.fetchGeo=async()=>{calls++;throw Error('network timeout')};
 await assert.rejects(geo.getRoute(54.989,73.368,55,73.38),e=>e.getResponse().reason==='PROVIDER_UNAVAILABLE');assert.equal(calls,2);
});
test('private BRouter car geometry uses road distance and never calls a public demo',async()=>{
 const geo=make({BROUTER_URL:'http://routing:17777'});const urls=[];
 geo.fetchGeo=async url=>{urls.push(url);return {json:async()=>({features:[{geometry:{type:'LineString',coordinates:[[82.61,49.95,200],[82.62,49.94,210],[83.51,50.34,300]]},properties:{'track-length':'133581','total-time':'7205'}}]})}};
 const result=await geo.getRoute(49.95,82.61,50.34,83.51);
 assert.equal(result.distance,133.581);assert.equal(result.duration,120);assert.equal(result.geometry.coordinates[0].length,2);
 assert.equal(urls.length,1);assert.match(urls[0],/^http:\/\/routing:17777\/brouter\?/);assert.match(urls[0],/profile=car-fast-nocost/);
});
test('private car route outage or malformed output is explicit, not a public-demo fallback',async()=>{
 for(const data of [null,{features:[]},{features:[{geometry:{type:'LineString',coordinates:[[1,1],[2,2]]},properties:{'track-length':'nan','total-time':'10'}}]}]) {
  const geo=make({BROUTER_URL:'http://routing:17777'});let calls=0;
  geo.fetchGeo=async()=>{calls++;if(data===null)throw Error('offline');return {json:async()=>data}};
  await assert.rejects(geo.getRoute(49.95,82.61,50.34,83.51),e=>e.getResponse().reason==='PROVIDER_UNAVAILABLE');assert.equal(calls,1);
 }
});
test('a second distinct private route never interrupts the active single routing worker',async()=>{
 const geo=make({BROUTER_URL:'http://routing:17777'});let complete,calls=0;
 geo.fetchGeo=async()=>{calls++;return new Promise(r=>{complete=()=>r({json:async()=>({features:[{geometry:{type:'LineString',coordinates:[[73.368,54.989],[73.38,55]]},properties:{'track-length':'2100','total-time':'240'}}]})})})};
 const first=geo.getRoute(54.989,73.368,55,73.38);
 await assert.rejects(geo.getRoute(54.989,73.368,55.1,73.38),e=>e.getResponse().reason==='PROVIDER_UNAVAILABLE');
 assert.equal(calls,1);complete();assert.equal((await first).distance,2.1);
});
