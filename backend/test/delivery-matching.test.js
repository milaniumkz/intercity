const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {PrismaClient}=require('@prisma/client');
const {DriverService}=require('../dist/src/driver/driver.service');
const database=process.env.TARIFF_TEST_DATABASE_URL;
test('future deliveries are visible with GPS and no assigned city, while disabled delivery stays hidden',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/(ui_review_|dispatch_test)/);
 const p=new PrismaClient({datasources:{db:{url:database}}}),rollback=Error('rollback delivery QA');
 try {await assert.rejects(p.$transaction(async tx=>{
  const db=new Proxy(tx,{get:(t,k)=>k==='$transaction'?fn=>fn(db):t[k]});
  const id=randomUUID();
  const user=await tx.user.create({data:{phone:'delivery:'+id,password:'fixture',name:'Local QA',refCode:id,refLink:'test',role:'DRIVER'}});
  const profile=await tx.driverProfile.create({data:{userId:user.id,status:'ACTIVE',acceptDelivery:true,acceptIntercity:false,acceptCityAuction:false}});
  await tx.driverOnline.create({data:{driverId:profile.id,isOnline:true,lastLat:49.95,lastLng:82.61}});
  const wanted=await tx.intercityRequest.create({data:{passengerId:'qa-passenger',requestType:'DELIVERY_CITY',fromCity:'Усть-Каменогорск',toCity:'Усть-Каменогорск',fromLat:49.96,fromLng:82.61,toLat:49.97,toLng:82.62,fromAddressLabel:'Шакарима 143',toAddressLabel:'Сатпаева 1',date:new Date(Date.now()+172800000),price:1500,status:'OPEN'}});
  const driver=new DriverService(db,{}, {}, {}, {}, {});
  assert((await driver.getMatchingIntercityRequests(user.id)).some(r=>r.id===wanted.id));
  await tx.driverProfile.update({where:{id:profile.id},data:{acceptDelivery:false}});
  assert(!(await driver.getMatchingIntercityRequests(user.id)).some(r=>r.id===wanted.id));
  throw rollback;
 },{timeout:30000}),e=>e===rollback);}finally{await p.$disconnect();}
});
