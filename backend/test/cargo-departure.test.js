const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {PrismaClient}=require('@prisma/client'),{OrdersService}=require('../dist/src/orders/orders.service');
test('cargo rejects absent, invalid and elapsed pickup dates before persistence',async()=>{
 const s=new OrdersService({}, {},{}, {},{}),base={mode:'CARGO',requestType:'CARGO',itemDescription:'Шкаф'};
 for(const scheduledFor of [undefined,'bad-date',new Date(Date.now()-60000).toISOString()]) await assert.rejects(s.createOrder('user',{...base,scheduledFor}),/дату и время подачи/);
});
const database=process.env.TARIFF_TEST_DATABASE_URL;
test('cargo persists the exact selected UTC pickup date with freight details',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/(ui_review_|dispatch_test)/);
 const p=new PrismaClient({datasources:{db:{url:database}}}),rollback=Error('rollback cargo');
 try{await assert.rejects(p.$transaction(async tx=>{
  const db=new Proxy(tx,{get:(t,k)=>k==='$transaction'?fn=>fn(db):t[k]});
  const user=await tx.user.create({data:{phone:'cargo:'+randomUUID(),password:'qa',name:'QA',refCode:randomUUID(),refLink:'test'}});
  const s=new OrdersService(db,{}, {assignCityOrder:async()=>null},{publish:()=>{}},{});s.previewOrderDtoToOrder=async()=>({price:1500,currency:'KZT',distance:2,duration:3});
  const date=new Date(Date.now()+2*86400000).toISOString().slice(0,10)+'T17:45:00+05:00';
  const expected=new Date(date).toISOString();
  const order=await s.createOrder(user.id,{mode:'CARGO',requestType:'CARGO',fromLat:43,fromLng:76,toLat:43.1,toLng:76.1,fromAddress:'A',toAddress:'B',paymentMethod:'CASH',itemDescription:'Шкаф',itemWeightKg:25,scheduledFor:date});
  assert.equal(order.scheduledFor.toISOString(),expected);assert.equal(order.deliveryItemDescription,'Шкаф');assert.equal(order.deliveryWeightKg,25);
  assert.equal((await tx.order.findUnique({where:{id:order.id}})).scheduledFor.toISOString(),expected);
  throw rollback;
 }),e=>e===rollback)}finally{await p.$disconnect()}
});
