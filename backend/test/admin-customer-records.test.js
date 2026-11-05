const {test}=require('node:test'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {PrismaClient}=require('@prisma/client');
const {listCustomers,customerOverview,customerTrips,customerTransactions,customerEdit,editDriverRecord}=require('../dist/src/admin/customer-records');
const {AdminPeopleController}=require('../dist/src/admin/admin-people.controller');
const database=process.env.DISPATCH_TEST_DATABASE_URL;
test('customer directory, both trip stores, protected edits and driver settings against PostgreSQL',{skip:!database},async t=>{
 const parsed=new URL(database);assert.equal(parsed.hostname,'127.0.0.1');assert.equal(parsed.pathname,'/dispatch_test');const db=new PrismaClient({datasources:{db:{url:database}}});const users=[],orders=[],markets=[];let driver;
 try{
  for(const [name,role]of [['Пассажир','PASSENGER'],['Олег','PASSENGER'],['Владелец','ADMIN']])users.push(await db.user.create({data:{name:name+' '+crypto.randomUUID().slice(0,8),role,phone:'+77'+crypto.randomInt(1e8,1e9).toString(),password:'not-a-real-hash',refCode:crypto.randomUUID(),refLink:''}}));
  const [passenger,driverUser,admin]=users;
  driver=await db.driverProfile.create({data:{userId:driverUser.id,status:'ACTIVE',carModel:'ГАЗ Газель',carNumber:'A123BC77'}});
  const cityOrder=await db.order.create({data:{passengerId:passenger.id,driverId:driver.id,mode:'CITY',requestType:'CITY_FIXED',status:'COMPLETED',fromLat:50,fromLng:82,toLat:51,toLng:83,fromAddress:'Дом',toAddress:'Вокзал',price:500,currency:'KZT',completedAt:new Date()}});orders.push(cityOrder.id);
  const market=await db.intercityRequest.create({data:{passengerId:passenger.id,selectedDriverId:driverUser.id,fromCity:'Риддер',toCity:'Усть-Каменогорск',price:3000,date:new Date(),status:'ACCEPTED'}});markets.push(market.id);
  const offer=await db.intercityOffer.create({data:{requestId:market.id,driverId:driverUser.id,price:4000,seats:1,status:'ACCEPTED'}});await db.intercityRequest.update({where:{id:market.id},data:{selectedOfferId:offer.id}});
  const wallet=await db.wallet.create({data:{userId:passenger.id}});await db.walletTransaction.create({data:{walletId:wallet.id,type:'REFERRAL_ORDER_BONUS',direction:'CREDIT',balanceSource:'BONUS',amount:100}});
  await t.test('all drivers are searchable by name, phone and car, including passenger-role profiles',async()=>{
   const listed=await listCustomers(db,{kind:'driver',search:driverUser.name});assert.equal(listed.total,1);assert.equal(listed.items[0].id,driverUser.id);
   assert.equal((await listCustomers(db,{kind:'passenger',search:driverUser.name})).total,0);
   assert.equal((await listCustomers(db,{kind:'driver',search:'Газель'})).items.some(x=>x.id===driverUser.id),true);
   const serialized=JSON.stringify(listed);for(const key of ['password','pushToken','secretHash','template'])assert(!serialized.includes('"'+key+'"'));
  });
  await t.test('history combines city and market orders at accepted price for passenger and driver',async()=>{
   const result=await customerTrips(db,{userId:passenger.id});assert.equal(result.total,2);assert.equal(result.items.find(x=>x.id===market.id).price,4000);
   assert.equal((await customerTrips(db,{userId:driverUser.id})).total,2);
   assert.equal((await customerTrips(db,{userId:passenger.id,status:'COMPLETED'})).total,1);
   assert.equal((await customerTrips(db,{userId:passenger.id,status:'ACTIVE'})).items[0].id,market.id);
   assert.equal((await customerTrips(db,{userId:passenger.id,take:1,skip:1})).items.length,1);
  });
  await t.test('financial information is permission-scoped and customer transactions stay isolated',async()=>{
   assert.equal((await customerOverview(db,passenger.id,false)).wallet,null);
   assert((await customerOverview(db,passenger.id,true)).wallet);
   assert.equal((await customerTransactions(db,passenger.id,{})).total,1);
   assert.equal((await customerTransactions(db,driverUser.id,{})).total,0);
  });
  const adminApi={adminHasPermission:async(id,key)=>id===admin.id,logAdminAction:async()=>{}};
  const controller=new AdminPeopleController(db,adminApi,{cancelRequest:async()=>{throw Error('unexpected')}},{cancelOrder:async()=>{throw Error('unexpected')}});
  await t.test('only whitelisted fields can change; ordinary callers and admin targets are protected',async()=>{
   await assert.rejects(controller.edit({user:{sub:passenger.id}},driverUser.id,{fields:{name:'Другой'},reason:'Тест прав'}),/Нет доступа/);
   for(const key of ['password','role','authVersion','pushToken'])assert.throws(()=>customerEdit({fields:{[key]:'ADMIN'},reason:'Проверка поля'}),/нельзя изменять/);
   await assert.rejects(controller.edit({user:{sub:admin.id}},admin.id,{fields:{name:'Другое имя'},reason:'Проверка защиты'}),/администраторов/);
   await controller.edit({user:{sub:admin.id}},passenger.id,{fields:{name:'Новое имя',phone:passenger.phone},reason:'Исправление имени'});
   assert.equal((await db.user.findUnique({where:{id:passenger.id}})).authVersion,0);
   assert.equal(await db.adminAuditLog.count({where:{adminId:admin.id,targetId:passenger.id,action:'user.profile.update'}}),1);
  });
  await t.test('blocking revokes sessions and records the reason without deleting history',async()=>{
   await db.refreshToken.create({data:{userId:passenger.id,token:crypto.randomUUID(),expiresAt:new Date(Date.now()+86400000)}});
   await controller.edit({user:{sub:admin.id}},passenger.id,{fields:{blocked:true},reason:'Проверка блокировки'});
   const user=await db.user.findUnique({where:{id:passenger.id}});assert(user.blockedAt);assert.equal(user.authVersion,1);assert.equal(await db.refreshToken.count({where:{userId:passenger.id}}),0);
   assert.equal((await customerTrips(db,{userId:passenger.id})).total,2);
   await controller.edit({user:{sub:admin.id}},passenger.id,{fields:{blocked:false},reason:'Проверка разблокировки'});
  });
  await t.test('driver modes save without resetting approval, car changes are blocked during trips',async()=>{
   const result=await db.$transaction(tx=>editDriverRecord(tx,driverUser.id,{fields:{acceptDelivery:false,acceptCargo:true},reason:'Настройки заказов'}));assert.equal(result.profile.status,'ACTIVE');assert.equal(result.profile.acceptDelivery,false);
   await assert.rejects(db.$transaction(tx=>editDriverRecord(tx,driverUser.id,{fields:{carNumber:'B777BB77'},reason:'Замена автомобиля'})),/активной поездки/);
   await db.intercityRequest.update({where:{id:market.id},data:{status:'CANCELLED'}});
   const changed=await db.$transaction(tx=>editDriverRecord(tx,driverUser.id,{fields:{carNumber:'B777BB77'},reason:'Замена автомобиля'}));assert.equal(changed.profile.status,'PENDING');
  });
 }finally{
  await db.adminAuditLog.deleteMany({where:{adminId:{in:users.map(u=>u.id)}}});await db.intercityOffer.deleteMany({where:{requestId:{in:markets}}});await db.intercityRequest.deleteMany({where:{id:{in:markets}}});await db.order.deleteMany({where:{id:{in:orders}}});
  await db.walletTransaction.deleteMany({where:{wallet:{userId:{in:users.map(u=>u.id)}}}});await db.wallet.deleteMany({where:{userId:{in:users.map(u=>u.id)}}});await db.refreshToken.deleteMany({where:{userId:{in:users.map(u=>u.id)}}});if(driver)await db.driverProfile.deleteMany({where:{id:driver.id}});await db.user.deleteMany({where:{id:{in:users.map(u=>u.id)}}});await db.$disconnect();
 }
});
