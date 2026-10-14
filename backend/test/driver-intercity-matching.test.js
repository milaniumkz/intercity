const test = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {PrismaClient} = require('@prisma/client');
const {DriverService} = require('../dist/src/driver/driver.service');
const {IntercityService} = require('../dist/src/intercity/intercity.service');
const database = process.env.DISPATCH_TEST_DATABASE_URL;
test('registered route matches distant requests and permits a real price offer, with seat and status filtering', {skip:!database}, async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/dispatch_test');
 const p=new PrismaClient({datasources:{db:{url:database}}}), key=randomUUID();
 let user,profile;const ids=[];
 try {
  user=await p.user.create({data:{phone:'test-route:'+key,password:'test',name:'Route fixture',refCode:key,refLink:'test',role:'DRIVER'}});
  profile=await p.driverProfile.create({data:{userId:user.id,status:'APPROVED',acceptIntercity:true}});
  const from='Route From '+key,to='Route To '+key;
  await p.driverIntercityRoute.create({data:{driverId:profile.id,fromCity:from,toCity:to,seatsAvailable:2,seatsTotal:2}});
  async function request(data={}) {const r=await p.intercityRequest.create({data:{passengerId:'test-passenger',fromCity:from,toCity:to,fromLat:49.96,fromLng:82.61,toLat:50.4,toLng:80.2,fromManualAddress:'Назарбаева 8/1',toAddressLabel:'Абая 10',price:7000,currency:'KZT',seats:2,date:new Date(Date.now()+86400000),...data}});ids.push(r.id);return r;}
  const wanted=await request({fromCity:from.toLowerCase()});
  await request({fromCity:to,toCity:from});await request({seats:3});await request({status:'CANCELLED'});
  // No GPS or online state: planned departures depend on registered intent.
  const driver=new DriverService(p,{}, {}, {}, {}, {});
  const matches=await driver.getMatchingIntercityRequests(user.id);
  assert.deepEqual(matches.map(r=>r.id),[wanted.id]);assert.equal(matches[0].fromManualAddress,'Назарбаева 8/1');assert.equal(matches[0].price,7000);
  assert.equal(matches[0].distanceKm,undefined);assert.equal(matches[0].myOffer,null);
  const intercity=new IntercityService(p,{});
  const offer=await intercity.createOffer(user.id,wanted.id,{price:7250,seats:2});
  assert.equal(offer.status,'PENDING');assert.equal(offer.price,7250);
  assert.equal((await driver.getMatchingIntercityRequests(user.id))[0].myOffer.id,offer.id);
  await assert.rejects(intercity.createOffer(user.id,wanted.id,{price:7300,seats:3}),/свободных мест/);
  await p.driverIntercityRoute.updateMany({where:{driverId:profile.id},data:{isActive:false}});
  assert.deepEqual(await driver.getMatchingIntercityRequests(user.id),[]);
 } finally {
  await p.intercityOffer.deleteMany({where:{requestId:{in:ids}}});await p.intercityRequest.deleteMany({where:{id:{in:ids}}});
  if(profile) {await p.driverIntercityRoute.deleteMany({where:{driverId:profile.id}});await p.driverProfile.delete({where:{id:profile.id}});}
  if(user) await p.user.delete({where:{id:user.id}});await p.$disconnect();
 }
});
