const {test}=require('node:test');const assert=require('node:assert/strict');
const {PrismaClient}=require('@prisma/client');
const {serviceDay,parseDailyBonus,creditDriverDailyBonus}=require('../dist/src/common/driver-daily-bonus');
test('service day changes at Kazakhstan midnight and campaign settings are strictly validated',()=>{
 assert.equal(serviceDay(new Date('2026-10-09T18:59:59Z')).day,'2026-10-09');
 assert.equal(serviceDay(new Date('2026-10-09T19:00:00Z')).day,'2026-10-10');
 for(const value of ['null','{}','{"enabled":true,"targetOrders":0,"rewardAmount":10}','{"enabled":true,"targetOrders":2,"rewardAmount":0}'])assert.throws(()=>parseDailyBonus(value));
});
const database=process.env.DAILY_BONUS_TEST_DATABASE_URL;
test('daily reward credits the main wallet exactly once under concurrency and separates currencies',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/intercity_activity');
 const p=new PrismaClient({datasources:{db:{url:database}}});const prefix='daily-'+Date.now();const now=new Date();
 try{
 const u=await p.user.create({data:{phone:prefix,password:'test-only',name:'Test',refCode:prefix,refLink:'test-only',wallet:{create:{money:0,moneyRub:0,bonus:20}}}});
 const d=await p.driverProfile.create({data:{userId:u.id,status:'APPROVED'}});
 const complete=currency=>p.order.create({data:{passengerId:u.id,driverId:d.id,status:'COMPLETED',completedAt:now,currency,fromLat:1,fromLng:1,toLat:2,toLng:2,fromAddress:'Test',toAddress:'Test'}});
 for(const currency of ['KZT','RUB'])await p.appSettings.upsert({where:{key:'driverDailyBonus'+currency},create:{key:'driverDailyBonus'+currency,value:JSON.stringify({enabled:true,targetOrders:2,rewardAmount:currency==='KZT'?1000:100})},update:{value:JSON.stringify({enabled:true,targetOrders:2,rewardAmount:currency==='KZT'?1000:100})}});
 await complete('KZT');assert.equal(await p.$transaction(tx=>creditDriverDailyBonus(tx,d.id,u.id,'KZT',now)),null);
 await complete('KZT');
 await Promise.all(Array.from({length:5},()=>p.$transaction(tx=>creditDriverDailyBonus(tx,d.id,u.id,'KZT',now))));
 let w=await p.wallet.findUnique({where:{userId:u.id}});assert.equal(w.money,1000);assert.equal(w.moneyRub,0);assert.equal(w.bonus,20);
 assert.equal(await p.walletTransaction.count({where:{walletId:w.id,type:'DRIVER_DAILY_BONUS'}}),1);
 await complete('RUB');await complete('RUB');await p.$transaction(tx=>creditDriverDailyBonus(tx,d.id,u.id,'RUB',now));
 w=await p.wallet.findUnique({where:{userId:u.id}});assert.equal(w.moneyRub,100);assert.equal(w.money,1000);
 await p.appSettings.update({where:{key:'driverDailyBonusKZT'},data:{value:JSON.stringify({enabled:false,targetOrders:1,rewardAmount:1000})}});
 assert.equal(await p.$transaction(tx=>creditDriverDailyBonus(tx,d.id,u.id,'KZT',new Date(now.getTime()+86400000))),null);
 }finally{await p.$disconnect()}
});
