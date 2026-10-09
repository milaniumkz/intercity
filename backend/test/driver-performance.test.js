const {test}=require('node:test');const assert=require('node:assert/strict');
const {driverPriority,driverPerformance}=require('../dist/src/common/driver-performance');
const now=new Date('2026-10-09T12:00:00Z');
test('priority breakdown equals the actual dispatch bonus and expiry removes only the expired bonus',()=>{
 const d={priorityFlags:{hasCheckers:true,hasBranding:true},rating:{ratingAvg:4.95},serviceStats:{serviceStartAt:new Date('2026-10-06T11:00:00Z')},fuelBonus:{bonusActiveUntil:new Date('2026-10-09T12:01:00Z')}};
 assert.equal(driverPriority(d,now).total,33);
 d.rating.ratingAvg=4.9;d.fuelBonus.bonusActiveUntil=now;
 assert.equal(driverPriority(d,now).total,21);
 assert.equal(driverPriority({serviceStats:{serviceStartAt:new Date('2026-10-10')}},now).total,0);
});
test('activity distinguishes healthy, warning, low and blocked and reflects expiry recovery',()=>{
 for(const [score,level]of [[100,'green'],[70,'green'],[69,'yellow'],[30,'yellow'],[29,'red'],[1,'red'],[0,'blocked']])assert.equal(driverPerformance({serviceStats:{activityScore:score}},now).activity.level,level);
 const d={serviceStats:{activityScore:0,activityBlockedUntil:new Date('2026-10-09T12:01:00Z')}};
 assert.equal(driverPerformance(d,now).activity.blocked,true);
 d.serviceStats.activityBlockedUntil=now;
 const a=driverPerformance(d,now).activity;assert.equal(a.score,30);assert.equal(a.level,'yellow');assert.equal(a.blocked,false);
 assert.equal(d.serviceStats.activityScore,0);
});

test('the dashboard priority equals the score used to dispatch a real driver',async()=>{
 const {AutoDispatchService}=require('../dist/src/orders/auto-dispatch.service');
 const driver={priorityFlags:{hasCheckers:true,hasBranding:true},rating:{ratingAvg:4.95},serviceStats:{activityScore:100,serviceStartAt:new Date(Date.now()-3*86400000-60000)},fuelBonus:{bonusActiveUntil:new Date(Date.now()+60000)}};
 const service=new AutoDispatchService({}, {}, {});
 const score=await service.computeScore({driverId:'test',distanceFromPassenger:0,driver},0,0);
 assert.equal(score.priorityScore,driverPerformance(driver).priority.total);
});

test('own profile exposes performance alongside the existing completed-trip counters',async()=>{
 const {DriverService}=require('../dist/src/driver/driver.service');
 const profile={id:'driver',rating:{ratingAvg:4.8,ratingCount:12},priorityFlags:{hasCheckers:true},serviceStats:{activityScore:97}};
 const prisma={driverProfile:{findUnique:async()=>profile},order:{count:async()=>3},intercityRequest:{count:async()=>1}};
 const result=await new DriverService(prisma,{}, {}, {}, {}).getMyProfile('user');
 assert.equal(result.performance.activity.score,97);assert.equal(result.performance.rating.average,4.8);
 assert.equal(result.performance.priority.total,5);assert.equal(result.todayCompletedOrders,4);assert.equal(result.completedTrips,4);
});
