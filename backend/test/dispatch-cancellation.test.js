const {test}=require('node:test');const assert=require('node:assert/strict');
const {AutoDispatchService}=require('../dist/src/orders/auto-dispatch.service');
for(const stage of ['already-cancelled','before-queue','before-assignment']){
 test(`dispatch cannot revive an order cancelled ${stage}`,async()=>{
  let status=stage==='already-cancelled'?'CANCELLED':'CREATED';let updates=0,publishes=0;
  const p={order:{findUnique:async()=>({id:'order',status,mode:'CITY',cityId:'city',driverId:null}),updateMany:async({where,data})=>{
   updates++;if(stage==='before-queue')status='CANCELLED';
   const allowed=where.status?.in?where.status.in.includes(status):where.status===status;
   if(!allowed)return{count:0};status=data.status;return{count:1};
  }}};
  const service=new AutoDispatchService(p,{publish:()=>publishes++},{sendOrderStatusToPassenger:async()=>assert.fail('cancelled order must not notify assignment')});
  service.recordRideEventSafe=async()=>{};
  service.getSettings=async()=>({cityAutoAssignEnabled:true});
  service.findEligibleDrivers=async()=>{status='CANCELLED';return [{driverId:'driver'}]};
  service.computeScore=async()=>({totalScore:100});
  await service.assignCityOrder('order');assert.equal(status,'CANCELLED');
  if(stage==='already-cancelled'){assert.equal(updates,0);assert.equal(publishes,0)}
  if(stage==='before-queue')assert.equal(publishes,0);
  if(stage==='before-assignment')assert.equal(updates,2);
 });
}
