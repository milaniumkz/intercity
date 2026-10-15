const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { PrismaClient } = require('@prisma/client');
const { socialIncrement, kazakhstanPeriod } = require('../dist/src/tax/kz-social-calculator');
const { TaxService, validIin } = require('../dist/src/tax/tax.service');
const { recordTaxIncome, releasePendingIncome } = require('../dist/src/tax/tax-ledger');
const { WalletService } = require('../dist/src/wallet/wallet.service');
const { AdminService } = require('../dist/src/admin/admin.service');
const {validateSync}=require('class-validator');
const {VerifyTaxProfileDto}=require('../dist/src/tax/tax.dto');
const { IntercityService } = require('../dist/src/intercity/intercity.service');

test('social payments use cumulative rounding, Kazakhstan calendar, SO cap and verified exemptions', () => {
  assert.equal(socialIncrement(0, 10000, 85000).total.toString(), '400');
  const cap = socialIncrement(590000, 10000, 85000);
  assert.equal(cap.SO.toString(), '50'); assert.equal(cap.total.toString(), '350');
  assert.equal(socialIncrement(0, 10000, 85000, ['OPVR', 'OSMS']).total.toString(), '200');
  let cumulative = 0, paid = 0;
  for (let n = 0; n < 100; n++) { paid += Number(socialIncrement(cumulative, .17, 85000).total); cumulative += .17; }
  assert.ok(Math.abs(paid - .68) < .000001);
  assert.equal(kazakhstanPeriod(new Date('2026-10-31T19:01:00Z')), '2026-11');
  assert.equal(validIin('000000000000'), false); assert.equal(validIin('123'), false);
  for(const birthDate of ['1975-01-01T00:00:00+05:00','1990-02-31']) {
    const dto=Object.assign(new VerifyTaxProfileDto(),{status:'VERIFIED',reference:'verified document',exemptions:[],birthDate});
    assert.ok(validateSync(dto).some(error=>error.property==='birthDate'));
  }
});

