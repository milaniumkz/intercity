const {test}=require('node:test');
const assert=require('node:assert/strict');
const {NotificationDispatchService}=require('../dist/src/admin/notification-dispatch.service');
function fixture(tokens) {
 let selection,updated; const sent=[];
 const prisma={notificationCampaign:{findUnique:async()=>({id:'campaign',title:'Тест',body:'Текст',audience:'DRIVERS',cityId:'city'}),update:async args=>{updated=args.data}},user:{findMany:async args=>{selection=args;return tokens.map(pushToken=>({pushToken}))}}};
 const service=new NotificationDispatchService(prisma,{}, {sendToToken:async(token,payload)=>{sent.push({token,payload});return true}});
 return {service,sent,get selection(){return selection},get updated(){return updated}};
}
test('admin broadcast uses shared HTTP v1 push transport and deduplicates tokens',async()=>{
 const f=fixture(['device-a',' device-a ','device-b','']);
 const result=await f.service.dispatchCampaign('campaign');
 assert.equal(result.successCount,2);assert.equal(result.failCount,0);
 assert.equal(f.sent.length,2);assert.deepEqual(f.sent[0].payload,{title:'Тест',body:'Текст',data:{type:'campaign'}});
 assert.equal(f.selection.where.blockedAt,null);assert.deepEqual(f.selection.where.driverProfile,{isNot:null});assert.equal(f.selection.where.cityId,'city');assert.equal(f.updated.isSent,true);
});
test('empty audience is an explicit Russian error rather than successful dispatch',async()=>{
 const f=fixture(['', ' ']);await assert.rejects(f.service.dispatchCampaign('campaign'),/Нет получателей.*Рассылка не отправлена/);assert.equal(f.sent.length,0);assert.equal(f.updated,undefined);
});
test('provider rejection is reported as failure, not delivery',async()=>{
 const f=fixture(['device']);f.service.sendPushWithRetry=async()=>false;
 const result=await f.service.dispatchCampaign('campaign');assert.equal(result.successCount,0);assert.equal(result.failCount,1);assert.match(result.lastError,/не принял/);assert.equal(f.updated.isSent,false);
});
