const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {PrismaClient}=require('@prisma/client');
const {dashboardPeriod,dashboardStatistics}=require('../dist/src/admin/dashboard-statistics');
test('dashboard uses UTC+5 calendar boundaries and validates custom periods',()=>{
 const now=new Date('2026-11-04T20:00:00Z');
 assert.equal(dashboardPeriod('today',undefined,undefined,now).from,'2026-11-04T19:00:00.000Z');
 assert.equal(dashboardPeriod('24h',undefined,undefined,now).from,'2026-11-03T20:00:00.000Z');
 const r=dashboardPeriod('custom','2026-11-04','2026-11-04',now);assert.equal(r.from,'2026-11-03T19:00:00.000Z');assert.equal(r.to,'2026-11-04T19:00:00.000Z');
 for(const [a,b] of [['2026-02-30','2026-03-01'],['2026-11-05','2026-11-04'],['2020-01-01','2026-01-01']]) assert.throws(()=>dashboardPeriod('custom',a,b,now));
 assert.throws(()=>dashboardPeriod('bogus'));
});
const database=process.env.TARIFF_TEST_DATABASE_URL;
test('dashboard counts both stores, accepted offer amounts, distinct passengers and exact date boundaries',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/(ui_review_|dispatch_test)/);
 const p=new PrismaClient({datasources:{db:{url:database}}}),rollback=Error('rollback dashboard');
 try {await assert.rejects(p.$transaction(async tx=>{
  const before=await dashboardStatistics(tx,'custom','2040-01-02','2040-01-02');
  const start=new Date('2040-01-01T19:00:00Z'),end=new Date('2040-01-02T19:00:00Z');
  async function user(role='PASSENGER',createdAt=start){return tx.user.create({data:{phone:'dashboard:'+randomUUID(),password:'qa',name:'Dashboard QA',role,refCode:randomUUID(),refLink:'qa',createdAt}})}
  const passenger=await user(),driver=await user(),old=await user('PASSENGER',new Date(start.getTime()-1));await user('ADMIN');
  await tx.driverProfile.create({data:{userId:driver.id,status:'ACTIVE',createdAt:start}});
  const base={passengerId:passenger.id,mode:'CARGO',requestType:'CARGO',fromLat:43,fromLng:76,toLat:43.1,toLng:76.1,fromAddress:'A',toAddress:'B',createdAt:start};
  await tx.order.create({data:{...base,status:'COMPLETED',completedAt:start,price:1500,currency:'KZT'}});
  await tx.order.create({data:{...base,status:'CANCELLED',currency:'RUB'}});
  await tx.order.create({data:{...base,status:'SEARCHING_DRIVER',createdAt:end}});
  const request=await tx.intercityRequest.create({data:{passengerId:passenger.id,requestType:'INTERCITY',fromCity:'A',toCity:'B',date:start,createdAt:start,status:'COMPLETED',completedAt:start,price:0,currency:'RUB'}});
  const offer=await tx.intercityOffer.create({data:{requestId:request.id,driverId:driver.id,price:700,seats:1}});await tx.intercityRequest.update({where:{id:request.id},data:{selectedOfferId:offer.id}});
  await tx.order.create({data:{...base,status:'COMPLETED',price:300,currency:'RUB',createdAt:new Date(start.getTime()-1),completedAt:start}});
  const after=await dashboardStatistics(tx,'custom','2040-01-02','2040-01-02');
  assert.equal(after.users.newTotal-before.users.newTotal,2);assert.equal(after.users.newDrivers-before.users.newDrivers,1);assert.equal(after.users.newPassengers-before.users.newPassengers,1);
  assert.equal(after.drivers.newProfiles-before.drivers.newProfiles,1);assert.equal(after.orders.total-before.orders.total,3);assert.equal(after.orders.completed-before.orders.completed,2);assert.equal(after.orders.cancelled-before.orders.cancelled,1);assert.equal(after.orders.uniquePassengers-before.orders.uniquePassengers,1);
  assert.equal(after.finance.find(x=>x.currency==='RUB').turnover,1000);assert.equal(after.completedInPeriod-before.completedInPeriod,3);assert.equal(after.daily.length,1);assert.equal(after.daily[0].users-before.daily[0].users,2);
  assert(!after.recentUsers.some(x=>x.id===old.id));assert(after.recentOrders.some(x=>x.id===request.id && x.price===700));throw rollback;
 },{timeout:30000}),e=>e===rollback)}finally{await p.$disconnect()}
});
