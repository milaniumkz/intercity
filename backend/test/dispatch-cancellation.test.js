const {test}=require('node:test');const assert=require('node:assert/strict');
const {AutoDispatchService}=require('../dist/src/orders/auto-dispatch.service');
for(const stage of ['already-cancelled','before-queue','before-offer']){
 test(`dispatch cannot revive an order cancelled ${stage}`,async()=>{
  let status=stage==='already-cancelled'?'CANCELLED':'CREATED';let offered=false,publishes=0;
  const p={order:{findUnique:async()=>({id:'order',status,mode:'CITY',cityId:'city',driverId:null,dispatchTriedDriverIds:[]}),updateMany:async({where,data})=>{
   if(stage==='before-queue')status='CANCELLED';
   const allowed=where.status?.in?where.status.in.includes(status):where.status===status;
   if(!allowed)return{count:0};if(data.status)status=data.status;
   if(data.dispatchDriverId)offered=true;return{count:1};
  }},$executeRaw:async()=>0};
  p.$transaction=async f=>f(p);
  const service=new AutoDispatchService(p,{publish:()=>publishes++},{sendToUser:async()=>assert.fail('cancelled order must not notify offer')});
  service.getSettings=async()=>({dispatchTimeoutSec:20});
  service.findEligibleDrivers=async()=>{status='CANCELLED';return [{driverId:'driver',driver:{acceptCityFixed:true}}]};
  service.computeScore=async()=>({totalScore:100});
  await service.assignCityOrder('order');assert.equal(status,'CANCELLED');assert.equal(offered,false);assert.equal(publishes,0);
 });
}
