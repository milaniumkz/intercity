const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto'),fs=require('node:fs');
const {departureDay,departureCityKey,requireNoDuplicateDeparture}=require('../dist/src/common/intercity-departure-duplicate');
const {OrdersService}=require('../dist/src/orders/orders.service');
const {PrismaClient}=require('@prisma/client'),{IntercityService}=require('../dist/src/intercity/intercity.service'),{DriverService}=require('../dist/src/driver/driver.service'),{RidesharingService}=require('../dist/src/ridesharing/ridesharing.service');
test('departure identity uses the chosen local calendar day and ignores city case/spacing/dash variants',()=>{
 assert.equal(departureDay('2026-12-31T19:15:00Z',300),'2027-01-01');assert.equal(departureDay('2026-12-31T19:15:00Z',180),'2026-12-31');
 assert.equal(departureCityKey('  Усть–Каменогорск  '),departureCityKey('УСТЬ-КАМЕНОГОРСК'));
 for(const offset of [841,-721,2.5,'300'])assert.throws(()=>departureDay(new Date(),offset));
});
const database=process.env.TARIFF_TEST_DATABASE_URL;
function client(){const u=new URL(database);assert.equal(u.hostname,'127.0.0.1');assert.match(u.pathname,/^\/(ui_review_|dispatch_test)/);return new PrismaClient({datasources:{db:{url:database}}});}
test('passenger and driver requests reject same-day duplicates but retain independent dates and existing records',{skip:!database},async()=>{
 const p=client(),rollback=Error('rollback duplicates');
 try{await assert.rejects(p.$transaction(async tx=>{
  const db=new Proxy(tx,{get:(t,k)=>k==='$transaction'?fn=>fn(db):t[k]});const key=randomUUID(),base=new Date(Date.now()+3*86400000);base.setUTCHours(4,0,0,0);const at=h=>new Date(base.getTime()+h*3600000);
  const passenger=await tx.user.create({data:{phone:'duplicate-passenger:'+key,password:'qa',name:'QA',refCode:randomUUID(),refLink:'qa'}});
  const driver=await tx.user.create({data:{phone:'duplicate-driver:'+key,password:'qa',name:'QA',refCode:randomUUID(),refLink:'qa',role:'DRIVER',driverProfile:{create:{status:'ACTIVE',acceptIntercity:true}}},include:{driverProfile:true}});
  const geo={departureCurrency:async()=> 'KZT'},intercity=new IntercityService(db,geo),drivers=new DriverService(db,geo,{}, {},{},{}),trips=new RidesharingService(db,geo);
  const route={fromCity:'From '+key,toCity:'To '+key};const request={...route,date:at(0),departureOffsetMinutes:300,seats:1};
  const a=await intercity.createRequest(passenger.id,request);
  await assert.rejects(intercity.createRequest(passenger.id,{...request,date:at(2),fromCity:route.fromCity.toUpperCase()}),e=>e.getStatus()===409&&e.getResponse().code==='DUPLICATE_INTERCITY_DEPARTURE');
  const b=await intercity.createRequest(passenger.id,{...request,date:at(24)});assert.notEqual(a.id,b.id);
  const c=await intercity.createRequest(passenger.id,{...request,toCity:'Other '+key});assert.notEqual(c.id,a.id);
  await tx.intercityRequest.update({where:{id:a.id},data:{status:'CANCELLED'}});
  const replacement=await intercity.createRequest(passenger.id,request);assert.notEqual(replacement.id,a.id);assert.equal((await tx.intercityRequest.findUnique({where:{id:a.id}})).status,'CANCELLED');
  const r1=await drivers.addIntercityRoute(driver.id,{...route,departureAt:at(0).toISOString(),departureOffsetMinutes:300,seatsAvailable:4});
  await assert.rejects(drivers.addIntercityRoute(driver.id,{...route,departureAt:at(2).toISOString(),departureOffsetMinutes:300}),/маршрут и дату/);
  const r2=await drivers.addIntercityRoute(driver.id,{...route,departureAt:at(24).toISOString(),departureOffsetMinutes:300,seatsAvailable:3});assert.notEqual(r1.id,r2.id);
  const trip={...route,fromLat:49.9,fromLng:82.6,toLat:50.4,toLng:80.2,seatsTotal:2,pricePerSeat:1000,departureTime:at(2),departureOffsetMinutes:300};
  await assert.rejects(trips.createTrip(driver.id,trip),/маршрут и дату/);
  const t=await trips.createTrip(driver.id,{...trip,departureTime:at(48)});assert(t.id);
  await assert.rejects(trips.createTrip(driver.id,{...trip,departureTime:at(50)}),/маршрут и дату/);
  await assert.rejects(drivers.addIntercityRoute(driver.id,{...route,departureAt:at(48).toISOString(),departureOffsetMinutes:300}),/маршрут и дату/);
  await tx.intercityRequest.update({where:{id:replacement.id},data:{status:'DRIVER_ASSIGNED',reservedRouteId:r1.id,reservedSeats:1,selectedDriverId:driver.id,date:at(-8.5),departureOffsetMinutes:180}});
  await tx.driverIntercityRoute.update({where:{id:r1.id},data:{isActive:false}});
  await assert.rejects(drivers.addIntercityRoute(driver.id,{...route,departureAt:at(0).toISOString(),departureOffsetMinutes:300}),/маршрут и дату/);
  const later=await drivers.addIntercityRoute(driver.id,{...route,departureAt:at(96).toISOString(),departureOffsetMinutes:300});assert(later.id);
  assert.equal((await tx.intercityRequest.findUnique({where:{id:replacement.id}})).reservedRouteId,r1.id);
  await tx.intercityRequest.update({where:{id:replacement.id},data:{status:'OPEN',reservedRouteId:null,reservedSeats:0,selectedDriverId:null,date:at(0),departureOffsetMinutes:300}});
  await drivers.addIntercityRoute(driver.id,{...route,departureAt:at(0).toISOString(),departureOffsetMinutes:300});
  const matches=await drivers.getMatchingIntercityRequests(driver.id);assert(matches.some(x=>x.id===replacement.id));assert(matches.some(x=>x.id===b.id));
  assert.equal((await tx.driverIntercityRoute.findUnique({where:{id:r1.id}})).departureAt.toISOString(),at(0).toISOString());
  assert.equal((await tx.driverIntercityRoute.findUnique({where:{id:r2.id}})).seatsAvailable,3);
  await tx.intercityRequest.update({where:{id:replacement.id},data:{status:'IN_PROGRESS'}});
  assert.equal((await new OrdersService(db,geo,{},{},{}).getActivePassengerOrder(passenger.id)).id,replacement.id);
  await tx.intercityRequest.update({where:{id:b.id},data:{status:'DRIVER_ASSIGNED',selectedDriverId:driver.id}});
  await assert.rejects(intercity.updateDriverRequestStatus(driver.id,b.id,'DRIVER_EN_ROUTE'),/У пассажира уже есть текущая поездка/);
  assert.equal((await tx.intercityRequest.findUnique({where:{id:b.id}})).status,'DRIVER_ASSIGNED');
  await assert.rejects(intercity.createRequest(passenger.id,{...request,date:at(72)}),/активный заказ/);
  throw rollback;
 },{timeout:60000}),e=>e===rollback);}finally{await p.$disconnect();}
});
test('concurrent same-account submissions commit exactly one departure',{skip:!database},async()=>{
 const p=client(),key=randomUUID();let user;
 try{
  user=await p.user.create({data:{phone:'duplicate-race:'+key,password:'qa',name:'QA',refCode:randomUUID(),refLink:'qa'}});
  const date=new Date(Date.now()+4*86400000),route={fromCity:'Race from '+key,toCity:'Race to '+key};
  const create=()=>p.$transaction(async tx=>{await requireNoDuplicateDeparture(tx,user.id,'PASSENGER',{...route,date,offset:300});await new Promise(r=>setTimeout(r,50));return tx.intercityRequest.create({data:{passengerId:user.id,...route,date,price:1000,departureOffsetMinutes:300}})},{timeout:15000});
  const results=await Promise.allSettled([create(),create()]);assert.equal(results.filter(x=>x.status==='fulfilled').length,1);assert.equal(results.filter(x=>x.status==='rejected'&&x.reason.getStatus()===409).length,1);
  assert.equal(await p.intercityRequest.count({where:{passengerId:user.id}}),1);
 }finally{if(user){await p.intercityRequest.deleteMany({where:{passengerId:user.id}});await p.user.delete({where:{id:user.id}});}await p.$disconnect();}
});
test('concurrent driver route and trip APIs cannot publish the same route/day twice',{skip:!database},async()=>{
 const p=client(),key=randomUUID();let driver;
 try{
  driver=await p.user.create({data:{phone:'duplicate-driver-race:'+key,password:'qa',name:'QA',refCode:randomUUID(),refLink:'qa',role:'DRIVER',driverProfile:{create:{status:'ACTIVE',acceptIntercity:true}}},include:{driverProfile:true}});
  const geo={departureCurrency:async()=> 'KZT'},drivers=new DriverService(p,geo,{},{},{},{}),trips=new RidesharingService(p,geo);
  const route={fromCity:'Driver race from '+key,toCity:'Driver race to '+key},date=new Date(Date.now()+5*86400000);
  const results=await Promise.allSettled([
    drivers.addIntercityRoute(driver.id,{...route,departureAt:date.toISOString(),departureOffsetMinutes:300,seatsAvailable:4}),
    trips.createTrip(driver.id,{...route,fromLat:49.9,fromLng:82.6,toLat:50.4,toLng:80.2,seatsTotal:2,pricePerSeat:1000,departureTime:date,departureOffsetMinutes:300}),
  ]);
  assert.equal(results.filter(x=>x.status==='fulfilled').length,1,JSON.stringify(results.map(x=>x.reason?.message)));
  assert.equal(results.filter(x=>x.status==='rejected'&&x.reason.getStatus()===409).length,1);
  assert.equal(await p.driverIntercityRoute.count({where:{driverId:driver.driverProfile.id}})+await p.rideSharingTrip.count({where:{driverId:driver.id}}),1);
 }finally{if(driver){await p.driverIntercityRoute.deleteMany({where:{driverId:driver.driverProfile.id}});await p.rideSharingTrip.deleteMany({where:{driverId:driver.id}});await p.driverProfile.delete({where:{id:driver.driverProfile.id}});await p.user.delete({where:{id:driver.id}});}await p.$disconnect();}
});
test('migration preserves old routes/requests and backfills the reserved route timezone',{skip:!database},async()=>{
 const p=client(),rollback=Error('rollback migration');
 try{await assert.rejects(p.$transaction(async tx=>{
  const schema='duplicate_migration_'+randomUUID().replaceAll('-','');await tx.$executeRawUnsafe(`CREATE SCHEMA "${schema}"`);await tx.$executeRawUnsafe(`SET LOCAL search_path TO "${schema}"`);
  for(const sql of [
   'CREATE TABLE "DriverIntercityRoute"(id text,"driverId" text,"fromCity" text,"toCity" text,"departureAt" timestamp,"departureOffsetMinutes" integer)',
   'CREATE UNIQUE INDEX "DriverIntercityRoute_driverId_fromCity_toCity_key" ON "DriverIntercityRoute"("driverId","fromCity","toCity")',
   'CREATE TABLE "IntercityRequest"(id text,"passengerId" text,date timestamp,"reservedRouteId" text)',
   'CREATE TABLE "RideSharingTrip"(id text,"driverId" text,"departureTime" timestamp)',
   `INSERT INTO "DriverIntercityRoute" VALUES('route','driver','From','To','2030-01-01',180)`,
   `INSERT INTO "IntercityRequest" VALUES('request','passenger','2030-01-01','route')`,
   `INSERT INTO "RideSharingTrip" VALUES('trip','driver','2030-01-01')`])await tx.$executeRawUnsafe(sql);
  const sql=fs.readFileSync('prisma/migrations/20261107100000_intercity_departure_days/migration.sql','utf8').replace(/^--.*$/gm,'');for(const statement of sql.split(';').map(x=>x.trim()).filter(Boolean))await tx.$executeRawUnsafe(statement);
  const request=await tx.$queryRawUnsafe('SELECT * FROM "IntercityRequest"');assert.equal(request.length,1);assert.equal(request[0].id,'request');assert.equal(request[0].departureOffsetMinutes,180);
  const trip=await tx.$queryRawUnsafe('SELECT * FROM "RideSharingTrip"');assert.equal(trip[0].departureOffsetMinutes,null);
  await tx.$executeRawUnsafe(`INSERT INTO "DriverIntercityRoute" VALUES('route2','driver','From','To','2030-01-02',180)`);
  assert.equal((await tx.$queryRawUnsafe('SELECT * FROM "DriverIntercityRoute"')).length,2);throw rollback;
 },{timeout:30000}),e=>e===rollback);}finally{await p.$disconnect();}
});
