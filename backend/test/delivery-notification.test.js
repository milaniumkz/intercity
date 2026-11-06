const {test}=require('node:test'),assert=require('node:assert/strict');
const {deliveryDriverEligible,notifyDeliveryDrivers}=require('../dist/src/common/delivery-notification');
const profile={id:'profile',userId:'driver',status:'ACTIVE',acceptDelivery:true,online:{isOnline:true,lastLat:49.95,lastLng:82.61,city:{name:'Усть-Каменогорск'}}};
const request={id:'delivery',passengerId:'passenger',requestType:'DELIVERY_CITY',fromCity:'Усть-Каменогорск',toCity:'Усть-Каменогорск',fromLat:49.96,fromLng:82.62,date:new Date(Date.now()+172800000)};
test('future local deliveries reach enabled nearby drivers without an intercity route',()=>{
 assert.equal(deliveryDriverEligible(profile,request),true);
 for(const changed of [{acceptDelivery:false},{status:'PENDING'},{userId:'passenger'},{serviceStats:{activityScore:0}},{online:{isOnline:false}},{online:{isOnline:true,lastLat:50.4,lastLng:80.2,city:{name:'Семей'}}}])assert.equal(deliveryDriverEligible({...profile,...changed},request),false);
 assert.equal(deliveryDriverEligible(profile,{...request,fromLat:null,fromLng:null}),true);
 assert.equal(deliveryDriverEligible(profile,{...request,fromLat:null,fromLng:null,fromCity:'Семей'}),false);
});
test('intercity delivery notification respects chosen route and departure day',()=>{
 const departure=new Date(Date.now()+172800000);departure.setUTCHours(23,0,0,0);
 const driver={...profile,intercityRoutes:[{isActive:true,seatsAvailable:1,fromCity:'Усть-Каменогорск',toCity:'Риддер',departureAt:departure,departureOffsetMinutes:0}]};
 const trip={...request,requestType:'DELIVERY_INTERCITY',toCity:'Риддер',date:departure};
 assert.equal(deliveryDriverEligible(driver,trip),true);
 assert.equal(deliveryDriverEligible(driver,{...trip,date:new Date(departure.getTime()+86400000)}),false);
 assert.equal(deliveryDriverEligible(driver,{...trip,toCity:'Семей'}),false);
});
test('delivery creation sends a push only to eligible drivers, with the available requests link',async()=>{
 const sent=[];let queries=0;
 const prisma={driverProfile:{findMany:async()=>{queries++;return[profile,{...profile,userId:'disabled',acceptDelivery:false}]}},$transaction:async()=>null};
 await notifyDeliveryDrivers(prisma,{sendToUser:async(...args)=>sent.push(args)},request);
 assert.equal(sent.length,1);assert.equal(sent[0][0],'driver');assert.equal(sent[0][1].data.type,'delivery_available');assert.equal(sent[0][1].data.route,'/driver/trip-create');
 await notifyDeliveryDrivers(prisma,{sendToUser:async()=>assert.fail('not a delivery')},{...request,requestType:'INTERCITY'});assert.equal(queries,1);
});
