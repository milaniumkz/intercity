const {test}=require('node:test');const assert=require('node:assert/strict');
const {importCityCatalog}=require('../dist/src/geo/import-city-catalog');
const {GeoService}=require('../dist/src/geo/geo.service');
test('catalog import preserves existing IDs, disabled cities, coordinates and tariffs; repeated import is idempotent',async()=>{
 const rows=[{id:'existing',name:'Лениногорск',aliases:[],countryCode:'KZ',lat:50.34,lng:83.51,region:'ВКО',isActive:false,tariffs:['retained']}];
 const tx={ $executeRawUnsafe:async()=>{}, city:{findMany:async()=>rows,update:async({where,data})=>Object.assign(rows.find(c=>c.id===where.id),data),createMany:async({data})=>rows.push(...data)}};
 const db={$transaction:async fn=>fn(tx)};
 const catalog=[{name:'Риддер',aliases:['Риддер','Лениногорск'],countryCode:'KZ',lat:50.344,lng:83.513,region:'ВКО'},
 {name:'Актау',aliases:['Актау'],countryCode:'KZ',lat:43.65,lng:51.15},
 {name:'Актау',aliases:['Актау'],countryCode:'KZ',lat:48.04,lng:72.81},
 {name:'Актау',aliases:['Актау'],countryCode:'RU',lat:55,lng:70}];
 const first=await importCityCatalog(db,catalog);assert.equal(first.added,3);
 assert.equal(rows[0].id,'existing');assert.equal(rows[0].isActive,false);assert.equal(rows[0].lat,50.34);
 assert.deepEqual(rows[0].tariffs,['retained']);assert.equal(rows[0].name,'Риддер');
 const second=await importCityCatalog(db,catalog);assert.equal(second.added,0);assert.equal(second.enriched,0);assert.equal(rows.length,4);
});
test('city selection uses only active database entries and their aliases, returning IDs and country currency',async()=>{
 const rows=[{id:'custom',name:'Тестовое село',aliases:['Старое название'],lat:49,lng:82,countryCode:'KZ',region:'Абайская область'}];
 const service=new GeoService({city:{findMany:async({where})=>{assert.equal(where.isActive,true);return rows;}}},{get:()=>undefined});
 service.fetchCitySearchResults=async()=>{throw Error('must never contact map city search');};
 const result=await service.searchCities('старое название');assert.equal(result[0].id,'custom');assert.equal(result[0].currency,'KZT');
 assert.deepEqual(await service.searchCities('Москва'),[]);
});
