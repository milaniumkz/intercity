const test=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto'),{PrismaClient}=require('@prisma/client');
const {DriverService}=require('../dist/src/driver/driver.service'),{IntercityService}=require('../dist/src/intercity/intercity.service');
const {DEFAULT_ROUTE_TOP_POLICY,ROUTE_TOP_POLICY_KEY,routeTopPrice,ensureRouteTopWindow}=require('../dist/src/common/driver-route-top');
const database=process.env.DISPATCH_TEST_DATABASE_URL;
test('paid route priority charges once, expires after 12 hours and broadcasts to all promoted drivers before normal drivers', {skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/dispatch_test');
 const p=new PrismaClient({datasources:{db:{url:database}}}),key=randomUUID(),users=[],drivers=[],wallets=[],ids=[];
 const previous=await p.appSettings.findUnique({where:{key:ROUTE_TOP_POLICY_KEY}});
 const geo={departureCurrency:async(_x,_y,city)=>city.startsWith('RU')?'RUB':'KZT'};
 const service=new DriverService(p,geo,{publish:()=>{}},{},{},{}),from='KZ '+key,to='To '+key;
 try {
  await p.appSettings.upsert({where:{key:ROUTE_TOP_POLICY_KEY},create:{key:ROUTE_TOP_POLICY_KEY,value:JSON.stringify(DEFAULT_ROUTE_TOP_POLICY)},update:{value:JSON.stringify(DEFAULT_ROUTE_TOP_POLICY)}});
  for(let i=0;i<5;i++) {
   const u=await p.user.create({data:{phone:`test:${key}:${i}`,password:'test',name:'Top fixture',refCode:randomUUID(),refLink:'test',role:'DRIVER',wallet:{create:{money:5000,moneyRub:5000}}},include:{wallet:true}});users.push(u);wallets.push(u.wallet.id);
   const d=await p.driverProfile.create({data:{userId:u.id,status:'ACTIVE',acceptIntercity:true,serviceStats:{create:{activityScore:80+i}},rating:{create:{ratingAvg:i===2?3:5,ratingCount:10}},priorityFlags:{create:{hasBranding:i===0}}}});drivers.push(d.id);
   u.route=await p.driverIntercityRoute.create({data:{driverId:d.id,fromCity:i===3?'RU '+from:from,toCity:to,seatsTotal:2,seatsAvailable:2,departureAt:new Date(new Date(Date.now()+86400000).setUTCHours(23,59,59,999)),departureOffsetMinutes:0}});
  }
  for(const status of ['PENDING','REJECTED']) {
    await p.driverProfile.update({where:{id:drivers[4]},data:{status}});
    await assert.rejects(service.promoteIntercityRoute(users[4].id,users[4].route.id,{requestKey:randomUUID(),expectedPrice:1000,currency:'KZT'}),/ещё не одобрен/);
    assert.deepEqual(await service.getMatchingIntercityRequests(users[4].id),[]);
    assert.equal((await p.wallet.findUnique({where:{id:wallets[4]}})).money,5000);
  }
  await p.driverProfile.update({where:{id:drivers[4]},data:{status:'ACTIVE'}});
  await p.driverProfile.update({where:{id:drivers[3]},data:{status:'APPROVED'}});
  const started=Date.now(),purchase={requestKey:randomUUID(),expectedPrice:1000,currency:'KZT'};
  const results=await Promise.all([service.promoteIntercityRoute(users[0].id,users[0].route.id,purchase),service.promoteIntercityRoute(users[0].id,users[0].route.id,purchase)]);
  assert.equal(results[0].topUntil.getTime(),results[1].topUntil.getTime());assert.ok(results[0].topUntil.getTime()-started>=43200000);assert.ok(results[0].topUntil.getTime()-started<43205000);
  assert.equal((await p.wallet.findUnique({where:{id:wallets[0]}})).money,4000);assert.equal(await p.walletTransaction.count({where:{walletId:wallets[0],type:'DRIVER_ROUTE_TOP'}}),1);
  await assert.rejects(service.promoteIntercityRoute(users[0].id,users[0].route.id,{...purchase,requestKey:randomUUID()}),/уже в топе/);
  for(let i=1;i<3;i++) await service.promoteIntercityRoute(users[i].id,users[i].route.id,{...purchase,requestKey:randomUUID()});
  assert.equal(routeTopPrice(DEFAULT_ROUTE_TOP_POLICY,'RUB'),142.86);
  await service.promoteIntercityRoute(users[3].id,users[3].route.id,{requestKey:randomUUID(),expectedPrice:142.86,currency:'RUB'});
  const rub=await p.wallet.findUnique({where:{id:wallets[3]}});assert.equal(rub.money,5000);assert.equal(rub.moneyRub,4857.14);
  const now=new Date(),order=[];
  for(let i=0;i<6;i++) {
   const r=await p.intercityRequest.create({data:{passengerId:'top-test',fromCity:from,toCity:to,date:new Date(Date.now()+86400000),price:7000,seats:2}});ids.push(r.id);
   const windows=await Promise.all([p.$transaction(tx=>ensureRouteTopWindow(tx,r,now)),p.$transaction(tx=>ensureRouteTopWindow(tx,r,now))]);
   assert.deepEqual(windows[0].routeIds,windows[1].routeIds);order.push(windows[0].activeDriverIds.slice().sort());
  }
  assert.deepEqual(order,Array.from({length:6},()=>drivers.slice(0,3).sort()));
  assert.ok((await service.getMatchingIntercityRequests(users[1].id)).some(r=>r.id===ids[0]));
  assert.equal((await service.getMatchingIntercityRequests(users[4].id)).some(r=>r.id===ids[0]),false);
  const intercity=new IntercityService(p,geo);
  await assert.rejects(intercity.createOffer(users[4].id,ids[0],{price:7100,seats:2}),/сначала предложен/);
  await intercity.createOffer(users[0].id,ids[0],{price:7100,seats:2});
  // A counteroffer waits for the passenger and does not remove the top phase.
  assert.equal((await service.getMatchingIntercityRequests(users[4].id)).some(r=>r.id===ids[0]),false);
  await p.intercityRoutePriorityWindow.update({where:{requestId:ids[0]},data:{expiresAt:new Date(Date.now()-1000)}});
  assert.ok((await service.getMatchingIntercityRequests(users[4].id)).some(r=>r.id===ids[0]));
  await intercity.createOffer(users[4].id,ids[0],{price:7200,seats:2});
  const review=await intercity.createOffer(users[4].id,ids[0],{price:7300,seats:2});
  await assert.rejects(intercity.rejectOffer(users[2].id,review.id),/не найдено/);
  await intercity.rejectOffer('top-test',review.id);
  assert.equal((await p.intercityOffer.findUnique({where:{id:review.id}})).status,'REJECTED');
  await assert.rejects(intercity.acceptOffer('top-test',review.id),/отклонено/);
  const expired=await intercity.createOffer(users[4].id,ids[0],{price:7400,seats:2});
  await p.intercityOffer.update({where:{id:expired.id},data:{updatedAt:new Date(Date.now()-31000)}});
  await assert.rejects(intercity.acceptOffer('top-test',expired.id),/истекло/);
  await intercity.getRequest('top-test',ids[0]);
  assert.equal((await p.intercityOffer.findUnique({where:{id:expired.id}})).status,'EXPIRED');
  const race=await Promise.allSettled([intercity.acceptPassengerPrice(users[0].id,ids[1]),intercity.acceptPassengerPrice(users[1].id,ids[1])]);
  assert.equal(race.filter(r=>r.status==='fulfilled').length,1);
  const assigned=await p.intercityRequest.findUnique({where:{id:ids[1]}});
  assert.equal(assigned.status,'DRIVER_ASSIGNED');
  assert.ok([users[0].id,users[1].id].includes(assigned.selectedDriverId));
  assert.equal(await p.intercityOffer.count({where:{requestId:ids[1],status:'ACCEPTED'}}),1);
  const rubRequest=await p.intercityRequest.create({data:{passengerId:'top-test',fromCity:'RU '+from,toCity:to,date:new Date(Date.now()+86400000),currency:'RUB',price:123.45,seats:1}});ids.push(rubRequest.id);
  await intercity.acceptPassengerPrice(users[3].id,rubRequest.id);
  const exact=await p.intercityOffer.findFirst({where:{requestId:rubRequest.id,status:'ACCEPTED'}});assert.equal(exact.price,123.45);
  await p.driverIntercityRoute.updateMany({where:{driverId:{in:drivers}},data:{topUntil:new Date(Date.now()-1000)}});
  assert.ok((await service.getMatchingIntercityRequests(users[4].id)).some(r=>r.id===ids[3]));
  await p.wallet.update({where:{id:wallets[4]},data:{money:9940,lockedBonus:9720}});
  const bonusPurchase={...purchase,requestKey:randomUUID()};
  await Promise.all([1,2].map(()=>service.promoteIntercityRoute(users[4].id,users[4].route.id,bonusPurchase)));
  const paid=await p.wallet.findUnique({where:{id:wallets[4]}});
  assert.equal(paid.money,8940);assert.equal(paid.lockedBonus,8720);
  assert.equal(paid.money-paid.lockedBonus,220,'promotion spending must not unlock bonus funds for withdrawal');
  assert.equal(await p.walletTransaction.count({where:{walletId:wallets[4],type:'DRIVER_ROUTE_TOP'}}),1);
  await p.driverIntercityRoute.update({where:{id:users[4].route.id},data:{topUntil:new Date(Date.now()-1000)}});
  await p.wallet.update({where:{id:wallets[4]},data:{money:500,lockedBonus:500}});
  await assert.rejects(service.promoteIntercityRoute(users[4].id,users[4].route.id,{...purchase,requestKey:randomUUID()}),/Недостаточно средств/);
  assert.equal((await p.wallet.findUnique({where:{id:wallets[4]}})).money,500);
 } finally {
  await p.intercityOffer.deleteMany({where:{requestId:{in:ids}}});await p.intercityRequest.deleteMany({where:{id:{in:ids}}});
  await p.walletTransaction.deleteMany({where:{walletId:{in:wallets}}});await p.driverIntercityRoute.deleteMany({where:{driverId:{in:drivers}}});
  for(const model of ['driverPriorityFlags','driverRating','driverServiceStats']) await p[model].deleteMany({where:{driverId:{in:drivers}}});
  await p.driverProfile.deleteMany({where:{id:{in:drivers}}});await p.wallet.deleteMany({where:{id:{in:wallets}}});await p.user.deleteMany({where:{id:{in:users.map(u=>u.id)}}});
  if(previous) await p.appSettings.update({where:{key:ROUTE_TOP_POLICY_KEY},data:{value:previous.value}});else await p.appSettings.deleteMany({where:{key:ROUTE_TOP_POLICY_KEY}});
  await p.$disconnect();
 }
});
