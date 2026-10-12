const {test}=require('node:test');
const assert=require('node:assert/strict');
const {PrismaClient}=require('@prisma/client');
const {passengerLeaving}=require('../dist/src/common/passenger-leaving');
const database=process.env.DISPATCH_TEST_DATABASE_URL;

test('passenger leaving is owner-only, arrival-only and idempotent across concurrent requests',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/dispatch_test');
 const p=new PrismaClient({datasources:{db:{url:database}}});
 const key='leaving-'+Date.now();const events=[],pushes=[];
 const realtime={publish:e=>events.push(e)};const push={sendToUser:async(id,data)=>{pushes.push({id,data});return true}};
 let passenger,driver;
 try {
  passenger=await p.user.create({data:{phone:key+'-p',password:'test-only',name:'Test',refCode:key+'-p',refLink:'test-only'}});
  const user=await p.user.create({data:{phone:key+'-d',password:'test-only',name:'Test',role:'DRIVER',refCode:key+'-d',refLink:'test-only'}});
  driver=await p.driverProfile.create({data:{userId:user.id,status:'APPROVED'}});
  for(const kind of ['CITY','INTERCITY']) {
   const model=kind==='CITY'?p.order:p.intercityRequest;
   const trip=await model.create({data:kind==='CITY'?
    {passengerId:passenger.id,driverId:driver.id,status:'DRIVER_EN_ROUTE',fromLat:49.95,fromLng:82.6,toLat:49.96,toLng:82.61,fromAddress:'A',toAddress:'B',price:700}:
    {passengerId:passenger.id,selectedDriverId:driver.userId,status:'DRIVER_ASSIGNED',fromCity:'A',toCity:'B',fromLat:49.95,fromLng:82.6,toLat:49.96,toLng:82.61,requestType:'INTERCITY',seats:1,price:700,date:new Date()}});
   const call=owner=>passengerLeaving(p,kind,trip.id,owner,realtime,push);
   await assert.rejects(call('unrelated-user'),e=>e.status===403);
   await assert.rejects(call(passenger.id),e=>e.status===400);
   assert.equal(events.length,kind==='CITY'?0:1);
   await model.update({where:{id:trip.id},data:{status:'DRIVER_ARRIVED'}});
   const before=pushes.length;
   const [first,second]=await Promise.all([call(passenger.id),call(passenger.id)]);
   assert.equal(first.sent,true);assert.equal(first.passengerLeavingAt.toISOString(),second.passengerLeavingAt.toISOString());
   assert.equal(pushes.length,before+1);assert.equal(events.length,before+1);
   const event=events.at(-1);assert.equal(event.entityId,driver.id);assert.equal(event.payload.tripId,trip.id);assert.equal(event.payload.isIntercity,kind==='INTERCITY');
   assert.equal(pushes.at(-1).id,driver.userId);assert.equal(pushes.at(-1).data.data.route,'/driver/home');
   assert.ok((await model.findUnique({where:{id:trip.id}})).passengerLeavingAt);
   await call(passenger.id);assert.equal(pushes.length,before+1);
   await model.update({where:{id:trip.id},data:{status:'IN_PROGRESS'}});
   await assert.rejects(call(passenger.id),e=>e.status===400);
   await model.delete({where:{id:trip.id}});
  }
 } finally {
  if(passenger){await p.order.deleteMany({where:{passengerId:passenger.id}});await p.intercityRequest.deleteMany({where:{passengerId:passenger.id}});await p.user.delete({where:{id:passenger.id}});}
  if(driver){await p.driverProfile.delete({where:{id:driver.id}});await p.user.delete({where:{id:driver.userId}});}
  await p.$disconnect();
 }
});
