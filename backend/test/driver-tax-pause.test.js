const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {PrismaClient}=require('@prisma/client'),{DriverService}=require('../dist/src/driver/driver.service'),{TaxService}=require('../dist/src/tax/tax.service'),{recordTaxIncome}=require('../dist/src/tax/tax-ledger');
const {WalletService}=require('../dist/src/wallet/wallet.service');
const {AdminService}=require('../dist/src/admin/admin.service');
const database=process.env.TARIFF_TEST_DATABASE_URL;
test('pause permits unclassified drivers, stops all new withholding/debt collection, preserves referral rewards and can be reversed',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/(ui_review_|dispatch_test)/);
 const p=new PrismaClient({datasources:{db:{url:database}}}),rollback=Error('rollback tax pause');
 try {await assert.rejects(p.$transaction(async tx=>{
  const db=new Proxy(tx,{get:(target,key)=>key==='$transaction'?fn=>fn(db):target[key]});
  for(const [key,value] of [['kzTaxEnabled','true'],['driverTaxIntegrationPaused','true'],['referralMinPayoutKzt','5000']]) await tx.appSettings.upsert({where:{key},create:{key,value},update:{value}});
  const city=await tx.city.create({data:{name:'QA '+randomUUID(),countryCode:'KZ',lat:43,lng:76}});
  const u=await tx.user.create({data:{phone:'pause:'+randomUUID(),password:'qa',name:'Driver QA',refCode:randomUUID(),refLink:'qa',cityId:city.id}});
  await tx.wallet.create({data:{userId:u.id,money:10000}});
  const tax=new TaxService(db),drivers=new DriverService(db,{}, {publish(){}},{},{},tax);
  const profile=await drivers.createProfile(u.id,{carModel:'QA',carNumber:'QA01',taxCountry:'KZ'});await tx.driverProfile.update({where:{id:profile.id},data:{status:'ACTIVE'}});
  await drivers.setOnline(u.id,{isOnline:true,cityId:city.id});assert.equal((await tx.driverOnline.findUnique({where:{driverId:profile.id}})).isOnline,true);
  const event={key:randomUUID(),userId:u.id,sourceKind:'CITY',sourceId:randomUUID(),gross:10000,currency:'KZT',occurredAt:new Date()};
  assert.equal(await recordTaxIncome(db,event),null);assert.equal((await tx.wallet.findUnique({where:{userId:u.id}})).money,10000);
  const ref={...event,key:randomUUID(),sourceKind:'REFERRAL',gross:25};
  const first=await recordTaxIncome(db,ref);const second=await recordTaxIncome(db,ref);assert.equal(first.id,second.id);assert.equal(first.profileKind,'SELF_ACCOUNTED_DRIVER');assert.equal(Number(first.withheld),0);assert.equal(Number((await tx.wallet.findUnique({where:{userId:u.id}})).referralMoney),25);
  assert.equal((await tax.collectDebt(u.id)).paused,true);
  await recordTaxIncome(db,{...ref,key:randomUUID(),gross:6000});
  const walletService=new WalletService(db,tax);walletService.kassa24Login='';walletService.kassa24Password='';
  const payout=await walletService.createPayoutRequest(u.id,{amount:5000,source:'REFERRAL',currency:'KZT',cardNumber:'4000000000000002'},'DRIVER');
  assert.equal(payout.source,'REFERRAL');assert.equal((await tx.wallet.findUnique({where:{userId:u.id}})).money,10000);assert.equal(Number((await tx.wallet.findUnique({where:{userId:u.id}})).referralMoney),1025);
  const admin=new AdminService(db,{},{});await admin.setSetting('driverTaxIntegrationPaused','false');assert.equal((await tx.driverOnline.findUnique({where:{driverId:profile.id}})).isOnline,false);
  await assert.rejects(drivers.setOnline(u.id,{isOnline:true,cityId:city.id}),/налоговый статус/);
  assert.deepEqual(await tx.taxIncomeEntry.findUnique({where:{id:first.id}}),first);
  throw rollback;
 },{timeout:30000}),e=>e===rollback)}finally{await p.$disconnect()}
});
