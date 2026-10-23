const {test}=require('node:test');const assert=require('node:assert/strict');const {randomUUID}=require('node:crypto');const {PrismaClient}=require('@prisma/client');const {IntercityService}=require('../dist/src/intercity/intercity.service');const {DriverService}=require('../dist/src/driver/driver.service');
const database=process.env.TARIFF_TEST_DATABASE_URL;
test('delivery eligibility and cancellation preserve bonuses and the exact reserved route',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/(ui_review_|dispatch_test)/);
 const p=new PrismaClient({datasources:{db:{url:database}}});const done=new Error('rollback fixtures');let checked=false;
 try {await assert.rejects(p.$transaction(async tx=>{
  const db=new Proxy(tx,{get:(target,key)=>key==='$transaction'?run=>run(db):target[key]});
  const suffix=randomUUID();const passenger=await tx.user.create({data:{phone:'qa-passenger:'+suffix,password:'fixture',name:'QA fixture',refCode:randomUUID(),refLink:'test',wallet:{create:{bonus:20000,bonusRub:20000}}}});
  const driver=await tx.user.create({data:{phone:'+7701'+Date.now(),password:'fixture',name:'QA fixture',refCode:randomUUID(),refLink:'test',role:'DRIVER',wallet:{create:{money:20000,moneyRub:20000}},driverProfile:{create:{status:'ACTIVE',acceptIntercity:true,acceptDelivery:true}}},include:{driverProfile:true}});
  let currency='KZT';const svc=new IntercityService(db,{departureCurrency:async()=>currency,cityNameAtPoint:async()=>null},{});const data={fromCity:'From '+suffix,toCity:'To '+suffix,date:new Date(Date.now()+86400000).toISOString(),fromLat:43,fromLng:76,toLat:44,toLng:77};
  await tx.appSettings.upsert({where:{key:'orderCommissionPercent'},create:{key:'orderCommissionPercent',value:'10'},update:{value:'10'}});
  const delivery=await svc.createRequest(passenger.id,{...data,fromAddressLabel:'Exact pickup without city',toAddressLabel:'Exact destination without city',requestType:'DELIVERY_CITY',itemDescription:'Коробка',itemWeightKg:10});
  assert.equal(delivery.fromCity,data.fromCity);assert.equal(delivery.toCity,data.toCity);
  let offer=await svc.createOffer(driver.id,delivery.id,{price:1000});await svc.acceptOffer(passenger.id,offer.id);for(const status of ['DRIVER_ARRIVED','IN_PROGRESS','COMPLETED','COMPLETED']) await svc.updateDriverRequestStatus(driver.id,delivery.id,status);
  const fees=await tx.walletTransaction.findMany({where:{intercityRequestId:delivery.id,direction:'DEBIT',wallet:{userId:driver.id}}});assert.equal(fees.length,1);assert.equal(fees[0].amount,100);
  const route=await tx.driverIntercityRoute.create({data:{driverId:driver.driverProfile.id,fromCity:data.fromCity,toCity:data.toCity,seatsTotal:4,seatsAvailable:4}});
  for(const actor of ['passenger','driver']) {
   const request=await svc.createRequest(passenger.id,{...data,requestType:'INTERCITY',fromAddressLabel:data.fromCity+', exact pickup',toAddressLabel:data.toCity+', exact destination',seats:2,paymentMethod:'BONUS'});
   assert.equal(request.fromCity,data.fromCity);assert.equal(request.toCity,data.toCity);
   offer=await svc.createOffer(driver.id,request.id,{price:1500,seats:2});await svc.acceptOffer(passenger.id,offer.id);await svc.acceptOffer(passenger.id,offer.id);
   assert.equal((await tx.driverIntercityRoute.findUnique({where:{id:route.id}})).seatsAvailable,2);assert.equal((await tx.wallet.findUnique({where:{userId:passenger.id}})).bonus,18500);
   for(let i=0;i<2;i++) if(actor==='passenger') await svc.cancelRequest(passenger.id,request.id);else await svc.updateDriverRequestStatus(driver.id,request.id,'CANCELLED');
   assert.equal((await tx.driverIntercityRoute.findUnique({where:{id:route.id}})).seatsAvailable,4);assert.equal((await tx.wallet.findUnique({where:{userId:passenger.id}})).bonus,20000);
  }
  for(const c of ['KZT','RUB']) {
   currency=c;
   const request=await svc.createRequest(passenger.id,{...data,requestType:'INTERCITY',fromAddressLabel:data.fromCity+', exact pickup',toAddressLabel:data.toCity+', exact destination',seats:2,paymentMethod:'BONUS'});
   assert.equal(request.fromCity,data.fromCity);assert.equal(request.toCity,data.toCity);
   offer=await svc.createOffer(driver.id,request.id,{price:1500,seats:2});await svc.acceptOffer(passenger.id,offer.id);
   for(const status of ['DRIVER_ARRIVED','IN_PROGRESS','COMPLETED','COMPLETED']) await svc.updateDriverRequestStatus(driver.id,request.id,status);
   const payments=await tx.walletTransaction.findMany({where:{intercityRequestId:request.id,type:'RIDE_BONUS_PAYMENT_CREDIT'}});assert.equal(payments.length,1);assert.equal(payments[0].amount,1500);assert.equal(payments[0].currency,c);
   const {DriverEarningsService}=require('../dist/src/driver/driver-earnings.service');const earnings=await new DriverEarningsService(db).summary(driver.id,undefined,c);assert.equal(Number(earnings.bonus),1500);assert.equal(Number(earnings.pendingBonus),0);
  }
  currency='KZT';
  const disabled=await svc.createRequest(passenger.id,{...data,fromAddressLabel:'Exact pickup without city',toAddressLabel:'Exact destination without city',requestType:'DELIVERY_CITY',itemDescription:'Коробка'});
  await tx.driverProfile.update({where:{id:driver.driverProfile.id},data:{acceptDelivery:false}});await assert.rejects(svc.createOffer(driver.id,disabled.id,{price:1000}));
  const city=await tx.city.create({data:{name:'Delivery '+suffix,lat:43,lng:76,countryCode:'KZ'}});
  await tx.driverProfile.update({where:{id:driver.driverProfile.id},data:{acceptDelivery:true,acceptIntercity:false}});await tx.driverOnline.create({data:{driverId:driver.driverProfile.id,isOnline:true,cityId:city.id,lastLat:43,lastLng:76}});
  const matching=await new DriverService(db,{},{},{},{},{}).getMatchingIntercityRequests(driver.id);assert(matching.some(x=>x.id===disabled.id));
  checked=true;throw done;
 },{timeout:60000}),e=>e===done);assert(checked);}finally{await p.$disconnect()}
});
