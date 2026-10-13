const {test}=require('node:test');const assert=require('node:assert/strict');const {PrismaClient}=require('@prisma/client');const {seedAllCityTariffs}=require('../scripts/seed-all-city-tariffs.cjs');
const database=process.env.DISPATCH_TEST_DATABASE_URL;
test('bulk tariffs preserve existing rates, disabled cities, country boundaries and idempotency',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/dispatch_test');
 const p=new PrismaClient({datasources:{db:{url:database}}});const prefix='tariff-test-'+Date.now();const cities=[];
 try {
  for(const [index,countryCode] of ['KZ','RU','KZ','RU','US'].entries()) cities.push(await p.city.create({data:{name:prefix+index,countryCode,lat:40,lng:60,isActive:index!==3}}));
  const custom=await p.tariffCity.create({data:{cityId:cities[2].id,name:'Custom',basePrice:0,pricePerKm:80,pricePerMin:0,minPrice:500}});
  const inactive=await p.tariffCity.create({data:{cityId:cities[3].id,name:'Disabled',isActive:false,basePrice:200,pricePerKm:40,pricePerMin:8,minPrice:300}});
  const where={id:{in:cities.map(c=>c.id)},countryCode:{in:['KZ','RU']}};
  const first=await seedAllCityTariffs(p,where);assert.equal(first.KZ.created,1);assert.equal(first.RU.created,2);
  assert.deepEqual(await p.tariffCity.findUnique({where:{id:custom.id}}),custom);assert.deepEqual(await p.tariffCity.findUnique({where:{id:inactive.id}}),inactive);
  assert.equal((await p.city.findUnique({where:{id:cities[3].id}})).isActive,false);assert.equal(await p.tariffCity.count({where:{cityId:cities[4].id}}),0);
  assert.equal((await p.tariffCity.findFirst({where:{cityId:cities[0].id,isActive:true}})).minPrice,700);assert.equal((await p.tariffCity.findFirst({where:{cityId:cities[1].id,isActive:true}})).minPrice,150);
  const count=await p.tariffCity.count({where:{cityId:{in:cities.map(c=>c.id)}}});const second=await seedAllCityTariffs(p,where);assert.equal(second.KZ.created+second.RU.created,0);assert.equal(await p.tariffCity.count({where:{cityId:{in:cities.map(c=>c.id)}}}),count);
  await p.tariffCity.create({data:{cityId:cities[0].id,name:'Invalid',basePrice:0,pricePerKm:0,pricePerMin:0,minPrice:0}});await assert.rejects(seedAllCityTariffs(p,where),/requires review/);assert.equal(await p.tariffCity.count({where:{cityId:{in:cities.map(c=>c.id)}}}),count+1);
 } finally {
  await p.tariffCity.deleteMany({where:{cityId:{in:cities.map(c=>c.id)}}});await p.city.deleteMany({where:{id:{in:cities.map(c=>c.id)}}});await p.$disconnect();
 }
});

const {OrdersService}=require('../dist/src/orders/orders.service');
test('new-city preview provisions country rates once and respects manual tariff disabling',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/dispatch_test');
 const p=new PrismaClient({datasources:{db:{url:database}}});const cities=[];
 try {
  for(const countryCode of ['KZ','RU']) {
   const city=await p.city.create({data:{name:'new-tariff-'+countryCode+'-'+Date.now(),countryCode,lat:40,lng:60}});cities.push(city);
   const service=new OrdersService(p,{reverseGeocode:async()=>({cityId:city.id,currency:countryCode==='RU'?'RUB':'KZT'}),getRoute:async()=>({distance:1,duration:1})},{},{},{});
   const dto={fromLat:40,fromLng:60,toLat:40.01,toLng:60.01,mode:'CITY'};
   const results=await Promise.all([service.previewOrder(dto),service.previewOrder(dto)]);
   assert.equal(await p.tariffCity.count({where:{cityId:city.id}}),1);
   assert.equal(results[0].currency,countryCode==='RU'?'RUB':'KZT');assert.equal(results[0].price,countryCode==='RU'?150:700);assert.equal(results[0].tariff.id,results[1].tariff.id);
   await p.tariffCity.update({where:{id:results[0].tariff.id},data:{isActive:false}});
   await assert.rejects(service.previewOrder(dto),/City tariff is not configured/);
   assert.equal(await p.tariffCity.count({where:{cityId:city.id}}),1);
  }
 } finally {await p.tariffCity.deleteMany({where:{cityId:{in:cities.map(c=>c.id)}}});await p.city.deleteMany({where:{id:{in:cities.map(c=>c.id)}}});await p.$disconnect();}
});
