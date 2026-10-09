const { test } = require('node:test');
const assert = require('node:assert/strict');
const { OrdersService } = require('../dist/src/orders/orders.service');
const order = {id:'ride', passengerId:'passenger', driverId:'driver-profile', driver:{userId:'driver'}, status:'COMPLETED'};
const messages = [
 {id:'1', senderId:'passenger', text:'Мой адрес', sender:{role:'DRIVER', name:'Олег'}},
 {id:'2', senderId:'driver', text:'Еду', sender:{role:'DRIVER', name:'Данил'}},
];
for (const viewer of ['passenger','driver']) {
 test(`chat uses participant identity for ${viewer} even when both accounts are drivers`, async () => {
  const service=new OrdersService({order:{findUnique:async()=>order}, orderChatMessage:{findMany:async()=>messages}},null,null,null,null);
  const result=await service.getOrderChat('ride',{userId:viewer,role:'DRIVER'});
  assert.deepEqual(result.map(m=>m.isMine), viewer==='passenger'?[true,false]:[false,true]);
  assert.deepEqual(result.map(m=>m.participantRole),['PASSENGER','DRIVER']);
 });
}
test('chat participant check still rejects an unrelated user',async()=>{
 const service=new OrdersService({order:{findUnique:async()=>order}},null,null,null,null);
 await assert.rejects(service.getOrderChat('ride',{userId:'stranger',role:'DRIVER'}), /Нет доступа/);
});
test('driver rating update is published only after updated average is saved',async()=>{
 const steps=[];
 const tx={$executeRaw:async()=>1,order:{updateMany:async()=>{steps.push('order');return {count:1}}},driverRating:{findUnique:async()=>({ratingCount:1,ratingAvg:4}),upsert:async({update})=>{assert.equal(update.ratingAvg,4.5);steps.push('rating');}}};
 const service=new OrdersService({order:{findUnique:async()=>order},$transaction:async fn=>fn(tx)},null,null,{publish:e=>{assert.equal(e.type,'driver.rating.updated');assert.equal(e.entityId,'driver-profile');steps.push('event');}},null);
 await service.rateOrder('ride','passenger',5,false);
 assert.deepEqual(steps,['order','rating','event']);
});
