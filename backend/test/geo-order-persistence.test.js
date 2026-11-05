const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {PrismaClient}=require('@prisma/client');
const {GeoService}=require('../dist/src/geo/geo.service');
const {OrdersService}=require('../dist/src/orders/orders.service');
const database=process.env.TARIFF_TEST_DATABASE_URL;
test('road outage creates no order; recovered road geometry permits a real local database order',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/(ui_review_|dispatch_test)/);
 const p=new PrismaClient({datasources:{db:{url:database}}}),rollback=Error('rollback geo QA');
 try {
  await assert.rejects(p.$transaction(async tx=>{
   const db=new Proxy(tx,{get:(t,k)=>k==='$transaction'?fn=>fn(db):t[k]});
   const suffix=randomUUID();
   const city=await tx.city.create({data:{name:'QA map '+suffix,lat:49.95,lng:82.61,countryCode:'KZ'}});
   await tx.tariffCity.create({data:{cityId:city.id,name:'QA',basePrice:500,minPrice:500,pricePerKm:100,pricePerMin:10}});
   const user=await tx.user.create({data:{phone:'geo:'+suffix,password:'qa',name:'Local QA',refCode:suffix,refLink:'test'}});
   const geo=new GeoService(db,{get:key=>key==='OSRM_URL'?'https://router.internal':undefined});
   geo.reverseGeocode=async()=>({cityId:city.id,currency:'KZT',countryCode:'KZ'});
   let fail=true,calls=0;
   geo.fetchGeo=async()=>{calls++;return {json:async()=>fail?{code:'NoRoute',routes:[]}:{code:'Ok',routes:[{distance:8300,duration:900,geometry:{type:'LineString',coordinates:[[82.61,49.95],[82.62,49.94],[82.609,49.90]]},legs:[]}]}}};
   const orders=new OrdersService(db,geo,{assignCityOrder:async()=>null},{publish:()=>{}},{});
   const dto={mode:'CITY',requestType:'CITY_FIXED',vehicleClass:'ECONOMY',fromLat:49.95,fromLng:82.61,toLat:49.90,toLng:82.609,fromAddress:'A',toAddress:'B',paymentMethod:'CASH'};
   await assert.rejects(orders.createOrder(user.id,dto),e=>e.getStatus()===503);
   assert.equal(await tx.order.count({where:{passengerId:user.id}}),0);
   fail=false;
   const order=await orders.createOrder(user.id,dto);
   assert.equal(order.currency,'KZT');assert.equal(order.price,1500);assert.equal(calls,2);
   assert.equal(await tx.order.count({where:{id:order.id,passengerId:user.id}}),1);
   throw rollback;
  }),e=>e===rollback);
 }finally{await p.$disconnect()}
});
