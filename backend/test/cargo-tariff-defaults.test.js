const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {PrismaClient}=require('@prisma/client');
const database=process.env.TARIFF_TEST_DATABASE_URL;
test('cargo defaults are idempotent and preserve configured rates',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/(ui_review_|dispatch_test)/);
 const p=new PrismaClient({datasources:{db:{url:database}}}),rollback=Error('rollback cargo tariffs');
 const sql=fs.readFileSync(path.join(__dirname,'../prisma/migrations/20261029051000_cargo_tariff_defaults/migration.sql'),'utf8');
 try{await assert.rejects(p.$transaction(async tx=>{
  await tx.tariffCargo.deleteMany({where:{countryCode:{in:['KZ','RU']}}});
  const old=await tx.tariffCargo.create({data:{countryCode:'RU',name:'Operator rate',basePrice:777,pricePerKm:33,pricePerKg:7,minPrice:999}});
  await tx.$executeRawUnsafe(sql);await tx.$executeRawUnsafe(sql);
  const kz=await tx.tariffCargo.findMany({where:{countryCode:'KZ'}});assert.equal(kz.length,1);assert.equal(kz[0].pricePerKm,100);assert.equal(kz[0].pricePerKg,20);assert.equal(kz[0].minPrice,1500);
  assert.deepEqual(await tx.tariffCargo.findMany({where:{countryCode:'RU'}}),[old]);
  throw rollback;
 }),e=>e===rollback)}finally{await p.$disconnect()}
});
