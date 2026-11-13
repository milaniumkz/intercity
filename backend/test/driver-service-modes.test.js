const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {PrismaClient}=require('@prisma/client'),{DriverService}=require('../dist/src/driver/driver.service');
const database=process.env.TARIFF_TEST_DATABASE_URL;
test('service modes persist without resetting verification, vehicle, online state or other drivers',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/(ui_review_|dispatch_test)/);
 const p=new PrismaClient({datasources:{db:{url:database}}}),rollback=Error('rollback modes');
 try{await assert.rejects(p.$transaction(async tx=>{
  const users=[];for(let i=0;i<2;i++) users.push(await tx.user.create({data:{phone:'modes:'+randomUUID(),password:'qa',name:'QA',refCode:randomUUID(),refLink:'test'}}));
  const profiles=[];for(const user of users) profiles.push(await tx.driverProfile.create({data:{userId:user.id,status:'APPROVED',carModel:'QA car',carNumber:'QA001',acceptDelivery:false,online:{create:{isOnline:true}}}}));
  const s=new DriverService(tx);
  const result=await s.updateServiceModes(users[0].id,{acceptDelivery:true,acceptCargo:false,status:'PENDING',carModel:'wrong'});
  assert.equal(result.acceptDelivery,true);assert.equal(result.acceptCargo,false);assert.equal(result.status,'APPROVED');assert.equal(result.carModel,'QA car');assert.equal(result.carNumber,'QA001');
  assert.equal((await tx.driverOnline.findUnique({where:{driverId:profiles[0].id}})).isOnline,true);
  assert.equal((await tx.driverProfile.findUnique({where:{id:profiles[1].id}})).acceptDelivery,false);
  await s.updateServiceModes(users[0].id,{acceptDelivery:false});assert.equal((await tx.driverProfile.findUnique({where:{id:profiles[0].id}})).acceptDelivery,false);
  await assert.rejects(s.updateServiceModes(randomUUID(),{acceptDelivery:true}),/не найден/);
  throw rollback;
 }),e=>e===rollback)}finally{await p.$disconnect()}
});

test('first GPS update creates offline presence and repeated updates preserve online state', {skip:!database}, async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/(ui_review_|dispatch_test)/);
 const p=new PrismaClient({datasources:{db:{url:database}}}),rollback=Error('rollback location');
 try {await assert.rejects(p.$transaction(async tx=>{
  const user=await tx.user.create({data:{phone:'qa-location:0'+randomUUID(),name:'QA location',password:'qa',refCode:randomUUID(),refLink:'test'}});
  const profile=await tx.driverProfile.create({data:{userId:user.id,status:'APPROVED'}});
  const service=new DriverService({...tx,$transaction:fn=>fn(tx)},{reverseGeocode:async()=>({cityId:null})}, {publish(){}});
  for(let i=0;i<20;i++) {
   const result=await service.updateLocation(user.id,{lat:49.97+i/10000,lng:82.61,accuracy:10,sampledAt:new Date().toISOString()});
   assert.equal(result.isOnline,false);assert.ok(Math.abs(result.lastLat-(49.97+i/10000))<1e-8);assert.equal(result.lastAccuracy,10);
  }
  await tx.driverOnline.update({where:{driverId:profile.id},data:{isOnline:true}});
  service.ensureDriverCanStayOnline=async()=>{};
  assert.equal((await service.updateLocation(user.id,{lat:49.98,lng:82.62})).isOnline,true);
  assert.equal(await tx.driverOnline.count({where:{driverId:profile.id}}),1);
  throw rollback;
 }),e=>e===rollback)}finally{await p.$disconnect()}
});
