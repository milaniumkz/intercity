const {test} = require('node:test');
const assert = require('node:assert/strict');
const {GeoService} = require('../dist/src/geo/geo.service');
const makeGeo = () => new GeoService({city:{findMany:async()=>[],findFirst:async()=>null}}, {get:()=>undefined});

test('city prefix search finds Shemonaikha locally, excludes unrelated places and duplicates', async()=>{
 const geo=makeGeo();geo.fetchCitySearchResults=async()=>{throw Error('must not need provider')};
 for(const q of ['Шем','Шемон','Шемона','Шемонаиха','шемонаиха','Shemon']) {
  const rows=await geo.searchCities(q);
  assert(rows.some(c=>c.name==='Шемонаиха'),q);
  assert(rows.every(c=>!c.name.match(/район|округ|администрация|область/i)));
  assert(!rows.some(c=>c.name==='Казань'||c.name==='Маслянино'));
  assert.equal(new Set(rows.map(c=>`${c.countryCode}:${c.name}`)).size,rows.length);
 }
 assert.equal((await geo.searchCities('Шемонаиха'))[0].countryCode,'KZ');
});

test('known city keeps local coordinate and is not duplicated by catalog',async()=>{
 const geo=makeGeo();const rows=await geo.searchCities('Омск');
 assert.equal(rows.filter(c=>c.name==='Омск').length,1);
 assert.equal(rows[0].countryCode,'RU');
});

test('address filtering accepts administrative name alias, rejects different cities',()=>{
 const geo=makeGeo();
 assert(geo.belongsToCityContext({address:{city:'городской округ Омск'}},{name:'Омск'}));
 assert(!geo.belongsToCityContext({address:{city:'Тюмень'}},{name:'Омск'}));
});

test('address provider failure does not discard successful later query',async()=>{
 const geo=makeGeo();geo.findNearestCity=async()=>({id:'omsk',name:'Омск',countryCode:'RU',region:'Россия',lat:54.989,lng:73.368});
 let calls=0;geo.fetchSearchResults=async()=>{if(++calls===1)throw Error('transient');return [{display_name:'улица Ленина, Омск',lat:'54.99',lon:'73.37'}]};
 assert((await geo.searchLocations('Ленина 10',54.989,73.368)).length>0);
});

test('NoRoute result still returns numeric fallback distance for fare calculation',async()=>{
 const geo=makeGeo();geo.fetchGeo=async()=>({json:async()=>({code:'NoRoute',routes:[]})});
 const route=await geo.getRoute(54.989,73.368,55.009,73.388);
 assert(route.distance>0);assert(Number.isFinite(route.duration));
});

test('real Omsk street result is retained when OSM labels municipality instead of city',()=>{
 const geo=makeGeo();
 const osm={display_name:'улица Ленина, Куйбышевский, городской округ Омск, Омская область, Россия',address:{road:'улица Ленина',suburb:'Куйбышевский',city:'городской округ Омск',country_code:'ru'}};
 assert(geo.belongsToCityContext(osm,{name:'Омск'}));
});

test('three provider street searches stay anchored to Ust-Kamenogorsk and preserve names',async()=>{
 for(const q of ['Аль-Фараби','Казыбек Би','Сатпаева']){
  const geo=makeGeo();const city={id:'ust',name:'Усть-Каменогорск',countryCode:'KZ',region:'Казахстан',lat:49.948986,lng:82.627945};
  geo.findNearestCity=async()=>city;
  geo.fetchSearchResults=async(candidate,country,context)=>{
   assert.equal(country,'kz');assert.equal(context.name,'Усть-Каменогорск');
   assert(candidate.includes(q));
   return [{display_name:q+', Усть-Каменогорск',lat:'49.948',lon:'82.627'}];
  };
  const results=await geo.searchLocations(q,city.lat,city.lng);
  assert.equal(results[0].displayName,q+', Усть-Каменогорск');
 }
});

test('Bokey 24 uses the verified house, never substitutes it for another number or city',async()=>{
 const geo=makeGeo();const city={name:'Усть-Каменогорск',lat:49.948986,lng:82.627945};
 for(const q of ['Оралхан Бокей 24','Оралхана Бокея 24','улица Оралхана Бокея, 24','Оралхан Бокей']){
  const rows=geo.findVerifiedAddresses(q,city);
  assert.equal(rows.length,1);assert.equal(rows[0].lat,49.902631);assert.equal(rows[0].lng,82.609936);
 }
 assert.equal(geo.findVerifiedAddresses('Оралхана Бокея 25',city).length,0);
 assert.equal(geo.findVerifiedAddresses('Оралхана Бокея 24',{name:'Алматы',lat:43.238949,lng:76.889709}).length,0);
});
