const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto'),fs=require('node:fs'),path=require('node:path');
const {PrismaClient}=require('@prisma/client'),{DriverService}=require('../dist/src/driver/driver.service');
const database=process.env.TARIFF_TEST_DATABASE_URL;
test('legacy city preferences merge once; unified on/off persists both city dispatch modes',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/(ui_review_|dispatch_test)/);
 const p=new PrismaClient({datasources:{db:{url:database}}}),rollback=Error('rollback unified modes');
 try{await assert.rejects(p.$transaction(async tx=>{
  const profiles=[];for(const [fixed,auction] of [[false,false],[true,false],[false,true],[true,true]]) {
   const user=await tx.user.create({data:{phone:'city-mode:'+randomUUID(),password:'qa',name:'QA',refCode:randomUUID(),refLink:'test'}});
   profiles.push(await tx.driverProfile.create({data:{userId:user.id,status:'APPROVED',acceptCityFixed:fixed,acceptCityAuction:auction,acceptDelivery:false,acceptCargo:false}}));
  }
  const migration=fs.readFileSync(path.join(__dirname,'../prisma/migrations/20261028141000_unify_city_trip_preferences/migration.sql'),'utf8');
  await tx.$executeRawUnsafe(migration);
  for(let i=0;i<profiles.length;i++) {
   let row=await tx.driverProfile.findUnique({where:{id:profiles[i].id}});assert.equal(row.acceptCityFixed,i>0);assert.equal(row.acceptCityAuction,i>0);
   const service=new DriverService(tx);
   for(const enabled of [false,true]) {
    await service.updateServiceModes(row.userId,{acceptCityFixed:enabled,acceptCityAuction:enabled});row=await tx.driverProfile.findUnique({where:{id:row.id}});
    assert.equal(row.acceptCityFixed,enabled);assert.equal(row.acceptCityAuction,enabled);assert.equal(row.status,'APPROVED');assert.equal(row.acceptDelivery,false);assert.equal(row.acceptCargo,false);
   }
  }
  throw rollback;
 },{timeout:60000}),e=>e===rollback)}finally{await p.$disconnect()}
});
