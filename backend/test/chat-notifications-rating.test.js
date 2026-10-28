const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {PrismaClient}=require('@prisma/client');
const {IntercityService}=require('../dist/src/intercity/intercity.service');
const {notifyTripChat}=require('../dist/src/common/trip-chat-notification');
const {RealtimeService}=require('../dist/src/realtime/realtime.service');
const {RealtimeController}=require('../dist/src/realtime/realtime.controller');
test('chat is private and survives push failure',async()=>{
 const realtime=new RealtimeService(),c=new RealtimeController(realtime,{},{}),mine=[],other=[],publicEvents=[],push=[];
 const subs=[c.userStream({user:{sub:'recipient'}}).subscribe(e=>mine.push(e)),c.userStream({user:{sub:'other'}}).subscribe(e=>other.push(e)),c.events().subscribe(e=>publicEvents.push(e))];
 try {
  notifyTripChat(realtime,{sendToUser:async(id,data)=>{push.push({id,data});throw Error('offline')}},{kind:'INTERCITY',tripId:'trip',messageId:'msg',recipientUserId:'recipient',recipientRole:'DRIVER'});
  await new Promise(r=>setImmediate(r));assert.equal(mine.length,1);assert.equal(other.length,0);assert.equal(publicEvents.length,0);
  assert.equal(push[0].id,'recipient');assert.match(push[0].data.data.route,/intercityRequestId=trip&chat=1&chatMessageId=msg/);assert.equal(mine[0].data.payload.text,undefined);
 } finally {subs.forEach(s=>s.unsubscribe())}
});
const database=process.env.TARIFF_TEST_DATABASE_URL;
test('completed intercity rating is owner-only and once-only; low ratings await review',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/(ui_review_|dispatch_test)/);
 const p=new PrismaClient({datasources:{db:{url:database}}}),rollback=Error('rollback rating');
 try{await assert.rejects(p.$transaction(async tx=>{
  const db=new Proxy(tx,{get:(t,k)=>k==='$transaction'?fn=>fn(db):t[k]});
  const users=[];for(let i=0;i<3;i++) users.push(await tx.user.create({data:{phone:'rating:'+randomUUID(),password:'qa',name:'QA',refCode:randomUUID(),refLink:'test'}}));
  const [passenger,driver,outsider]=users, profile=await tx.driverProfile.create({data:{userId:driver.id}});
  const create=status=>tx.intercityRequest.create({data:{passengerId:passenger.id,selectedDriverId:driver.id,status,fromCity:'QA',toCity:'QA2',date:new Date(),price:3000}});
  const trip=await create('DRIVER_ASSIGNED'),s=new IntercityService(db,{});
  await assert.rejects(s.rateDriver(trip.id,passenger.id,5),/после завершения/);
  await tx.intercityRequest.update({where:{id:trip.id},data:{status:'COMPLETED'}});
  await assert.rejects(s.rateDriver(trip.id,outsider.id,5),/Нет доступа/);await assert.rejects(s.rateDriver(trip.id,passenger.id,5.5),/от 1 до 5/);
  assert.deepEqual(await s.rateDriver(trip.id,passenger.id,5),{success:true,pendingReview:false});await assert.rejects(s.rateDriver(trip.id,passenger.id,4),/уже отправлена/);
  let a=await tx.driverRating.findUnique({where:{driverId:profile.id}});assert.equal(a.ratingCount,1);assert.equal(a.ratingAvg,5);
  const low=await create('COMPLETED');await assert.rejects(s.rateDriver(low.id,passenger.id,1,'bad'),/опишите/);
  assert.equal((await s.rateDriver(low.id,passenger.id,1,'Водитель опасно управлял автомобилем')).pendingReview,true);
  a=await tx.driverRating.findUnique({where:{driverId:profile.id}});assert.equal(a.ratingCount,1);
  const complaint=await tx.complaint.findFirst({where:{intercityRequestId:low.id}});assert.equal(complaint.driverId,profile.id);
  const {AdminService}=require('../dist/src/admin/admin.service');
  const admin=new AdminService(db,{publish:()=>{}},null);
  await admin.updateComplaint(complaint.id,{ratingDecision:'APPROVE',resolutionNote:'Нарушение подтверждено'});
  await admin.updateComplaint(complaint.id,{ratingDecision:'APPROVE',resolutionNote:'Повторно подтверждено'});
  a=await tx.driverRating.findUnique({where:{driverId:profile.id}});assert.equal(a.ratingCount,2);assert.equal(a.ratingAvg,3);
  await admin.updateComplaint(complaint.id,{ratingDecision:'REJECT',resolutionNote:'Нарушение не подтверждено'});
  a=await tx.driverRating.findUnique({where:{driverId:profile.id}});assert.equal(a.ratingCount,1);assert.equal(a.ratingAvg,5);
  throw rollback;
 },{timeout:60000}),e=>e===rollback)}finally{await p.$disconnect()}
});
