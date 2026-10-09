const {test}=require('node:test');
const assert=require('node:assert/strict');
const {KazakhstanAddressIndex}=require('../dist/src/geo/kz-address-index');
const {GeoService}=require('../dist/src/geo/geo.service');
const {cityCatalog}=require('../dist/src/geo/combined-city-catalog');
const index=new KazakhstanAddressIndex({get:key=>key==='SQLITE3_BIN'?process.env.SQLITE3_BIN:undefined});
const geo=()=>new GeoService({city:{findMany:async()=>require('../dist/src/geo/combined-city-catalog').cityCatalog.map((c,i)=>({...c,id:'fixture-'+i})),findFirst:async()=>null}}, {get:()=>undefined},index);

test('packaged address index works with all external geocoders unavailable',async()=>{
 const service=geo();service.fetchGeo=async()=>{throw Error('provider unavailable')};
 for(const q of ['улица Кабдолова, 14А','Кабдолова 14A']){
  const rows=await service.searchLocations(q,43.2369657,76.8538584);
  assert(rows.some(row=>Math.abs(row.lat-43.2369657)<.0001 && Math.abs(row.lng-76.8538584)<.0001),q);
  assert(rows.every(row=>row.attribution==='© OpenStreetMap contributors'));
 }
 assert(index.info().addresses>1000000);
});
test('local index keeps full house numbers, country boundaries and SQL literals',async()=>{
 const rows=await index.search('Кабдолова 14Б',{lat:43.2369657,lng:76.8538584,countryCode:'KZ'});
 assert(!rows.some(row=>row.houseNumber==='14А'));
 assert.deepEqual(await index.search('Кабдолова 14А',{lat:43.2369657,lng:76.8538584,countryCode:'RU'}),[]);
 assert.deepEqual(await index.search("Кабдолова' OR 1=1 -- 14А",{lat:43.2369657,lng:76.8538584,countryCode:'KZ'}),[]);
 assert.deepEqual(await index.search('Кабдолова 14А',{lat:NaN,lng:76.85,countryCode:'KZ'}),[]);
});
test('new Kazakhstan cities and renamed cities are searchable by current and previous names',async()=>{
 const service=geo();service.fetchCitySearchResults=async()=>{throw Error('must be local')};
 for(const [q,name] of [['Алатау','Алатау'],['Конаев','Конаев'],['Капчагай','Конаев'],['Қонаев','Конаев']]){
  const rows=await service.searchCities(q);assert(rows.some(row=>row.name===name),q);
 }
});
test('same-named Kazakhstan settlements remain separate and carry region labels',async()=>{
 const service=geo();const expected=cityCatalog.filter(city=>city.countryCode==='KZ' && city.name==='Актау');
 const rows=await service.searchCities('Актау');
 assert(expected.length>=3);
 for(const city of expected)assert(rows.some(row=>service.haversine(city.lat,city.lng,row.lat,row.lng)<5),JSON.stringify(city));
 assert(rows.filter(row=>row.name==='Актау').some(row=>row.region));
});
test('city anchoring covers smaller Kazakhstan settlements instead of a distant regional capital',async()=>{
 const service=geo();const city=await service.findNearestCity(49.14284,57.12736);
 assert.equal(city.name,'Темир');assert.equal(city.countryCode,'KZ');
});
