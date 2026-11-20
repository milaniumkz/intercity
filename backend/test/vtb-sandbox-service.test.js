const test=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {PrismaClient}=require('@prisma/client');
const {VtbSandboxService}=require('../dist/src/wallet/vtb-sandbox.service');
const database=process.env.VTB_SANDBOX_TEST_DATABASE_URL;
test('VTB sandbox: Russian RUB only, ownership, concurrent requests, forged callbacks and no real wallet credit',{skip:!database},async()=>{
 const url=new URL(database);assert.ok(['localhost','127.0.0.1'].includes(url.hostname));assert.equal(url.pathname,'/vtb_sandbox_test');
 const p=new PrismaClient({datasources:{db:{url:database}}}),key=randomUUID(),cities=[],users=[],oldEnabled=process.env.VTB_SANDBOX_ENABLED;
 process.env.VTB_SANDBOX_ENABLED='true';
 try {
  for(const countryCode of ['RU','KZ'])cities.push(await p.city.create({data:{name:'VTB sandbox '+countryCode+' '+key,countryCode,lat:56.8,lng:60.6}}));
  for(let i=0;i<2;i++)users.push(await p.user.create({data:{phone:'vtb-fixture:'+i+key,name:'VTB fixture',password:'not-a-real-password',refCode:randomUUID(),refLink:'test',role:'DRIVER',cityId:cities[i].id,wallet:{create:{money:111,moneyRub:222,bonus:333,bonusRub:444}}},include:{wallet:true}}));
  const service=new VtbSandboxService(p);let registrations=0,bankState={},lastOrder;
  service.gateway={configured:true,register:async input=>{registrations++;lastOrder=input.orderNumber;return{orderId:randomUUID(),paymentUrl:'https://vtbkz.rbsuat.com/payment/merchants/temp/payment_ru.html'}},status:async()=>bankState,statusByOrderNumber:async()=>bankState};
  assert.equal((await service.instructions(users[0].id)).available,true);
  assert.equal((await service.instructions(users[1].id)).eligible,false);
  await assert.rejects(service.create(users[1].id,{amount:100,currency:'RUB'}),/российского/);
  await assert.rejects(service.create(users[0].id,{amount:100,currency:'KZT'}),/рубли/);
  await assert.rejects(service.create(users[0].id,{amount:1.001,currency:'RUB'}),/сумма/);
  const input={amount:100,currency:'RUB',requestKey:'same-request'};
  const created=await Promise.all(Array.from({length:20},()=>service.create(users[0].id,input)));
  assert.equal(new Set(created.map(x=>x.id)).size,1);assert.equal(registrations,1);
  const id=created[0].id,payment=await p.vtbSandboxPayment.findUnique({where:{id}});
  await assert.rejects(service.create(users[0].id,{...input,amount:101}),/ту же сумму/);
  await assert.rejects(service.check(users[1].id,id),/не найден/);
  const valid={errorCode:0,orderNumber:lastOrder,amount:10000,currency:'643',orderStatus:0,actionCode:0};
  bankState=valid;
  assert.equal((await service.callback({mdOrder:payment.bankOrderId,orderNumber:id,status:1,operation:'deposited'})).status,'PENDING');
  bankState={...valid,orderStatus:1};
  assert.equal((await service.check(users[0].id,id)).status,'PENDING');
  for(const patch of [{amount:9999},{currency:'398'},{orderNumber:'wrong'}]){
   bankState={...valid,orderStatus:2,...patch};
   assert.equal((await service.check(users[0].id,id)).status,'UNVERIFIED');
  }
  bankState={...valid,orderStatus:2};
  assert.equal((await service.check(users[0].id,id)).status,'SUCCEEDED');
  const repeats=await Promise.all(Array.from({length:20},()=>service.callback({mdOrder:payment.bankOrderId,orderNumber:id,status:1})));
  assert.ok(repeats.every(r=>r.status==='SUCCEEDED'&&r.creditsWallet===false));
  const wallet=await p.wallet.findUnique({where:{id:users[0].wallet.id}});
  for(const field of ['money','moneyRub','bonus','bonusRub'])assert.equal(wallet[field],users[0].wallet[field]);
  assert.equal(await p.topupRequest.count({where:{walletId:wallet.id}}),0);
  assert.equal(await p.walletTransaction.count({where:{walletId:wallet.id}}),0);
  service.gateway.register=async()=>{throw Error('fixture-secret-must-not-leak')};
  const uncertain=await service.create(users[0].id,{...input,requestKey:'network-timeout'});
  assert.equal(uncertain.status,'UNKNOWN');assert.ok(!JSON.stringify(uncertain).includes('fixture-secret'));
  assert.equal(uncertain.creditsWallet,false);
  process.env.VTB_SANDBOX_ENABLED='false';
  await assert.rejects(service.create(users[0].id,{...input,requestKey:'disabled'}),/ещё не настроена/);
 } finally {
  if(oldEnabled===undefined)delete process.env.VTB_SANDBOX_ENABLED;else process.env.VTB_SANDBOX_ENABLED=oldEnabled;
  for(const u of users){await p.wallet.deleteMany({where:{userId:u.id}});await p.user.delete({where:{id:u.id}})}
  for(const c of cities)await p.city.delete({where:{id:c.id}});
  await p.$disconnect();
 }
});
