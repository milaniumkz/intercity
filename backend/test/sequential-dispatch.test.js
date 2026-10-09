const {test}=require('node:test');const assert=require('node:assert/strict');
const {PrismaClient}=require('@prisma/client');
const {AutoDispatchService}=require('../dist/src/orders/auto-dispatch.service');
const {DriverService}=require('../dist/src/driver/driver.service');
const database=process.env.DISPATCH_TEST_DATABASE_URL;
test('durable sequential dispatch: rejection, timeout, repeat rounds, restart, exclusive acceptance and cancellation', {skip:!database}, async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/dispatch_test$/);
 const p=new PrismaClient({datasources:{db:{url:database}}});
 const prefix='dispatch-'+Date.now();
 const realtime={publish:()=>{}};const pushes=[];
 const push={sendToUser:async(userId)=>{pushes.push(userId);return true},sendOrderStatusToPassenger:async()=>true};
 try {
  const city=await p.city.create({data:{name:prefix,countryCode:'KZ',lat:49.9,lng:82.6}});
  const passenger=await p.user.create({data:{phone:prefix+'-p',password:'test-only',name:'Test',refCode:prefix+'-p',refLink:'test-only'}});
  const drivers=[];
  for(let i=0;i<3;i++){
   const user=await p.user.create({data:{phone:prefix+'-'+i,password:'test-only',name:'Test',role:'DRIVER',refCode:prefix+'-'+i,refLink:'test-only',wallet:{create:{money:10000}}}});
   const driver=await p.driverProfile.create({data:{userId:user.id,status:'APPROVED',acceptIntercity:false,acceptCityAuction:false,
    online:{create:{isOnline:true,cityId:city.id,lastLat:49.9,lastLng:82.6,lastLocationAt:new Date()}},serviceStats:{create:{activityScore:100}}}});
   drivers.push({id:driver.id,userId:user.id});
  }
  const makeService=()=>{const s=new AutoDispatchService(p,realtime,push);s.computeScore=async d=>({driverId:d.driverId,totalScore:100,priorityScore:100-drivers.findIndex(x=>x.id===d.driverId),activityScore:50,ratingScore:0,distanceScore:50,randomJitter:0});return s};
  const dispatch=makeService();const driverApi=new DriverService(p,{},realtime,push,dispatch);
  const create=()=>p.order.create({data:{passengerId:passenger.id,cityId:city.id,fromLat:49.9,fromLng:82.6,toLat:49.91,toLng:82.61,fromAddress:'Test start',toAddress:'Test end'}});
  const read=id=>p.order.findUnique({where:{id}});
  const expired=id=>p.order.update({where:{id},data:{dispatchExpiresAt:new Date(Date.now()-1000)}});
  const retry=id=>p.order.update({where:{id},data:{dispatchRetryAt:new Date(Date.now()-1000)}});
  const nearby=async d=>(await driverApi.getNearbyOrders(d.userId)).map(o=>o.id);
  const a=await create();
  await Promise.all([dispatch.assignCityOrder(a.id),makeService().assignCityOrder(a.id),dispatch.assignCityOrder(a.id)]);
  assert.equal((await read(a.id)).status,'SEARCHING_DRIVER');assert.equal((await read(a.id)).driverId,null);
  assert.equal((await read(a.id)).dispatchDriverId,drivers[0].id);assert.equal(pushes.length,1);
  assert.deepEqual(await nearby(drivers[0]),[a.id]);assert.deepEqual(await nearby(drivers[1]),[]);assert.deepEqual(await nearby(drivers[2]),[]);
  const deadline=(await read(a.id)).dispatchExpiresAt.getTime();await nearby(drivers[0]);assert.equal((await read(a.id)).dispatchExpiresAt.getTime(),deadline);
  await assert.rejects(driverApi.acceptOrder(drivers[1].userId,a.id));await assert.rejects(driverApi.rejectOrder(drivers[1].userId,a.id));
  for(let i=0;i<3;i++){
   assert.equal((await read(a.id)).dispatchDriverId,drivers[i].id);
   await driverApi.rejectOrder(drivers[i].userId,a.id);
  }
  const waiting=await read(a.id);assert.equal(waiting.status,'SEARCHING_DRIVER');assert.equal(waiting.dispatchDriverId,null);assert.ok(waiting.dispatchRetryAt>new Date());
  await makeService().processQueue();assert.equal((await read(a.id)).dispatchDriverId,null);
  await retry(a.id);await makeService().processQueue();assert.equal((await read(a.id)).dispatchDriverId,drivers[0].id);
  await driverApi.rejectOrder(drivers[0].userId,a.id);assert.equal((await p.driverServiceStats.findUnique({where:{driverId:drivers[0].id}})).activityScore,94);
  assert.equal((await read(a.id)).dispatchDriverId,drivers[1].id);
  await expired(a.id);await assert.rejects(driverApi.acceptOrder(drivers[1].userId,a.id));
  await makeService().processQueue();assert.equal((await read(a.id)).dispatchDriverId,drivers[2].id);
  assert.equal((await p.driverOnline.findUnique({where:{driverId:drivers[1].id}})).isOnline,false);
  assert.equal((await p.driverServiceStats.findUnique({where:{driverId:drivers[1].id}})).activityScore,94);
  await dispatch.assignCityOrder(a.id);
  assert.equal((await p.driverServiceStats.findUnique({where:{driverId:drivers[1].id}})).activityScore,94);
  const results=await Promise.allSettled([driverApi.acceptOrder(drivers[2].userId,a.id),driverApi.acceptOrder(drivers[2].userId,a.id),driverApi.acceptOrder(drivers[1].userId,a.id)]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal((await read(a.id)).driverId,drivers[2].id);
  await dispatch.assignCityOrder(a.id);assert.equal((await read(a.id)).status,'DRIVER_EN_ROUTE');
  assert.equal((await p.driverServiceStats.findUnique({where:{driverId:drivers[2].id}})).activityScore,100);
  await p.driverOnline.update({where:{driverId:drivers[1].id},data:{isOnline:true}});
  const b=await create(),c=await create();
  await Promise.all([dispatch.assignCityOrder(b.id),makeService().assignCityOrder(c.id)]);
  const pending=await p.order.findMany({where:{id:{in:[b.id,c.id]}},select:{dispatchDriverId:true}});
  assert.equal(new Set(pending.map(o=>o.dispatchDriverId)).size,2);assert.ok(pending.every(o=>o.dispatchDriverId&&o.dispatchDriverId!==drivers[2].id));
  await p.order.updateMany({where:{id:{in:[b.id,c.id]}},data:{status:'CANCELLED'}});
  await Promise.all([dispatch.assignCityOrder(b.id),dispatch.assignCityOrder(c.id)]);
  assert.deepEqual(await nearby(drivers[0]),[]);assert.deepEqual(await nearby(drivers[1]),[]);
  assert.equal((await read(b.id)).status,'CANCELLED');assert.equal((await read(c.id)).status,'CANCELLED');
  await p.driverOnline.updateMany({where:{driverId:{in:drivers.map(d=>d.id)}},data:{isOnline:false}});
  const d=await create();await dispatch.assignCityOrder(d.id);assert.equal((await read(d.id)).dispatchDriverId,null);
  await p.driverOnline.update({where:{driverId:drivers[0].id},data:{isOnline:true}});
  await retry(d.id);await makeService().processQueue();assert.equal((await read(d.id)).dispatchDriverId,drivers[0].id);
  await p.order.update({where:{id:d.id},data:{status:'CANCELLED'}});
 }finally{await p.$disconnect()}
});
