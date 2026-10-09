const {test}=require('node:test');const assert=require('node:assert/strict');
const {PrismaClient}=require('@prisma/client');
const {Kassa24Gateway,confirmedPayment}=require('../dist/src/payments/kassa24-gateway');
const {CardPaymentsService}=require('../dist/src/payments/card-payments.service');
const {OrdersService}=require('../dist/src/orders/orders.service');
const {IntercityService}=require('../dist/src/intercity/intercity.service');
test('official Kassa24 contract uses unique orderId, minor units, token and acquiringId with TLS and basic auth',async()=>{
 let captured;
 const gateway=new Kassa24Gateway({baseUrl:'https://example.test',login:'test',password:'not-a-real-password',demo:false},async(url,options)=>{captured={url:String(url),options};return {ok:true,json:async()=>({id:'provider'})}});
 await gateway.create({orderId:'CITY:ride:1',amount:12500,customerData:{phone:'77000000000',cardToken:'fake-token'},acquiringId:12});
 assert.equal(captured.url,'https://example.test/payment/create');
 const body=JSON.parse(captured.options.body);assert.equal(body.orderId,'CITY:ride:1');assert.equal(body.amount,12500);assert.equal(body.customerData.cardToken,'fake-token');assert.equal(body.acquiringId,12);assert.equal(body.type,undefined);
 assert.equal(captured.options.headers.Authorization,'Basic '+Buffer.from('test:not-a-real-password').toString('base64'));
 await assert.rejects(new Kassa24Gateway({baseUrl:'http://example.test',login:'test',password:'test',demo:false}).create({}),/HTTPS/);
 assert.equal(confirmedPayment({orderId:'ride',merchantId:'test',amount:12500,demo:false},'ride',125,'test',false),true);
 for(const changed of [{orderId:'other'},{merchantId:'other'},{amount:12501},{demo:true}]) assert.equal(confirmedPayment({orderId:'ride',merchantId:'test',amount:12500,demo:false,...changed},'ride',125,'test',false),false);
});
const database=process.env.DAILY_BONUS_TEST_DATABASE_URL;
test('start schedules charge, ambiguous result reuses transaction, three confirmed failures switch to cash, and earnings settle once',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/intercity_activity');
 const p=new PrismaClient({datasources:{db:{url:database}}});
 const saved={};for(const [key,value] of Object.entries({KASSA24_LOGIN:'test',KASSA24_PASSWORD:'not-a-real-password',JWT_SECRET:'test-only-secret-'.repeat(4),KASSA24_DEMO:'false',BACKEND_PUBLIC_URL:'https://api.example.test/api'})){saved[key]=process.env[key];process.env[key]=value;}
 try {
 const suffix=Date.now().toString();
 const passenger=await p.user.create({data:{phone:'7708'+suffix.slice(-7),name:'Card test',password:'test-only',refCode:'cardp'+suffix,refLink:'test'}});
 const driver=await p.user.create({data:{phone:'7705'+suffix.slice(-7),name:'Driver test',password:'test-only',refCode:'cardd'+suffix,refLink:'test',wallet:{create:{}}}});
 const profile=await p.driverProfile.create({data:{userId:driver.id,status:'APPROVED'}});
 await p.appSettings.upsert({where:{key:'kassa24SavedCardsEnabled'},create:{key:'kassa24SavedCardsEnabled',value:'true'},update:{value:'true'}});
 await p.appSettings.upsert({where:{key:'kassa24AcquiringId'},create:{key:'kassa24AcquiringId',value:'12'},update:{value:'12'}});
 const events=[],pushes=[];
 const payments=new CardPaymentsService(p,{publish:event=>events.push(event)},{sendToUser:async(user,payload)=>pushes.push({user,payload})});
 const card=await p.savedPaymentCard.create({data:{userId:passenger.id,phone:passenger.phone,tokenEncrypted:payments.encrypt('fake-card-token'),tokenHash:suffix,last4:'0123',acquiringId:12,demo:false,isDefault:true}});
 assert.equal(payments.decrypt(card.tokenEncrypted),'fake-card-token');
 assert.notEqual(card.tokenEncrypted,'fake-card-token');
 const publicCards=await payments.listCards(passenger.id);assert.deepEqual(Object.keys(publicCards.cards[0]).sort(),['id','isDefault','last4']);
 assert.equal(await payments.cardForOrder(passenger.id,'KZT'),card.id);
 await assert.rejects(payments.cardForOrder(passenger.id,'RUB'),/рублях/);
 await assert.rejects(payments.selectCard(driver.id,card.id),/не найдена/);
 const orders=new OrdersService(p,{}, {},{publish(){}},{sendOrderStatusToPassenger:async()=>{},sendToUser:async()=>{}},payments);
 const make=()=>p.order.create({data:{passengerId:passenger.id,driverId:profile.id,status:'DRIVER_ARRIVED',mode:'CITY',requestType:'CITY_FIXED',currency:'KZT',price:1000,commissionAmount:100,fromLat:50,fromLng:80,toLat:50.01,toLng:80,fromAddress:'A',toAddress:'B',paymentMethod:'CARD',paymentCardId:card.id}});
 const ride=await make();await orders.updateOrderStatus(ride.id,'IN_PROGRESS',{userId:driver.id,role:'DRIVER'});
 const paymentId='CITY:'+ride.id;assert.equal((await p.tripCardPayment.findUnique({where:{id:paymentId}})).status,'PENDING');
 const statuses=new Map();let creates=0;
 payments.gateway.status=async id=>statuses.get(id) ?? {notFound:true};
 payments.gateway.create=async body=>{creates++;statuses.set(body.orderId,{orderId:body.orderId,merchantId:'test',amount:100000,demo:false,status:1,id:'provider-success'});throw new Error('Simulated connection loss after bank accepted payment');};
 await Promise.all([payments.processPayment(paymentId),payments.processPayment(paymentId)]);
 assert.equal(creates,1);assert.equal((await p.tripCardPayment.findUnique({where:{id:paymentId}})).status,'CHECKING');
 await payments.processPayment(paymentId);assert.equal(creates,1);assert.equal((await p.tripCardPayment.findUnique({where:{id:paymentId}})).status,'PAID');
 await orders.updateOrderStatus(ride.id,'COMPLETED',{userId:driver.id,role:'DRIVER'});
 await Promise.all([payments.processPayment(paymentId),payments.processPayment(paymentId)]);
 await payments.processPayment(paymentId);
 assert.equal(await p.walletTransaction.count({where:{idempotencyKey:'card-earnings:'+paymentId}}),1);
 assert.equal((await p.wallet.findUnique({where:{userId:driver.id}})).money,900);
 const declined=await make();await orders.updateOrderStatus(declined.id,'IN_PROGRESS',{userId:driver.id,role:'DRIVER'});
 const failedId='CITY:'+declined.id;let failedCreates=0;
 payments.gateway.create=async body=>{failedCreates++;statuses.set(body.orderId,{orderId:body.orderId,merchantId:'test',amount:100000,demo:false,status:0,id:'failed-'+failedCreates});return{id:'failed-'+failedCreates}};
 for(let i=0;i<3;i++)await payments.processPayment(failedId);
 assert.equal(failedCreates,3);assert.equal((await p.order.findUnique({where:{id:declined.id}})).paymentMethod,'CASH');assert.equal((await p.tripCardPayment.findUnique({where:{id:failedId}})).status,'CASH');
 await payments.processPayment(failedId);assert.equal(failedCreates,3);assert.equal(pushes.length,2);assert.ok(events.some(e=>e.type==='driver.payment.changed'&&e.payload.paymentStatus==='CASH'));
 // Intercity charge uses the accepted offer, not the passenger's initial proposed fare.
 const intercity=new IntercityService(p,{},payments);
 const request=await p.intercityRequest.create({data:{passengerId:passenger.id,fromCity:'A',toCity:'B',date:new Date(),price:500,currency:'KZT',status:'DRIVER_ARRIVED',selectedDriverId:driver.id,paymentMethod:'CARD',paymentCardId:card.id}});
 const offer=await p.intercityOffer.create({data:{requestId:request.id,driverId:driver.id,price:1200,seats:1,status:'ACCEPTED'}});
 await p.intercityRequest.update({where:{id:request.id},data:{selectedOfferId:offer.id}});
 await intercity.updateDriverRequestStatus(driver.id,request.id,'IN_PROGRESS');
 assert.equal((await p.tripCardPayment.findUnique({where:{id:'INTERCITY:'+request.id}})).amount,1200);
 await intercity.cancelRequest(passenger.id,request.id);
 await payments.processPayment('INTERCITY:'+request.id);
 assert.equal((await p.tripCardPayment.findUnique({where:{id:'INTERCITY:'+request.id}})).status,'CANCELLED');
 // A stale cancellation read must not overwrite a completion committed by another request.
 await p.intercityRequest.update({where:{id:request.id},data:{status:'COMPLETED'}});
 const owned=intercity.requireOwnedRequest.bind(intercity);
 intercity.requireOwnedRequest=async()=>({...request,status:'IN_PROGRESS'});
 await assert.rejects(intercity.cancelRequest(passenger.id,request.id),/нельзя отменить/);
 assert.equal((await p.intercityRequest.findUnique({where:{id:request.id}})).status,'COMPLETED');
 intercity.requireOwnedRequest=owned;

 // Cancellation after payment refunds once and never credits driver earnings.
 const cancelled=await make();await orders.updateOrderStatus(cancelled.id,'IN_PROGRESS',{userId:driver.id,role:'DRIVER'});
 const cancelledId='CITY:'+cancelled.id;
 payments.gateway.create=async body=>{statuses.set(body.orderId,{orderId:body.orderId,merchantId:'test',amount:100000,demo:false,status:1,id:'refund-test'});return{id:'refund-test'}};
 await payments.processPayment(cancelledId);
 await p.order.update({where:{id:cancelled.id},data:{status:'CANCELLED'}});
 let refunds=0;payments.gateway.cancel=async id=>{refunds++;statuses.set(id,{...statuses.get(id),status:3});return{}};
 await payments.processPayment(cancelledId);await payments.processPayment(cancelledId);
 assert.equal(refunds,1);assert.equal((await p.tripCardPayment.findUnique({where:{id:cancelledId}})).status,'REFUNDED');
 assert.equal(await p.walletTransaction.count({where:{idempotencyKey:'card-earnings:'+cancelledId}}),0);
 // A forged callback cannot introduce a card or acknowledge a payment.
 await payments.callback('CITY:unknown:1');assert.equal(await p.savedPaymentCard.count({where:{userId:passenger.id}}),1);
 // Hosted binding, authenticated token sync, and storing only last four digits of the PAN.
 payments.gateway.create=async body=>{assert.equal(body.tokenization,true);assert.equal(body.amount,undefined);assert.equal(body.customerData.phone,passenger.phone);return{id:'binding-test',url:'https://ecommerce.pult24.kz/hosted'}};
 const binding=await payments.bind(passenger.id);assert.match(binding.url,/^https:/);
 payments.gateway.tokens=async phone=>{assert.equal(phone,passenger.phone);return[{ID:'new-fake-token-'+suffix,Pan:'4111111111111111'}]};
 await payments.callback('bind:'+binding.bindingId);
 const synced=await payments.listCards(passenger.id);assert.equal(synced.cards.length,1);assert.equal(synced.cards[0].last4,'1111');
 const stored=await p.savedPaymentCard.findUnique({where:{id:synced.cards[0].id}});assert.equal(stored.phone,passenger.phone);assert.equal(JSON.stringify(stored).includes('4111111111111111'),false);
 assert.equal(payments.decrypt(stored.tokenEncrypted),'new-fake-token-'+suffix);
 payments.gateway.remove=async token=>{assert.equal(token,'new-fake-token-'+suffix);return{removed:true}};
 await payments.removeCard(passenger.id,stored.id);assert.equal((await payments.listCards(passenger.id)).cards.length,0);

 }finally{await p.$disconnect();for(const [key,value]of Object.entries(saved)){if(value===undefined)delete process.env[key];else process.env[key]=value;}}
});
