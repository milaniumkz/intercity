const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {PrismaClient}=require('@prisma/client'),{IntercityService}=require('../dist/src/intercity/intercity.service');
const database=process.env.TARIFF_TEST_DATABASE_URL;
test('intercity participants exchange persisted messages; outsiders and closed writes are rejected',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/(ui_review_|dispatch_test)/);
 const p=new PrismaClient({datasources:{db:{url:database}}}),rollback=Error('rollback chat');
 try{await assert.rejects(p.$transaction(async tx=>{
  const db=new Proxy(tx,{get:(t,k)=>k==='$transaction'?fn=>fn(db):t[k]});
  const users=[];for(let i=0;i<3;i++)users.push(await tx.user.create({data:{phone:'chat:'+randomUUID(),password:'qa',name:'QA '+i,refCode:randomUUID(),refLink:'test'}}));
  const [passenger,driver,outsider]=users;
  const trip=await tx.intercityRequest.create({data:{passengerId:passenger.id,selectedDriverId:driver.id,status:'DRIVER_ASSIGNED',fromCity:'QA',toCity:'QA2',date:new Date(),price:3000}});
  const events=[],pushes=[];
  const s=new IntercityService(db,{},null,{publish:event=>events.push(event)},{sendToUser:async(userId,payload)=>pushes.push({userId,payload})});
  assert.deepEqual(await s.getChat(trip.id,passenger.id),[]);
  await assert.rejects(s.getChat(trip.id,outsider.id),/Нет доступа/);
  await assert.rejects(s.sendChat(trip.id,outsider.id,'test'),/Нет доступа/);
  await assert.rejects(s.sendChat(trip.id,driver.id,{}),/Введите/);
  await assert.rejects(s.sendChat(trip.id,driver.id,'x'.repeat(1001)),/длинное/);
  const first=await s.sendChat(trip.id,passenger.id,'  Здравствуйте  ');assert.equal(first.text,'Здравствуйте');assert.equal(first.participantRole,'PASSENGER');
  const second=await s.sendChat(trip.id,driver.id,'Еду к вам');assert.equal(second.participantRole,'DRIVER');
  await new Promise(r=>setImmediate(r));
  assert.deepEqual(events.map(e=>e.entityId),[driver.id,passenger.id]);
  assert.deepEqual(pushes.map(e=>e.userId),[driver.id,passenger.id]);
  assert(events.every(e=>e.entity==='user'));
  const messages=await s.getChat(trip.id,driver.id);assert.equal(messages.length,2);assert.equal(messages.find(m=>m.id===first.id).isMine,false);assert.equal(messages.find(m=>m.id===second.id).isMine,true);
  assert.equal(messages[0].sender.password,undefined);
  await tx.intercityRequest.update({where:{id:trip.id},data:{status:'COMPLETED'}});
  await assert.rejects(s.sendChat(trip.id,passenger.id,'late'),/закрыт/);assert.equal((await s.getChat(trip.id,passenger.id)).length,2);
  throw rollback;
 },{timeout:60000}),e=>e===rollback)}finally{await p.$disconnect()}
});
