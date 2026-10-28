const {test}=require('node:test');const assert=require('node:assert/strict');const {randomUUID}=require('node:crypto');const {PrismaClient}=require('@prisma/client');const {WalletService}=require('../dist/src/wallet/wallet.service');
const database=process.env.TARIFF_TEST_DATABASE_URL;
test('topup readiness blocks demo and unconfigured payment links before contacting a provider',async()=>{
 const saved={...process.env};try{
  process.env.KASSA24_DEMO='true';process.env.KASSA24_LOGIN='qa-merchant';process.env.KASSA24_PASSWORD='qa-only';
  const row={id:'qa-topup',provider:'ONLINE',amount:1000,currency:'KZT',status:'PENDING'};let creates=0;
  const db={appSettings:{findUnique:async()=>null},driverProfile:{findUnique:async()=>null},wallet:{findUnique:async()=>({id:'wallet',user:{phone:'+77000000000'}})},topupRequest:{create:async()=>{creates++;return row},update:async({data})=>({...row,...data})}};
  const demo=new WalletService(db,{});demo.gateway.create=async()=>{throw Error('Demo must never open payment')};assert.equal((await demo.createTopupRequest('user',{amount:1000},'DRIVER')).paymentUrl,null);
  process.env.KASSA24_DEMO='false';process.env.KASSA24_PASSWORD='';const missing=new WalletService(db,{});assert.equal((await missing.createTopupRequest('user',{amount:1000},'DRIVER')).provider,'MANUAL');
  for(const amount of[0,-1,NaN,Infinity,1000.001,10000001])await assert.rejects(missing.createTopupRequest('user',{amount},'DRIVER'));assert.equal(creates,2);
 }finally{for(const k of ['KASSA24_DEMO','KASSA24_LOGIN','KASSA24_PASSWORD'])if(saved[k]===undefined)delete process.env[k];else process.env[k]=saved[k];}
});
test('provider demo mismatch, ownership, confirmation, duplicate callbacks and ledger failure preserve actual wallet money',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/(ui_review_|dispatch_test)/);
 const saved={...process.env};process.env.KASSA24_DEMO='false';process.env.KASSA24_LOGIN='qa-merchant';process.env.KASSA24_PASSWORD='qa-only';
 const p=new PrismaClient({datasources:{db:{url:database}}});let user,previousSetting;
 try{
  user=await p.user.create({data:{phone:'qa-topup:'+randomUUID(),password:'test-only',name:'QA topup',refCode:randomUUID(),refLink:'test',role:'DRIVER',wallet:{create:{money:200,moneyRub:500}}},include:{wallet:true}});
  previousSetting=await p.appSettings.findUnique({where:{key:"allowDemoTopupCredits"}});
  await p.appSettings.upsert({where:{key:"allowDemoTopupCredits"},create:{key:"allowDemoTopupCredits",value:"false"},update:{value:"false"}});
  const service=new WalletService(p,{});service.topupGateway=()=>service.gateway;let bank={status:0,demo:false};let lastCreate;
  service.gateway.create=async data=>{lastCreate=data;return{url:'https://example.test/payment',id:'provider-'+data.orderId}};
  service.gateway.status=async id=>({orderId:id,merchantId:'qa-merchant',amount:150000,...bank});
  const topup=await service.createTopupRequest(user.id,{amount:1500,currency:'KZT'},'DRIVER');assert.equal(topup.provider,'KASSA24');assert.equal(lastCreate.amount,150000);assert(lastCreate.backUrl.endsWith('/#/driver/wallet'));
  await assert.rejects(service.checkTopupPayment('another-user',topup.id),e=>e.getStatus()===404);
  assert.equal((await service.checkTopupPayment(user.id,topup.id)).status,'PENDING');assert.equal((await p.wallet.findUnique({where:{id:user.wallet.id}})).money,200);
  for(const wrong of[{demo:true},{amount:149999},{merchantId:'wrong'},{orderId:'wrong'}]){bank={status:1,demo:false,...wrong};const current=await service.checkTopupPayment(user.id,topup.id);assert.equal(current.status,'PENDING');if(wrong.demo)assert.equal(current.paymentMode,'TEST');assert.equal((await p.wallet.findUnique({where:{id:user.wallet.id}})).money,200);}
  bank={status:1,demo:false};await Promise.all([service.checkTopupPayment(user.id,topup.id),service.handleTopupPaymentCallback({topupRequestId:topup.id,paid:true})]);await service.checkTopupPayment(user.id,topup.id);
  assert.equal((await p.wallet.findUnique({where:{id:user.wallet.id}})).money,1700);assert.equal((await p.wallet.findUnique({where:{id:user.wallet.id}})).moneyRub,500);assert.equal(await p.walletTransaction.count({where:{topupRequestId:topup.id}}),1);
  bank={status:10,demo:true};const demo=await service.createTopupRequest(user.id,{amount:1500},'DRIVER');assert.equal(demo.provider,'MANUAL');assert.equal(demo.paymentUrl,null);assert.match(demo.message,/тестов/);
  bank={status:1,demo:false};const failure=await service.createTopupRequest(user.id,{amount:1500},'DRIVER');
  const broken=new Proxy(p,{get:(target,key)=>key==='$transaction'?cb=>p.$transaction(tx=>cb(new Proxy(tx,{get:(t,k)=>k==='walletTransaction'?new Proxy(t[k],{get:(m,q)=>q==='create'?async()=>{throw Error('ledger unavailable')}:m[q]}):t[k]}))):target[key]});
  const faulty=new WalletService(broken,{});faulty.gateway.status=service.gateway.status;await assert.rejects(faulty.checkTopupPayment(user.id,failure.id),/ledger unavailable/);
  assert.equal((await p.wallet.findUnique({where:{id:user.wallet.id}})).money,1700);assert.equal((await p.topupRequest.findUnique({where:{id:failure.id}})).status,'PENDING');
  await p.appSettings.update({where:{key:'allowDemoTopupCredits'},data:{value:'true'}});
  bank={status:10,demo:true};const enabledDemo=await service.createTopupRequest(user.id,{amount:1500},'DRIVER');assert.equal(enabledDemo.provider,'KASSA24_DEMO');assert(enabledDemo.paymentUrl);
  assert.equal((await service.checkTopupPayment(user.id,enabledDemo.id)).status,'PENDING');
  bank={status:1,demo:true};await Promise.all([service.checkTopupPayment(user.id,enabledDemo.id),service.handleTopupPaymentCallback({topupRequestId:enabledDemo.id})]);
  assert.equal((await p.wallet.findUnique({where:{id:user.wallet.id}})).money,3200);assert.equal(await p.walletTransaction.count({where:{topupRequestId:enabledDemo.id,type:'TOPUP_DEMO_CREDIT'}}),1);
  const legacy=await p.topupRequest.create({data:{walletId:user.wallet.id,amount:1500,currency:'KZT',provider:'KASSA24'}});
  const recovered=await service.checkTopupPayment(user.id,legacy.id);assert.equal(recovered.status,'APPROVED');assert.equal(recovered.paymentMode,'TEST');await service.checkTopupPayment(user.id,legacy.id);assert.equal((await p.wallet.findUnique({where:{id:user.wallet.id}})).money,4700);
  const blocked=await p.topupRequest.create({data:{walletId:user.wallet.id,amount:1500,currency:'KZT',provider:'KASSA24_DEMO'}});await p.appSettings.update({where:{key:'allowDemoTopupCredits'},data:{value:'false'}});assert.equal((await service.checkTopupPayment(user.id,blocked.id)).status,'PENDING');assert.equal((await p.wallet.findUnique({where:{id:user.wallet.id}})).money,4700);


 }finally{
  if(previousSetting)await p.appSettings.update({where:{key:'allowDemoTopupCredits'},data:{value:previousSetting.value}});else await p.appSettings.deleteMany({where:{key:'allowDemoTopupCredits'}});
  if(user){await p.walletTransaction.deleteMany({where:{walletId:user.wallet.id}});await p.topupRequest.deleteMany({where:{walletId:user.wallet.id}});await p.wallet.delete({where:{id:user.wallet.id}});await p.user.delete({where:{id:user.id}});}await p.$disconnect();for(const k of ['KASSA24_DEMO','KASSA24_LOGIN','KASSA24_PASSWORD'])if(saved[k]===undefined)delete process.env[k];else process.env[k]=saved[k];
 }
});
