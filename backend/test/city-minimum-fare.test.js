const {test}=require('node:test'),assert=require('node:assert/strict');
const {cityTariffDefaults}=require('../dist/src/common/city-tariff-defaults');
const {AdminService}=require('../dist/src/admin/admin.service');
const {OrdersService}=require('../dist/src/orders/orders.service');
const policy=rate=>JSON.stringify({priceKzt:1000,kztPerRub:rate,durationHours:12,firstAccessSeconds:30});
test('new city minimum uses the exact existing administrative exchange rate',async()=>{
 for(const rate of [5,7,6.25,10]) {
  const db={appSettings:{findUnique:async({where})=>{assert.equal(where.key,'driverRouteTopPolicy');return {value:policy(rate)}}}};
  assert.equal((await cityTariffDefaults(db,'KZ')).minPrice,500);
  assert.equal((await cityTariffDefaults(db,'RU')).minPrice,Number((500/rate).toFixed(2)));
 }
});
test('saving administrative exchange rate recalculates Russian city minima atomically',async()=>{
 const calls=[];const tx={appSettings:{upsert:async args=>{calls.push(args);return {value:args.update.value}}},tariffCity:{updateMany:async args=>calls.push(args)}};
 const admin=new AdminService({$transaction:async fn=>fn(tx)});
 await admin.setSetting('driverRouteTopPolicy',policy(5));
 assert.equal(JSON.parse(calls[0].update.value).kztPerRub,5);
 assert.deepEqual(calls[1],{where:{city:{countryCode:'RU'}},data:{minPrice:100}});
});
test('RUB minimum is not inflated to the old 50-ruble step',()=>{
 const service=new OrdersService();
 assert.equal(service.roundRidePrice(71.43,'RUB'),71.43);
 assert.equal(service.roundRidePrice(500,'KZT'),500);
 assert.equal(service.roundRidePrice(501,'KZT'),550);
});
const database=process.env.DISPATCH_TEST_DATABASE_URL;
test('migration updates every KZ/RU tariff from admin rate and preserves other rates and countries',{skip:!database},async()=>{
 const {PrismaClient}=require('@prisma/client'),fs=require('node:fs');
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/dispatch_test');
 const p=new PrismaClient({datasources:{db:{url:database}}}),rollback=new Error('rollback');
 try {
  await assert.rejects(p.$transaction(async tx=>{
   await tx.appSettings.upsert({where:{key:'driverRouteTopPolicy'},create:{key:'driverRouteTopPolicy',value:policy(5)},update:{value:policy(5)}});
   const rows=[];
   for(const countryCode of ['KZ','RU','US']) {
    const city=await tx.city.create({data:{name:'minimum-qa-'+countryCode,lat:40,lng:60,countryCode}});
    const tariff=await tx.tariffCity.create({data:{cityId:city.id,name:'QA',basePrice:80,pricePerKm:10,pricePerMin:2,minPrice:150,isActive:false}});rows.push({city,tariff});
   }
   const missing=await tx.city.create({data:{name:'minimum-qa-no-tariff',lat:40,lng:60,countryCode:'RU'}});
   const sql=fs.readFileSync(require('node:path').join(__dirname,'../prisma/migrations/20261104160000_city_minimum_fare/migration.sql'),'utf8');
   for(const statement of sql.replace(/^--.*$/gm,'').split(';').filter(s=>s.trim())) await tx.$executeRawUnsafe(statement);
   for(const {city,tariff} of rows) {
    const after=await tx.tariffCity.findUnique({where:{id:tariff.id}});
    assert.equal(after.minPrice,city.countryCode==='KZ'?500:city.countryCode==='RU'?100:150);
    for(const field of ['basePrice','pricePerKm','pricePerMin','isActive']) assert.equal(after[field],tariff[field]);
   }
   assert.equal((await tx.tariffCity.findFirst({where:{cityId:missing.id}})).minPrice,100);
   assert.equal((await tx.appSettings.findUnique({where:{key:'driverRouteTopPolicy'}})).value,policy(5));
   throw rollback;
  },{timeout:120000}),err=>err===rollback);
 } finally {await p.$disconnect()}
});
