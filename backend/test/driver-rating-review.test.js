const {test}=require('node:test');const assert=require('node:assert/strict');const {PrismaClient}=require('@prisma/client');
const {OrdersService}=require('../dist/src/orders/orders.service');const {AdminService}=require('../dist/src/admin/admin.service');
const {ratingReviewHint,validateReviewDecision}=require('../dist/src/common/driver-rating-review');
test('rating automation separates platform issues for review without silently deciding truth',()=>{
 assert.equal(ratingReviewHint('Не работает промокод приложения').recommendation,'CHECK_PLATFORM_ISSUE');
 assert.equal(ratingReviewHint('Водитель ехал опасно').recommendation,'CHECK_TRIP_FACTS');
 assert.throws(()=>validateReviewDecision({ratingDecision:'CHANGE',rating:5.1,resolutionNote:'Проверено'}));
});
const database=process.env.DAILY_BONUS_TEST_DATABASE_URL;
test('bad rating needs explanation, stays pending, and admin decisions revise the average exactly once',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/intercity_activity');
 const p=new PrismaClient({datasources:{db:{url:database}}});const prefix='review-'+Date.now();const events=[];const realtime={publish:e=>events.push(e)};
 try{
 const user=await p.user.create({data:{phone:prefix,password:'test-only',name:'Test',refCode:prefix,refLink:'test-only'}});
 const d=await p.driverProfile.create({data:{userId:user.id,status:'APPROVED'}});
 const create=()=>p.order.create({data:{passengerId:user.id,driverId:d.id,status:'COMPLETED',completedAt:new Date(),fromLat:1,fromLng:1,toLat:2,toLng:2,fromAddress:'Test',toAddress:'Test'}});
 const api=new OrdersService(p,null,null,realtime,null);const admin=new AdminService(p,realtime,null);
 const good=await create();await api.rateOrder(good.id,user.id,5,false);
 const bad=await create();await assert.rejects(api.rateOrder(bad.id,user.id,1,false),/опишите/);
 assert.equal((await p.order.findUnique({where:{id:bad.id}})).driverRating,null);
 const results=await Promise.allSettled([api.rateOrder(bad.id,user.id,1,false,'Водитель ехал опасно и нарушал правила'),api.rateOrder(bad.id,user.id,1,false,'Водитель ехал опасно и нарушал правила')]);assert.equal(results.filter(e=>e.status==='fulfilled').length,1);
 const c=await p.complaint.findFirst({where:{orderId:bad.id}});assert.equal(c.status,'NEW');
 let rating=await p.driverRating.findUnique({where:{driverId:d.id}});assert.equal(rating.ratingAvg,5);assert.equal(rating.ratingCount,1);
 await admin.updateComplaint(c.id,{ratingDecision:'APPROVE',resolutionNote:'Нарушение подтверждено'});
 rating=await p.driverRating.findUnique({where:{driverId:d.id}});assert.equal(rating.ratingAvg,3);assert.equal(rating.ratingCount,2);
 await admin.updateComplaint(c.id,{ratingDecision:'APPROVE',resolutionNote:'Повторная проверка подтверждает'});
 assert.equal((await p.driverRating.findUnique({where:{driverId:d.id}})).ratingCount,2);
 await admin.updateComplaint(c.id,{ratingDecision:'CHANGE',rating:3,resolutionNote:'Уточнили обстоятельства'});
 assert.equal((await p.driverRating.findUnique({where:{driverId:d.id}})).ratingAvg,4);
 await admin.updateComplaint(c.id,{ratingDecision:'REJECT',resolutionNote:'Нарушение не подтверждено'});
 rating=await p.driverRating.findUnique({where:{driverId:d.id}});assert.equal(rating.ratingAvg,5);assert.equal(rating.ratingCount,1);
 assert.equal((await p.order.findUnique({where:{id:bad.id}})).driverRatingStatus,'REJECTED');
 assert.equal((await p.complaint.findUnique({where:{id:c.id}})).status,'RESOLVED');
 await assert.rejects(api.rateOrder(bad.id,user.id,2,false,'Повторная оценка запрещена'),/already submitted/);
 assert.ok(events.filter(e=>e.type==='driver.rating.updated').length>=4);
 }finally{await p.$disconnect()}
});
