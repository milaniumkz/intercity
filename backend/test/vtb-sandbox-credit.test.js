const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {PrismaClient}=require('@prisma/client');
const {VtbSandboxService}=require('../dist/src/wallet/vtb-sandbox.service');
const database=process.env.VTB_SANDBOX_TEST_DATABASE_URL;
test('VTB confirmed top-ups credit RUB once with atomic history and reconciliation',{skip:!database},async t=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/vtb_sandbox_test');
 const db=new PrismaClient({datasources:{db:{url:database}}}),ids=[],bank=new Map();
 const oldEnabled=process.env.VTB_SANDBOX_ENABLED,oldCredits=process.env.VTB_SANDBOX_WALLET_CREDITS_ENABLED;
 process.env.VTB_SANDBOX_ENABLED='true';process.env.VTB_SANDBOX_WALLET_CREDITS_ENABLED='true';
 const city=await db.city.create({data:{name:'VTB credit QA '+randomUUID(),countryCode:'RU',lat:56.8,lng:60.6}});
 const gateway={configured:true,
  register:async input=>{const orderId=randomUUID();bank.set(orderId,{errorCode:0,orderNumber:input.orderNumber,amount:input.amountMinor,currency:'398',orderStatus:0,actionCode:0});return{orderId,paymentUrl:'https://vtbkz.rbsuat.com/payment/merchants/ecom/payment.html'};},
  status:async id=>bank.get(id),
  statusByOrderNumber:async number=>[...bank.values()].find(x=>x.orderNumber===number),
 };
 const serviceFor=client=>{const s=new VtbSandboxService(client);s.gateway=gateway;return s;};
 const service=serviceFor(db);
 async function user(withWallet=true){
  const u=await db.user.create({data:{phone:'vtb-credit:'+randomUUID(),name:'Isolated credit QA',password:'unused-fixture-password',refCode:randomUUID(),refLink:'',role:'DRIVER',cityId:city.id,
   ...(withWallet?{wallet:{create:{money:11,moneyRub:22,bonus:33,bonusRub:44}}}:{})}});
  ids.push(u.id);return u;
 }
 const create=(u,amount=100)=>service.create(u.id,{amount,currency:'RUB',purpose:'TOPUP',requestKey:randomUUID()});
 async function row(payment){return db.vtbSandboxPayment.findUniqueOrThrow({where:{id:payment.id}});}
 async function paid(payment){const p=await row(payment);bank.get(p.bankOrderId).orderStatus=2;return p;}
 const wallet=u=>db.wallet.findUniqueOrThrow({where:{userId:u.id}});
 try {
  await t.test('pending and forged callbacks do not credit; forty concurrent checks and callbacks credit once',async()=>{
   const u=await user(),payment=await create(u),p=await row(payment);
   assert.equal(payment.creditsWallet,true);assert.equal(payment.creditedAt,null);
   await service.callback({mdOrder:p.bankOrderId,orderNumber:p.id,status:2,operation:'deposited'});
   assert.equal((await wallet(u)).moneyRub,22);
   await paid(payment);
   await db.vtbSandboxPayment.update({where:{id:p.id},data:{createdAt:new Date(Date.now()-10000)}});
   const results=await Promise.all([
    ...Array.from({length:20},()=>service.check(u.id,p.id)),
    ...Array.from({length:20},()=>service.callback({mdOrder:p.bankOrderId,orderNumber:p.id,status:2})),
    service.reconcileTopups(),
   ]);
   assert(results.filter(Boolean).every(x=>x.status==='SUCCEEDED'&&!!x.creditedAt));
   const w=await wallet(u);assert.equal(w.moneyRub,122);assert.equal(w.money,11);assert.equal(w.bonus,33);assert.equal(w.bonusRub,44);
   const events=await db.walletTransaction.findMany({where:{walletId:w.id}});
   assert.equal(events.length,1);assert.equal(events[0].id,p.id);assert.equal(events[0].currency,'RUB');assert.equal(events[0].amount,100);
   assert.equal(events[0].type,'TOPUP_DEMO_CREDIT');
   const topups=await db.topupRequest.findMany({where:{walletId:w.id}});
   assert.equal(topups.length,1);assert.equal(topups[0].status,'APPROVED');assert.equal(topups[0].provider,'VTB_SANDBOX');
  });
  await t.test('wrong amount, currency, order number, failures and cancellations never credit',async()=>{
   for(const patch of [{amount:69999},{currency:'643'},{orderNumber:'foreign-order'},{orderStatus:6},{orderStatus:3}]){
    const u=await user(),payment=await create(u),p=await paid(payment);
    bank.set(p.bankOrderId,{...bank.get(p.bankOrderId),...patch});
    await service.check(u.id,p.id);
    const w=await wallet(u);assert.equal(w.moneyRub,22);
    assert.equal(await db.walletTransaction.count({where:{walletId:w.id}}),0);
    assert.equal((await row(payment)).creditedAt,null);
   }
  });
  await t.test('ledger failure rolls back balance, history and marker; retry credits once',async()=>{
   const u=await user(),payment=await create(u);await paid(payment);
   const broken=db.$extends({query:{walletTransaction:{async create(){throw new Error('isolated-secret-must-not-leak');}}}});
   await assert.rejects(serviceFor(broken).check(u.id,payment.id),error=>error?.getStatus?.()===503&&!JSON.stringify(error).includes('isolated-secret'));
   const w=await wallet(u);assert.equal(w.moneyRub,22);
   assert.equal(await db.topupRequest.count({where:{walletId:w.id}}),0);
   assert.equal(await db.walletTransaction.count({where:{walletId:w.id}}),0);
   assert.equal((await row(payment)).creditedAt,null);
   await service.check(u.id,payment.id);await service.check(u.id,payment.id);
   assert.equal((await wallet(u)).moneyRub,122);
   assert.equal(await db.walletTransaction.count({where:{walletId:w.id}}),1);
  });
  await t.test('twenty different confirmed payments create a missing wallet without lost increments',async()=>{
   const u=await user(false),payments=await Promise.all(Array.from({length:20},()=>create(u,1.25)));
   await Promise.all(payments.map(paid));
   await Promise.all(payments.map(p=>service.check(u.id,p.id)));
   const w=await wallet(u);assert.equal(w.moneyRub,25);assert.equal(w.money,0);
   assert.equal(await db.walletTransaction.count({where:{walletId:w.id}}),20);
   assert.equal(await db.topupRequest.count({where:{walletId:w.id}}),20);
  });
  await t.test('server reconciliation credits after the user closes the bank page',async()=>{
   const u=await user(),payment=await create(u,5);await paid(payment);
   await db.vtbSandboxPayment.update({where:{id:payment.id},data:{createdAt:new Date(Date.now()-10000)}});
   await service.reconcileTopups();await service.reconcileTopups();
   assert.equal((await wallet(u)).moneyRub,27);assert((await row(payment)).creditedAt);
  });
  await t.test('legacy and credit-disabled payments are never retroactively credited',async()=>{
   const u=await user();
   const legacy=await db.vtbSandboxPayment.create({data:{userId:u.id,requestKey:randomUUID(),amountMinor:10000,bankAmountMinor:70000,conversionRate:7,status:'SUCCEEDED'}});
   assert.equal((await service.check(u.id,legacy.id)).creditsWallet,false);
   process.env.VTB_SANDBOX_WALLET_CREDITS_ENABLED='false';
   const disabled=await create(u);await paid(disabled);
   process.env.VTB_SANDBOX_WALLET_CREDITS_ENABLED='true';
   const result=await service.check(u.id,disabled.id);
   assert.equal(result.creditsWallet,false);assert.equal(result.creditedAt,null);
   assert.equal((await wallet(u)).moneyRub,22);
  });
  await t.test('a captured payment keeps its credit instruction when the new-payment switch changes',async()=>{
   const u=await user(),payment=await create(u);await paid(payment);
   process.env.VTB_SANDBOX_WALLET_CREDITS_ENABLED='false';
   try{const result=await service.check(u.id,payment.id);assert(result.creditedAt);assert.equal((await wallet(u)).moneyRub,122);}
   finally{process.env.VTB_SANDBOX_WALLET_CREDITS_ENABLED='true';}
  });
 } finally {
  if(oldEnabled===undefined)delete process.env.VTB_SANDBOX_ENABLED;else process.env.VTB_SANDBOX_ENABLED=oldEnabled;
  if(oldCredits===undefined)delete process.env.VTB_SANDBOX_WALLET_CREDITS_ENABLED;else process.env.VTB_SANDBOX_WALLET_CREDITS_ENABLED=oldCredits;
  const wallets=await db.wallet.findMany({where:{userId:{in:ids}},select:{id:true}});
  const walletIds=wallets.map(x=>x.id);
  await db.walletTransaction.deleteMany({where:{walletId:{in:walletIds}}});
  await db.topupRequest.deleteMany({where:{walletId:{in:walletIds}}});
  await db.wallet.deleteMany({where:{userId:{in:ids}}});
  await db.user.deleteMany({where:{id:{in:ids}}});
  await db.city.delete({where:{id:city.id}});
  await db.$disconnect();
 }
});
