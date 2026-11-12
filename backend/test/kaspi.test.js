const test=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('crypto');
const {PrismaClient}=require('@prisma/client');
const {KaspiService,kaspiAmount,kaspiDate,KASPI_IPS}=require('../dist/src/wallet/kaspi.service');
const {KaspiController}=require('../dist/src/wallet/kaspi.controller');
test('Kaspi validates money and dates without losing 18-digit transaction IDs',async()=>{
 for(const raw of ['0.00','-1.00','1','1.001','1,00','NaN','1e3','10000000.01'])assert.equal(kaspiAmount(raw),null);
 assert.equal(kaspiAmount('0.01'),1);assert.equal(kaspiAmount('10000000.00'),1000000000);
 assert(kaspiDate('20261112123456'));assert(!kaspiDate('20260230120000'));assert(!kaspiDate('20261112240000'));
 const svc=new KaspiService({user:{findUnique:async()=>({driverProfile:{},wallet:{}})}});
 const r=await svc.process({command:'check',txn_id:'999999999999999999',account:'70000000001',sum:'fictional'});
 assert.equal(r.result,0);assert.equal(r.txn_id,'999999999999999999');
 assert.equal((await svc.process({command:['check'],txn_id:'1',account:'70000000001'})).result,5);
});
test('Kaspi rejects untrusted IP and ignores forged forwarded headers',async()=>{
 let calls=0;const c=new KaspiController({process:async()=>{calls++;return{result:0}}});
 const response={headers:{},setHeader(k,v){this.headers[k]=v},status(code){this.code=code;return this},json(body){this.body=body;return this}};
 await c.callback({txn_id:'1'},{ip:'127.0.0.1',headers:{'x-forwarded-for':KASPI_IPS[0]}},response);
 assert.equal(response.code,403);assert.equal(calls,0);assert.match(response.headers['Cache-Control'],/no-store/);
 await c.callback({txn_id:'1'},{ip:'::ffff:'+KASPI_IPS[0]},response);assert.equal(response.code,200);assert.equal(calls,1);
});
test('wallet history shows a human Kaspi label instead of bank metadata',async()=>{
 const {WalletService}=require('../dist/src/wallet/wallet.service');
 const wallet={id:'w',money:0,bonus:0,moneyRub:0,bonusRub:0,lockedBonus:0,lockedBonusRub:0,referralMoney:0};
 const p={wallet:{findUnique:async()=>wallet},topupRequest:{findMany:async()=>[]},payoutRequest:{findMany:async()=>[]},walletTransaction:{findMany:async()=>[{type:'TOPUP_KASPI',note:'{"txn_date":"20261112150000"}'}]}};
 const result=await new WalletService(p,{}).getWallet('user');assert.equal(result.transactions[0].note,'Пополнение через Kaspi');
});
const database=process.env.DISPATCH_TEST_DATABASE_URL||process.env.TARIFF_TEST_DATABASE_URL;
test('Kaspi credits once under concurrent retries, preserves bank date and rolls back failed ledger writes',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/dispatch_test');
 const p=new PrismaClient({datasources:{db:{url:database}}});const key=randomUUID();let user;
 try {
  user=await p.user.create({data:{phone:'+700'+String(Date.now()).slice(-8),name:'Kaspi isolated test',password:'not-a-login-hash',refCode:key,refLink:'',role:'DRIVER',wallet:{create:{money:10,moneyRub:55}},driverProfile:{create:{status:'PENDING'}}},include:{wallet:true}});
  const service=new KaspiService(p),q={command:'pay',txn_id:String(Date.now())+'111',account:user.phone.slice(1),sum:'123.45',txn_date:'20261112120001'};
  const results=await Promise.all(Array.from({length:12},()=>service.process(q)));
  for(const r of results){assert.equal(r.result,0);assert.equal(r.prv_txn_id,results[0].prv_txn_id);assert.match(r.prv_txn_id,/^\d{1,20}$/);assert.equal(r.sum,'123.45');}
  let wallet=await p.wallet.findUnique({where:{id:user.wallet.id}});assert.equal(wallet.money,133.45);assert.equal(wallet.moneyRub,55);
  const ledger=await p.walletTransaction.findMany({where:{walletId:wallet.id}});assert.equal(ledger.length,1);assert.equal(JSON.parse(ledger[0].note).txn_date,q.txn_date);
  assert.equal((await service.process({...q,sum:'999.00'})).result,5);
  assert.equal((await service.process({...q,account:'70000000002'})).result,5);
  assert.equal((await service.process({...q,txn_id:q.txn_id+'2',account:'70000000002'})).result,1);
  // A forged generic card callback must never confirm a Kaspi credit.
  const broken=new Proxy(p,{get:(target,k)=>k==='$transaction'?cb=>p.$transaction(tx=>cb(new Proxy(tx,{get:(t,j)=>j==='walletTransaction'?{create:async()=>{throw Error('ledger unavailable')}}:t[j]}))):target[k]});
  assert.equal((await new KaspiService(broken).process({...q,txn_id:q.txn_id+'3'})).result,5);
  wallet=await p.wallet.findUnique({where:{id:wallet.id}});assert.equal(wallet.money,133.45);
  assert.equal(await p.topupRequest.count({where:{externalOrderId:'kaspi:'+q.txn_id+'3'}}),0);
  assert.equal((await service.process({...q,txn_id:q.txn_id+'3'})).result,0);
  assert.equal(Math.round((await p.wallet.findUnique({where:{id:wallet.id}})).money*100),25690);
  await p.user.update({where:{id:user.id},data:{blockedAt:new Date()}});
  assert.equal((await service.process({...q,command:'check'})).result,1);
  assert.equal((await service.process(q)).result,0); // settled replay survives subsequent account blocking
 }finally{
  if(user){await p.walletTransaction.deleteMany({where:{walletId:user.wallet.id}});await p.topupRequest.deleteMany({where:{walletId:user.wallet.id}});await p.driverProfile.deleteMany({where:{userId:user.id}});await p.wallet.delete({where:{id:user.wallet.id}});await p.user.delete({where:{id:user.id}});}await p.$disconnect();
 }
});
