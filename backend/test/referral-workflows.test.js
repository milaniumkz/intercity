const {test}=require('node:test'),assert=require('node:assert/strict');const {PrismaClient}=require('@prisma/client');const {JwtService}=require('@nestjs/jwt');
const {AuthService}=require('../dist/src/auth/auth.service');const {OrdersService}=require('../dist/src/orders/orders.service');const {AdminService}=require('../dist/src/admin/admin.service');const {creditRideReferrals}=require('../dist/src/common/referral-bonus');const {startTripVerification}=require('../dist/src/common/trip-verification');
const database=process.env.TARIFF_TEST_DATABASE_URL;
test('referral registration, real completed trips, review decisions and summary reconcile without duplicate rewards',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/(ui_review_|dispatch_test)/);
 const p=new PrismaClient({datasources:{db:{url:database}}});const rollback=new Error('rollback referral fixtures');let checked=false;
 try {await assert.rejects(p.$transaction(async tx=>{
  const db=new Proxy(tx,{get:(target,key)=>key==='$transaction'?run=>typeof run==='function'?run(db):Promise.all(run):target[key]});
  for(const [key,value]of [['referralCommissionPercent','25'],['kzTaxEnabled','false'],['orderCommissionPercent','10']])await tx.appSettings.upsert({where:{key},create:{key,value},update:{value}});
  const auth=new AuthService(db,new JwtService(),{},{get:key=>key==='PUBLIC_WEB_URL'?'https://example.test':'test-referral-signing-secret-long-enough'});let n=0;
  async function register(referralCode){return (await auth.register({phone:'+7702'+String(Date.now()+n++).slice(-7),name:'Referral QA',password:'LocalFixture2026!',referralCode})).user;}
  const refPassenger=await register(),refDriver=await register();const passenger=await register(refPassenger.refCode.toLowerCase());const driver=await register('https://example.test/#/ref/'+refDriver.refCode.toLowerCase());
  assert.equal((await tx.user.findUnique({where:{id:passenger.id}})).referredBy,refPassenger.refCode);assert.equal((await tx.user.findUnique({where:{id:driver.id}})).referredBy,refDriver.refCode);
  assert.equal((await auth.getReferralSummary(refPassenger.id)).invitedCount,1);assert.equal((await auth.getReferralSummary(refDriver.id)).invitedCount,1);
  await assert.rejects(auth.register({phone:passenger.phone,name:'Duplicate',password:'LocalFixture2026!',referralCode:refDriver.refCode}),e=>e.getStatus()===409);assert.equal((await tx.user.findUnique({where:{id:passenger.id}})).referredBy,refPassenger.refCode);
  const invalidPhone='+7702'+String(Date.now()+100).slice(-7);await assert.rejects(auth.register({phone:invalidPhone,name:'Invalid',password:'LocalFixture2026!',referralCode:'UNKNOWNREFERRALCODE'}),e=>e.getStatus()===400);assert.equal(await tx.user.count({where:{phone:invalidPhone}}),0);
  const profile=await tx.driverProfile.create({data:{userId:driver.id,status:'ACTIVE'}});await tx.wallet.update({where:{userId:driver.id},data:{money:10000,moneyRub:10000}});
  const orders=new OrdersService(db,{}, {},{publish(){}},{sendOrderStatusToPassenger:async()=>{}},{});
  async function trip(currency,verified=true,status='IN_PROGRESS') {
   const order=await tx.order.create({data:{passengerId:passenger.id,driverId:profile.id,fromLat:43,fromLng:76,toLat:43.01,toLng:76.01,fromAddress:'QA A',toAddress:'QA B',distanceKm:1.4,price:1000,commissionAmount:100,currency,status}});
   if(status==='IN_PROGRESS') {await startTripVerification(db,'CITY',order,profile.id,driver.id);if(verified){const now=Date.now();await tx.tripVerification.update({where:{id:'CITY:'+order.id},data:{startedAt:new Date(now-180000),points:[{lat:43,lng:76,accuracy:10,at:new Date(now-180000).toISOString()},{lat:43.01,lng:76.01,accuracy:10,at:new Date(now).toISOString()}]}});}await orders.updateOrderStatus(order.id,'COMPLETED',{userId:driver.id,role:'DRIVER'});await orders.updateOrderStatus(order.id,'COMPLETED',{userId:driver.id,role:'DRIVER'});}return order;
  }
  for(const currency of ['KZT','RUB']) {
   const order=await trip(currency);assert.equal((await tx.tripVerification.findUnique({where:{id:'CITY:'+order.id}})).status,'VERIFIED');
   const ride={id:order.id,currency,commissionAmount:100,passengerId:passenger.id,driverUserId:driver.id};await creditRideReferrals(db,ride);await creditRideReferrals(db,ride);
   for(const inviter of [refPassenger,refDriver]) {const summary=await auth.getReferralSummary(inviter.id);assert.equal(summary.earned[currency],25);const wallet=await tx.wallet.findUnique({where:{userId:inviter.id}});assert.equal(Number(currency==='KZT'?wallet.referralMoney:wallet.bonusRub),25);}
  }
  const held=await trip('KZT',false);assert.equal((await tx.tripVerification.findUnique({where:{id:'CITY:'+held.id}})).status,'REVIEW');assert.equal((await auth.getReferralSummary(refPassenger.id)).earned.KZT,25);
  const admin=new AdminService(db,{publish(){}},{});await admin.decideTripReview('CITY:'+held.id,'APPROVE','Verified by QA fixture',refPassenger.id);assert.equal((await auth.getReferralSummary(refPassenger.id)).earned.KZT,50);await assert.rejects(admin.decideTripReview('CITY:'+held.id,'APPROVE','Duplicate approval',refPassenger.id));assert.equal((await auth.getReferralSummary(refPassenger.id)).earned.KZT,50);
  const rejected=await trip('KZT',false);await admin.decideTripReview('CITY:'+rejected.id,'REJECT','Rejected by QA fixture',refPassenger.id);assert.equal((await auth.getReferralSummary(refPassenger.id)).earned.KZT,50);
  const cancelled=await trip('KZT',false,'SEARCHING_DRIVER');await orders.cancelOrder(cancelled.id,passenger.id);assert.equal((await auth.getReferralSummary(refPassenger.id)).earned.KZT,50);
  await tx.user.update({where:{id:passenger.id},data:{referredBy:passenger.refCode}});await creditRideReferrals(db,{id:'self-invite-test',currency:'KZT',commissionAmount:100,passengerId:passenger.id});assert.equal(Number((await tx.wallet.findUnique({where:{userId:passenger.id}})).referralMoney),0);
  checked=true;throw rollback;
 },{timeout:60000}),e=>e===rollback);assert(checked);}finally{await p.$disconnect()}
});