const database = process.env.DISPATCH_TEST_DATABASE_URL;
test('KZ monetary referrals: verified status, no duplicate money, caps, IP, currency review, payouts and refunds', { skip: !database }, async () => {
  const url = new URL(database); assert.equal(url.hostname, '127.0.0.1'); assert.equal(url.pathname, '/dispatch_test');
  const p = new PrismaClient({ datasources: { db: { url: database } } });
  const tax = new TaxService(p), key = `tax-test:${randomUUID()}`, owners = [], driverProfiles = [], requests = [], cities = [];
  const settingKeys = ['kzTaxEnabled','kzTaxOperatorReference','kzTaxReferralContractReference','referralMinPayoutKzt',`kzTaxPolicy${new Date().getUTCFullYear()}`];
  const previous = await p.appSettings.findMany({where:{key:{in:settingKeys}}});
  const oldKey = process.env.TAX_ID_ENCRYPTION_KEY;
  process.env.TAX_ID_ENCRYPTION_KEY = 'isolated-test-tax-encryption-secret-only';
  const oldFetch = global.fetch;
  global.fetch = async () => ({ok:false,json:async()=>({})}); // No real payment request in a test.
  const period = kazakhstanPeriod(new Date());
  function syntheticIin(prefix) {
    const digits = [...prefix].map(Number);
    const sum = weights => weights.reduce((n,w,i)=>n+w*digits[i],0)%11;
    let digit=sum([1,2,3,4,5,6,7,8,9,10,11]);
    if(digit===10) digit=sum([3,4,5,6,7,8,9,10,11,1,2]);
    if(digit===10) return syntheticIin(String(Number(prefix)+1));
    return prefix+digit;
  }
  async function user(kind='SELF_EMPLOYED') {
    const u=await p.user.create({data:{phone:`${key}:${owners.length}`,password:'test-only',name:'Tax fixture',refCode:randomUUID(),refLink:'test',wallet:{create:{money:0,bonus:123,lockedBonus:0}}},include:{wallet:true}});
    owners.push(u.id);
    const iin=syntheticIin(String(90010130001 + owners.length * 10));
    const declared=await tax.declare(u.id,{countryCode:'KZ',kind,iin,activities:['49320','82990'],consent:true});
    assert.equal(declared.iinEncrypted,undefined); assert.equal(declared.status,'PENDING');
    assert.equal((await tax.protectedIdentity(u.id)).iin,iin);
    await tax.verify(u.id,{status:'VERIFIED',birthDate:'1990-01-01',effectiveFrom:'2026-01-01',reference:'TEST verified declaration',exemptions:[]},'test-admin');
    await tax.monthlyBasis(u.id,{period,externalGross:0,reference:'TEST verified zero external income'},'test-admin');
    return u;
  }
  const credit = (u,id,gross=10000,currency='KZT',sourceKind='REFERRAL') => p.$transaction(tx => recordTaxIncome(tx,{key:`${key}:${id}`,userId:u.id,sourceKind,sourceId:id,gross,currency,occurredAt:new Date()}));
  try {
    const legacy=[];
    for(const countryCode of ['KZ','RU']) {
      const city=await p.city.create({data:{name:key+countryCode,countryCode,lat:50,lng:80}});cities.push(city.id);
      const oldDriver=await p.user.create({data:{phone:key+countryCode,password:'test',name:'Legacy',refCode:randomUUID(),refLink:'test',role:'DRIVER',cityId:city.id}});owners.push(oldDriver.id);
      const dp=await p.driverProfile.create({data:{userId:oldDriver.id,status:'APPROVED',online:{create:{isOnline:true,cityId:city.id}}}});driverProfiles.push(dp.id);legacy.push(dp.id);
    }
    await tax.configure({enabled:true,operatorReference:'',referralContractReference:'',minPayout:5000,year:new Date().getUTCFullYear().toString(),mrp:4325,mzp:85000,policyReference:'TEST annual policy'});
    assert.equal((await p.driverOnline.findUnique({where:{driverId:legacy[0]}})).isOnline,false);
    assert.equal((await p.driverOnline.findUnique({where:{driverId:legacy[1]}})).isOnline,true);
    const u=await user();
    await Promise.all([credit(u,'same'),credit(u,'same'),credit(u,'same')]);
    assert.equal(await p.taxIncomeEntry.count({where:{ownerKey:u.id}}),1);
    let wallet=await p.wallet.findUnique({where:{userId:u.id}});
    assert.equal(wallet.referralMoney.toString(),'9600');assert.equal(wallet.bonus,123);assert.equal(wallet.money,0);
    const income=await p.taxIncomeEntry.findFirst({where:{ownerKey:u.id}});
    assert.equal(income.withheld.toString(),'400');
    await assert.rejects(tax.monthlyBasis(u.id,{period,externalGross:0,reference:'Attempt to rewrite used basis'},'test-admin'));
    await assert.rejects(tax.verify(u.id,{status:'VERIFIED',birthDate:'1990-01-01',effectiveFrom:'2026-01-01',reference:'Attempt to change used exemptions',exemptions:['OSMS']},'test-admin'));
    await credit(u,'rub',1000,'RUB');
    assert.equal((await p.taxIncomeEntry.findUnique({where:{eventKey:`${key}:rub`}})).status,'REVIEW');
    assert.equal((await p.wallet.findUnique({where:{userId:u.id}})).referralMoney.toString(),'9600');
    const quick=await user();
    await p.taxPeriodBasis.deleteMany({where:{ownerKey:quick.id}});
    await p.taxProfile.update({where:{userId:quick.id},data:{status:'PENDING',birthDate:null,effectiveFrom:null}});
    const quickProfile=await tax.verify(quick.id,{status:'VERIFIED',quickApproval:true},'test-admin');
    assert.equal(quickProfile.status,'VERIFIED');
    assert.equal(quickProfile.birthDate.toISOString().slice(0,10),'1990-01-01');
    assert.equal(quickProfile.verifiedBy,'test-admin');
    assert.ok(quickProfile.effectiveFrom <= new Date());
    assert.equal(await p.taxPeriodBasis.count({where:{ownerKey:quick.id}}),0);
    const rejected=await tax.verify(quick.id,{status:'REJECTED',quickApproval:true},'test-admin');
    assert.equal(rejected.status,'REJECTED');
    const ie=await user('IE'); await credit(ie,'ie');
    assert.equal((await p.wallet.findUnique({where:{userId:ie.id}})).referralMoney.toString(),'10000');
    assert.equal((await p.taxIncomeEntry.findUnique({where:{eventKey:`${key}:ie`}})).withheld.toString(),'0');
    const cap=await user(); await credit(cap,'cap',600000);
    const capIncome=await p.taxIncomeEntry.findUnique({where:{eventKey:`${key}:cap`}});
    assert.equal(capIncome.so.toString(),'5950'); assert.equal(capIncome.withheld.toString(),'23950');
    const cash=await user(); await credit(cash,'cash',1000,'KZT','CITY');
    const cashIncome=await p.taxIncomeEntry.findUnique({where:{eventKey:`${key}:cash`}});
    assert.equal(cashIncome.withheld.toString(),'0');assert.equal(cashIncome.opv.toString(),'10');
    await p.wallet.update({where:{userId:cash.id},data:{money:100,lockedBonus:80}});
    assert.equal((await tax.collectDebt(cash.id)).collected.toString(),'20');
    assert.equal((await p.wallet.findUnique({where:{userId:cash.id}})).money,80);
    assert.equal((await tax.collectDebt(cash.id)).collected.toString(),'0');
    await p.wallet.update({where:{userId:cash.id},data:{money:100}});
    assert.equal((await tax.collectDebt(cash.id)).collected.toString(),'20');
    assert.equal((await p.taxIncomeEntry.findUnique({where:{eventKey:`${key}:cash`}})).withheld.toString(),'40');
    const pending=await user();await p.taxProfile.update({where:{userId:pending.id},data:{status:'PENDING'}});
    await credit(pending,'pending');assert.equal((await p.wallet.findUnique({where:{userId:pending.id}})).referralMoney.toString(),'0');
    await tax.verify(pending.id,{status:'VERIFIED',birthDate:'1990-01-01',effectiveFrom:'2026-01-01',reference:'TEST verification after entitlement',exemptions:[]},'test-admin');
    const release=await p.$transaction(tx=>releasePendingIncome(tx,pending.id));assert.equal(release.released,1);
    await p.$transaction(tx=>releasePendingIncome(tx,pending.id));
    assert.equal((await p.wallet.findUnique({where:{userId:pending.id}})).referralMoney.toString(),'9600');
    const service=new WalletService(p,tax);
    await assert.rejects(service.createPayoutRequest(u.id,{source:'REFERRAL',amount:4999,currency:'KZT',cardNumber:'4000000000000002'},'PASSENGER'));
    await assert.rejects(service.createPayoutRequest(u.id,{source:'REFERRAL',amount:5000,currency:'RUB',cardNumber:'4000000000000002'},'PASSENGER'));
    const payouts=await Promise.allSettled([1,2].map(()=>service.createPayoutRequest(u.id,{source:'REFERRAL',amount:5000,currency:'KZT',cardNumber:'4000000000000002'},'PASSENGER')));
    assert.equal(payouts.filter(r=>r.status==='fulfilled').length,1);
    const payout=payouts.find(r=>r.status==='fulfilled').value;
    assert.equal((await p.wallet.findUnique({where:{userId:u.id}})).referralMoney.toString(),'4600');
    // A user can trigger a callback, but cannot assert that money was paid.
    // A real authenticated provider confirmation is required and replay-safe.
    const paymentService=new WalletService(p,tax);
    const deposit=await p.topupRequest.create({data:{walletId:u.wallet.id,amount:100,currency:'KZT',provider:'ONLINE',externalOrderId:'provider-'+key}});
    paymentService.gateway.status=async()=>({orderId:deposit.id,merchantId:'wrong-merchant',amount:10000,demo:false,status:1});
    assert.equal((await paymentService.handleTopupPaymentCallback({orderId:deposit.id,paid:true})).ignored,true);
    assert.equal((await p.wallet.findUnique({where:{userId:u.id}})).money,0);
    paymentService.gateway.status=async()=>({orderId:deposit.id,merchantId:paymentService.kassa24Login,amount:10000,demo:false,status:1});
    await Promise.all([paymentService.handleTopupPaymentCallback({orderId:deposit.id,paid:true}),paymentService.handleTopupPaymentCallback({orderId:deposit.id,paid:true})]);
    assert.equal((await p.wallet.findUnique({where:{userId:u.id}})).money,100);
    assert.equal(await p.walletTransaction.count({where:{topupRequestId:deposit.id,type:'TOPUP_PAID_ONLINE'}}),1);
    const admin=new AdminService(p,{publish:()=>{}},{});
    await admin.rejectPayout(payout.id);
    wallet=await p.wallet.findUnique({where:{userId:u.id}});assert.equal(wallet.referralMoney.toString(),'9600');assert.equal(wallet.money,100);assert.equal(wallet.bonus,123);
    await assert.rejects(admin.rejectPayout(payout.id));
    await tax.remittance({ownerKey:u.id,period,component:'OPV',amount:100,reference:`${key}:bank-payment`,paidAt:new Date().toISOString(),note:'TEST actual bank confirmation'},'test-admin');
    await assert.rejects(tax.remittance({ownerKey:u.id,period,component:'OPV',amount:1,reference:`${key}:bank-payment`,paidAt:new Date().toISOString(),note:'Duplicate'},'test-admin'));
    const registry=await tax.registry(period,'SELF_EMPLOYED'); const row=registry.rows.find(r=>r.ownerKey===u.id);
    assert.equal(row.withheld.toString(),'400');assert.equal(row.paid.toString(),'100');assert.equal(row.payable.toString(),'300');
    assert.equal(JSON.stringify(registry).includes('iinEncrypted'),false);
    // Real completion debits commission before posting cash income. It races
    // with debt collection/payouts on the same wallet; neither may deadlock or
    // collect a social payment twice.
    const driver = await user();
    await p.user.update({where:{id:driver.id},data:{role:'DRIVER',phone:'+77'+String(Date.now()).slice(-9)}});
    await p.wallet.update({where:{userId:driver.id},data:{money:10000}});
    const profile = await p.driverProfile.create({data:{userId:driver.id,status:'APPROVED',online:{create:{isOnline:true,lastLat:49.9,lastLng:82.6}}}});
    driverProfiles.push(profile.id);
    const intercity = new IntercityService(p,{getRoute:async()=>({distance:100,duration:60})},{},{publish:()=>{}},{});
    for(let n=0;n<6;n++) {
      const request=await p.intercityRequest.create({data:{passengerId:u.id,selectedDriverId:driver.id,status:'IN_PROGRESS',currency:'KZT',paymentMethod:'CASH',price:1000,fromCity:'Test origin',toCity:'Test destination',date:new Date()}});
      requests.push(request.id);
    }
    const financial = await Promise.allSettled([...requests.map(id=>intercity.updateDriverRequestStatus(driver.id,id,'COMPLETED')), ...Array.from({length:6},()=>tax.collectDebt(driver.id))]);
    const failed = financial.filter(result=>result.status==='rejected');
    assert.equal(failed.length,0,failed.map(result=>result.reason.message).join('\n'));
    const posted=await p.taxIncomeEntry.findMany({where:{ownerKey:driver.id,sourceKind:'INTERCITY'}});
    assert.equal(posted.length,6);assert.equal(posted.reduce((sum,row)=>sum+Number(row.withheld),0),240);
    assert.ok((await p.wallet.findUnique({where:{userId:driver.id}})).money>=0);
  } finally {
    global.fetch=oldFetch;
    if(oldKey===undefined) delete process.env.TAX_ID_ENCRYPTION_KEY;else process.env.TAX_ID_ENCRYPTION_KEY=oldKey;
    await p.taxIncomeEntry.deleteMany({where:{ownerKey:{in:owners}}});await p.taxPeriodBasis.deleteMany({where:{ownerKey:{in:owners}}});await p.taxRemittance.deleteMany({where:{ownerKey:{in:owners}}});await p.taxAccountingIdentity.deleteMany({where:{ownerKey:{in:owners}}});
    const wallets=await p.wallet.findMany({where:{userId:{in:owners}},select:{id:true}});const ids=wallets.map(w=>w.id);
    await p.walletTransaction.deleteMany({where:{walletId:{in:ids}}});await p.payoutRequest.deleteMany({where:{walletId:{in:ids}}});await p.topupRequest.deleteMany({where:{walletId:{in:ids}}});
    await p.tripVerification.deleteMany({where:{driverUserId:{in:owners}}});await p.intercityRequest.deleteMany({where:{id:{in:requests}}});
    await p.driverDailyParticipation.deleteMany({where:{driverId:{in:driverProfiles}}});await p.driverOnline.deleteMany({where:{driverId:{in:driverProfiles}}});await p.driverProfile.deleteMany({where:{id:{in:driverProfiles}}});
    await p.wallet.deleteMany({where:{userId:{in:owners}}});await p.user.deleteMany({where:{id:{in:owners}}});await p.city.deleteMany({where:{id:{in:cities}}});
    await p.appSettings.deleteMany({where:{key:{in:settingKeys}}});for(const row of previous) await p.appSettings.create({data:{key:row.key,value:row.value}});
    await p.$disconnect();
  }
});
