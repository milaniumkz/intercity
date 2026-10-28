const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {routeRequestTimeRange,routeMatchesRequestSchedule}=require('../dist/src/common/driver-route-schedule');
const {PrismaClient}=require('@prisma/client'),{DriverService}=require('../dist/src/driver/driver.service'),{IntercityService}=require('../dist/src/intercity/intercity.service');
test('same local departure day and cutoff include boundary times but exclude adjacent days and expired departures',()=>{
 const now=new Date('2026-10-28T08:00:00Z'),route={departureAt:'2026-10-29T11:00:00Z',departureOffsetMinutes:300};
 const range=routeRequestTimeRange(route,now);assert.equal(range.gte.toISOString(),'2026-10-28T19:00:00.000Z');assert.equal(range.lte.toISOString(),'2026-10-29T11:00:00.000Z');
 for(const [date,expected]of [['2026-10-28T18:59:59Z',false],['2026-10-28T19:00:00Z',true],['2026-10-29T10:59:59Z',true],['2026-10-29T11:00:00Z',true],['2026-10-29T11:00:01Z',false],['2026-10-29T19:00:00Z',false]])assert.equal(routeMatchesRequestSchedule(route,{date},now),expected,date);
 assert.equal(routeMatchesRequestSchedule(route,{date:'2026-10-29T07:00:00Z'},new Date('2026-10-29T10:00:00Z')),true);
 assert.equal(routeRequestTimeRange(route,new Date('2026-10-29T11:00:00Z')),null);assert.equal(routeRequestTimeRange({},now),null);
 const west=routeRequestTimeRange({departureAt:'2026-10-29T23:00:00Z',departureOffsetMinutes:-420},now);assert.equal(west.gte.toISOString(),'2026-10-29T07:00:00.000Z');
});
const database=process.env.TARIFF_TEST_DATABASE_URL;
test('scheduled route matches only selected local day, validates offers, preserves bookings and stops after departure',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/(ui_review_|dispatch_test)/);const p=new PrismaClient({datasources:{db:{url:database}}});const rollback=Error('rollback schedule');
 try{await assert.rejects(p.$transaction(async tx=>{
  const db=new Proxy(tx,{get:(t,k)=>k==='$transaction'?fn=>fn(db):t[k]});const key=randomUUID();
  const passenger=await tx.user.create({data:{phone:'schedule-passenger:'+key,password:'qa',name:'QA',refCode:randomUUID(),refLink:'test',wallet:{create:{}}}});
  const driver=await tx.user.create({data:{phone:'+7702'+String(Date.now()).slice(-7),password:'qa',name:'QA',refCode:randomUUID(),refLink:'test',role:'DRIVER',wallet:{create:{money:0}},driverProfile:{create:{status:'ACTIVE',acceptIntercity:true,acceptDelivery:true}}},include:{driverProfile:true}});
  const service=new DriverService(db,{}, {}, {}, {}, {}),intercity=new IntercityService(db,{});
  const day=new Date(Date.now()+86400000);day.setUTCHours(0,0,0,0);const at=hours=>new Date(day.getTime()+hours*3600000);
  const data={fromCity:'From '+key,toCity:'To '+key,seatsAvailable:2,departureAt:at(11).toISOString(),departureOffsetMinutes:300};
  await assert.rejects(service.addIntercityRoute(driver.id,{...data,departureAt:undefined}),/дату/);await assert.rejects(service.addIntercityRoute(driver.id,{...data,departureAt:new Date(Date.now()-1000).toISOString()}),/будущ/);
  const route=await service.addIntercityRoute(driver.id,data);assert.equal(route.departureAt.toISOString(),data.departureAt);
  const ids=[];for(const h of[-6,-4,7,11,11.01,19]){const r=await tx.intercityRequest.create({data:{passengerId:passenger.id,fromCity:data.fromCity,toCity:data.toCity,date:at(h),price:1000,seats:1,currency:'KZT'}});ids.push(r.id);}
  const matches=await service.getMatchingIntercityRequests(driver.id);assert.deepEqual(new Set(matches.map(r=>r.id)),new Set(ids.slice(1,4)));
  await assert.rejects(intercity.createOffer(driver.id,ids[2],{price:1000,seats:1}),/Недостаточно средств/);
  await tx.wallet.update({where:{userId:driver.id},data:{money:10000}});await assert.rejects(intercity.createOffer(driver.id,ids[4],{price:1000,seats:1}),/маршрут|мест/);
  const offer=await intercity.createOffer(driver.id,ids[2],{price:1000,seats:1});await intercity.acceptOffer(passenger.id,offer.id);
  await assert.rejects(service.addIntercityRoute(driver.id,data),/принятые заказы/);assert.equal((await tx.driverIntercityRoute.findUnique({where:{id:route.id}})).seatsAvailable,1);
  await tx.driverIntercityRoute.update({where:{id:route.id},data:{departureAt:new Date(Date.now()-1000)}});assert.deepEqual(await service.getMatchingIntercityRequests(driver.id),[]);
  assert((await service.getActiveIntercity(driver.id)).some(r=>r.id===ids[2]));
  const pickup=await intercity.getRequest(passenger.id,ids[2]);assert.equal(pickup.pickupProgress.route.seatsAvailable,1);assert.equal(pickup.pickupProgress.driverLocation,null);
  await intercity.updateDriverRequestStatus(driver.id,ids[2],'DRIVER_EN_ROUTE');
  await tx.driverOnline.create({data:{driverId:driver.driverProfile.id,isOnline:true,lastLat:49.9,lastLng:82.6,lastAccuracy:10,lastLocationAt:new Date()}});
  const enRoute=await intercity.getRequest(passenger.id,ids[2]);assert.equal(enRoute.status,'DRIVER_EN_ROUTE');assert.equal(enRoute.pickupProgress.driverLocation.lat,49.9);
  await tx.driverOnline.update({where:{driverId:driver.driverProfile.id},data:{lastLocationAt:new Date(Date.now()-180000)}});assert.equal((await intercity.getRequest(passenger.id,ids[2])).pickupProgress.driverLocation,null);
  await intercity.updateDriverRequestStatus(driver.id,ids[2],'CANCELLED');assert.equal((await tx.driverIntercityRoute.findUnique({where:{id:route.id}})).seatsAvailable,2);
  throw rollback;
 },{timeout:60000}),e=>e===rollback);}finally{await p.$disconnect()}
});
