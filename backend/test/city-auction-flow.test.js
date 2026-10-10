const {test}=require('node:test');const assert=require('node:assert/strict');const {PrismaClient}=require('@prisma/client');
const {OrdersService}=require('../dist/src/orders/orders.service');const {AutoDispatchService}=require('../dist/src/orders/auto-dispatch.service');const {DriverService}=require('../dist/src/driver/driver.service');
const database=process.env.DISPATCH_TEST_DATABASE_URL;
test('taxi broadcast, passenger confirmation, 30s expiry and activity accounting',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/dispatch_test');
 const p=new PrismaClient({datasources:{db:{url:database}}});const key='auction-'+Date.now();const pushes=[];const realtime={publish:()=>{}};const push={sendToUser:async id=>{pushes.push(id);return true},sendOrderStatusToPassenger:async()=>true};let city,passenger;const drivers=[];
 try{
  city=await p.city.create({data:{name:key,countryCode:'KZ',lat:49.95,lng:82.6}});
  passenger=await p.user.create({data:{phone:key+'-p',password:'test-only',name:'Passenger',refCode:key+'-p',refLink:'test-only'}});
  for(let i=0;i<4;i++){
   const user=await p.user.create({data:{phone:key+'-'+i,password:'test-only',role:'DRIVER',name:'Driver',refCode:key+'-'+i,refLink:'test-only',wallet:{create:{money:10000}}}});
   drivers.push(await p.driverProfile.create({data:{userId:user.id,status:'APPROVED',acceptCityAuction:true,acceptIntercity:false,online:{create:{isOnline:true,cityId:city.id,lastLat:49.95,lastLng:82.6,lastLocationAt:new Date()}},serviceStats:{create:{activityScore:82}}}}));
  }
  const dispatch=new AutoDispatchService(p,realtime,push);const geo={reverseGeocode:async()=>({cityId:city.id,currency:'KZT'}),getRoute:async()=>({distance:2.1,duration:4})};const service=new OrdersService(p,geo,dispatch,realtime,push,{state:async()=>null});const driverApi=new DriverService(p,{},realtime,push,dispatch);
  const create=()=>service.createOrder(passenger.id,{fromLat:49.95,fromLng:82.6,toLat:49.96,toLng:82.61,fromAddress:'A',toAddress:'B',mode:'CITY',requestType:'CITY_AUCTION',desiredPrice:700,vehicleClass:'ECONOMY',paymentMethod:'CASH'});
  const score=async d=>(await p.driverServiceStats.findUnique({where:{driverId:d.id}})).activityScore;
  const order=await create();assert.equal(order.price,700);assert.equal(order.vehicleClass,'ECONOMY');assert.equal(order.distanceKm,2.1);assert.equal(pushes.length,4);
  for(const d of drivers)assert.ok((await driverApi.getNearbyOrders(d.userId)).some(o=>o.id===order.id));
  const offer=await service.createOrderOffer(order.id,drivers[0].userId,{price:700});assert.ok(offer.expiresAt-new Date()>25000 && offer.expiresAt-new Date()<=30000);assert.equal((await p.order.findUnique({where:{id:order.id}})).driverId,null);
  assert.deepEqual(await driverApi.getNearbyOrders(drivers[0].userId),[]);await service.rejectOrderOffer(offer.id,passenger.id);assert.equal(await score(drivers[0]),82);await assert.rejects(service.acceptOrderOffer(offer.id,passenger.id));
  const rejectedView=await service.getOrder(order.id,{userId:drivers[0].userId,role:'PASSENGER'});assert.equal(rejectedView.offers.find(item=>item.id===offer.id).status,'REJECTED');await assert.rejects(service.getOrder(order.id,{userId:'unrelated-user',role:'PASSENGER'}));
  const expired=await service.createOrderOffer(order.id,drivers[1].userId,{price:800});await p.orderOffer.update({where:{id:expired.id},data:{expiresAt:new Date(Date.now()-1000)}});await assert.rejects(service.acceptOrderOffer(expired.id,passenger.id));
  await driverApi.rejectOrder(drivers[2].userId,order.id);assert.equal(await score(drivers[2]),79);
  await p.orderAuctionInvitation.updateMany({where:{orderId:order.id,driverId:drivers[3].id},data:{expiresAt:new Date(Date.now()-1000)}});await dispatch.processQueue();assert.equal((await p.orderOffer.findUnique({where:{id:expired.id}})).status,'EXPIRED');assert.equal(await score(drivers[1]),82);assert.equal(await score(drivers[3]),79);await dispatch.processQueue();assert.equal(await score(drivers[3]),79);
  await p.orderOffer.updateMany({where:{orderId:order.id},data:{status:'REJECTED'}});
  const beforeRound=pushes.length;await dispatch.assignCityOrder(order.id);assert.equal(pushes.length,beforeRound);
  await p.orderAuctionInvitation.updateMany({where:{orderId:order.id},data:{createdAt:new Date(Date.now()-120000)}});
  await p.orderOffer.updateMany({where:{orderId:order.id},data:{updatedAt:new Date(Date.now()-61000)}});
  await dispatch.assignCityOrder(order.id);assert.equal(pushes.length,beforeRound+3);
  assert.equal(await p.orderAuctionInvitation.count({where:{orderId:order.id,status:'PENDING'}}),3);
  assert.equal(await score(drivers[0]),82);assert.equal(await score(drivers[1]),82);
  const newPrice=await service.increaseAuctionPrice(order.id,passenger.id);assert.equal(newPrice.price,800);
  assert.equal(pushes.length,beforeRound+6);assert.equal(await score(drivers[0]),82);
  await assert.rejects(service.increaseAuctionPrice(order.id,drivers[0].userId));
  await p.order.update({where:{id:order.id},data:{status:'CANCELLED'}});await p.driverOnline.updateMany({where:{driverId:{in:drivers.map(d=>d.id)}},data:{isOnline:true,lastLocationAt:new Date()}});
  const second=await create();const a=await service.createOrderOffer(second.id,drivers[0].userId,{price:700});const b=await service.createOrderOffer(second.id,drivers[1].userId,{price:900});const result=await Promise.allSettled([service.acceptOrderOffer(a.id,passenger.id),service.acceptOrderOffer(b.id,passenger.id)]);assert.equal(result.filter(x=>x.status==='fulfilled').length,1);
  const trip=await p.order.findUnique({where:{id:second.id}});assert.equal(trip.status,'DRIVER_EN_ROUTE');assert.ok([700,900].includes(trip.price));assert.equal(await p.orderAuctionInvitation.count({where:{orderId:second.id,status:'PENDING'}}),0);await assert.rejects(service.rejectOrderOffer(trip.selectedOfferId,passenger.id));assert.equal(await score({id:trip.driverId}),85);
 }finally{
  if(passenger){const ids=(await p.order.findMany({where:{passengerId:passenger.id},select:{id:true}})).map(x=>x.id);await p.rideEvent.deleteMany({where:{orderId:{in:ids}}});await p.orderOffer.deleteMany({where:{orderId:{in:ids}}});await p.order.deleteMany({where:{id:{in:ids}}});}
  await p.driverActivityEvent.deleteMany({where:{driverId:{in:drivers.map(d=>d.id)}}});for(const d of drivers){await p.driverOnline.deleteMany({where:{driverId:d.id}});await p.driverServiceStats.deleteMany({where:{driverId:d.id}});await p.driverProfile.delete({where:{id:d.id}});await p.wallet.deleteMany({where:{userId:d.userId}});await p.user.delete({where:{id:d.userId}});}if(passenger)await p.user.delete({where:{id:passenger.id}});if(city)await p.city.delete({where:{id:city.id}});await p.$disconnect();
 }
});
