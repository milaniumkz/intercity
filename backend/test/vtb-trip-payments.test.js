const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {PrismaClient}=require('@prisma/client');
const {VtbTripPaymentsService,vtbTripBankState}=require('../dist/src/payments/vtb-trip-payments.service');
const {VtbSandboxGateway}=require('../dist/src/payments/vtb-sandbox-gateway');
const {CardPaymentsService}=require('../dist/src/payments/card-payments.service');
const {OrdersService}=require('../dist/src/orders/orders.service');
const {IntercityService}=require('../dist/src/intercity/intercity.service');
const {DriverService}=require('../dist/src/driver/driver.service');
test('trip verification rejects mismatches, partial refunds and held funds',()=>{
 const expected={orderNumber:'one',amount:70000,currency:'398',orderStatus:2,actionCode:0};
 assert.equal(vtbTripBankState(expected,'one',70000),'PAID');
 for(const changed of [{orderNumber:'other'},{amount:69999},{currency:643},{actionCode:5},{orderStatus:1},{orderStatus:4,paymentAmountInfo:{refundedAmount:1}}])assert.notEqual(vtbTripBankState({...expected,...changed},'one',70000),'PAID');
 assert.equal(vtbTripBankState({...expected,orderStatus:4,paymentAmountInfo:{refundedAmount:70000}},'one',70000),'REFUNDED');
});
test('binding and refund requests use bank tokens, client ownership, KZT and a stable refund ID',async()=>{
 const requests=[];const g=new VtbSandboxGateway({userName:'qa',password:'test-only'},async(url,opt)=>{requests.push({url:String(url),body:new URLSearchParams(opt.body)});return{ok:true,json:async()=>String(url).endsWith('register.do')?{errorCode:0,orderId:randomUUID(),formUrl:'https://vtbkz.rbsuat.com/payment/merchants/intercity/payment_ru.html'}:{errorCode:0}}});
 await g.register({orderNumber:randomUUID(),amountMinor:100,clientId:'owner',bindingId:'protected-bank-binding',returnUrl:'https://app.example.test/return'});
 assert.equal(requests[0].body.get('currency'),'398');assert.equal(requests[0].body.get('bindingId'),'protected-bank-binding');assert.equal(requests[0].body.get('clientId'),'owner');
 const id=randomUUID();await g.refund(randomUUID(),100,id);assert.equal(requests[1].body.get('externalRefundId'),id);assert.equal(requests[1].body.get('amount'),'100');
 assert.equal(requests[1].body.has('cvc'),false);
});
const database=process.env.VTB_SANDBOX_TEST_DATABASE_URL;
test('VTB trip payments: real database atomic net earnings, 20 repeats, cancellation, binding refund, CVC fallback and isolation',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/vtb_sandbox_test');
 const db=new PrismaClient({datasources:{db:{url:database}}}),users=[],cityIds=[],orderIds=[],requestIds=[];
 const saved={};for(const [key,value]of Object.entries({VTB_SANDBOX_ENABLED:'true',VTB_SANDBOX_USER_NAME:'qa-api',VTB_SANDBOX_PASSWORD:'test-only',JWT_SECRET:'vtb-trip-test-only-secret-'.repeat(4)})){saved[key]=process.env[key];process.env[key]=value;}
 const events=[], realtime={publish:e=>events.push(e)},push={sendToUser:async()=>{},sendOrderStatusToPassenger:async()=>{},sendIntercityStatusToPassenger:async()=>false};
 const vtb=new VtbTripPaymentsService(db,realtime),payments=new CardPaymentsService(db,realtime,push,vtb),orders=new OrdersService(db,{}, {},realtime,push,payments),intercity=new IntercityService(db,{},payments,realtime,push);
 const bank=new Map(),byNumber=new Map(),refunds=new Set(),registerCalls=[],bindings=[],charges=[];
 let payAutomatically=false;
 vtb.gateway.register=async input=>{
  registerCalls.push(input);
  if(byNumber.has(input.orderNumber))return byNumber.get(input.orderNumber);
  const orderId=randomUUID(),result={orderId,paymentUrl:'https://vtbkz.rbsuat.com/payment/merchants/intercity/payment_ru.html?mdOrder='+orderId};
  byNumber.set(input.orderNumber,result);bank.set(orderId,{orderNumber:input.orderNumber,amount:input.amountMinor,currency:398,orderStatus:0,actionCode:0,attributes:[{name:'mdOrder',value:orderId}]});return result;
 };
 vtb.gateway.status=async id=>structuredClone(bank.get(id));
 vtb.gateway.statusByOrderNumber=async number=>{const item=byNumber.get(number);if(!item){const {VtbSandboxApiError}=require('../dist/src/payments/vtb-sandbox-gateway');throw new VtbSandboxApiError('6');}return structuredClone(bank.get(item.orderId));};
 vtb.gateway.bindings=async clientId=>({bindings:bindings.filter(b=>b.clientId===clientId)});
 vtb.gateway.unbind=async id=>{const i=bindings.findIndex(b=>b.bindingId===id);if(i>=0)bindings.splice(i,1);return{errorCode:0};};
 vtb.gateway.payBinding=async(id,token)=>{charges.push({id,token});if(payAutomatically)bank.get(id).orderStatus=2;else throw Error('CVC required');};
 vtb.gateway.refund=async(id,amount,key)=>{const b=bank.get(id);assert.equal(b.amount,amount);refunds.add(key);b.orderStatus=4;b.paymentAmountInfo={refundedAmount:amount};return{errorCode:0};};
 vtb.gateway.decline=async id=>{bank.get(id).orderStatus=6;return{errorCode:0};};
 vtb.gateway.reverse=async id=>{bank.get(id).orderStatus=3;return{errorCode:0};};
 try{
 const city=await db.city.create({data:{name:'VTB trip isolated QA '+randomUUID(),countryCode:'RU',lat:56.8,lng:60.6}});cityIds.push(city.id);
 async function user(role){const id=randomUUID();const u=await db.user.create({data:{phone:'qa:'+id,name:'VTB QA',password:'test-only',role,cityId:city.id,refCode:id,refLink:'',wallet:{create:{}}}});users.push(u.id);return u;}
 const passenger=await user('PASSENGER'),driver=await user('DRIVER'),other=await user('PASSENGER');
 const profile=await db.driverProfile.create({data:{userId:driver.id,status:'APPROVED'}});
 const make=async(cardId=null)=>{const o=await db.order.create({data:{passengerId:passenger.id,driverId:profile.id,status:'DRIVER_ARRIVED',mode:'CITY',requestType:'CITY_FIXED',currency:'RUB',price:100,commissionAmount:10,fromLat:56.8,fromLng:60.6,toLat:56.81,toLng:60.61,fromAddress:'QA A',toAddress:'QA B',paymentMethod:'CARD',paymentCardId:cardId}});orderIds.push(o.id);await db.$transaction(tx=>vtb.prepare(tx,'CITY',o));return o;};
 const ride=await make(),id='CITY:'+ride.id;
 await assert.rejects(orders.updateOrderStatus(ride.id,'IN_PROGRESS',{userId:driver.id,role:'DRIVER'}),/не подтвердил оплату/);
 await assert.rejects(vtb.checkout(other.id,'CITY',ride.id),/не найдена/);
 await Promise.all(Array.from({length:20},()=>vtb.processPayment(id)));
 let p=await db.tripCardPayment.findUniqueOrThrow({where:{id}});assert.equal(byNumber.size,1);assert.equal(p.bankAmountMinor,70000);assert.equal(p.status,'ACTION_REQUIRED');
 bank.get(p.bankOrderId).orderStatus=2;await Promise.all(Array.from({length:20},()=>vtb.processPayment(id)));
 assert.equal((await db.wallet.findUnique({where:{userId:driver.id}})).moneyRub,0);
 await orders.updateOrderStatus(ride.id,'IN_PROGRESS',{userId:driver.id,role:'DRIVER'});
 const originalSettle=vtb.settle.bind(vtb);vtb.settle=async(...args)=>{await originalSettle(...args);throw Error('storage failure after credit');};
 await assert.rejects(orders.updateOrderStatus(ride.id,'COMPLETED',{userId:driver.id,role:'DRIVER'}),/storage failure/);
 assert.equal((await db.order.findUnique({where:{id:ride.id}})).status,'IN_PROGRESS');assert.equal((await db.wallet.findUnique({where:{userId:driver.id}})).moneyRub,0);
 assert.equal((await db.tripCardPayment.findUnique({where:{id}})).earningsCredited,false);vtb.settle=originalSettle;
 await orders.updateOrderStatus(ride.id,'COMPLETED',{userId:driver.id,role:'DRIVER'});
 for(let i=0;i<20;i++)await orders.updateOrderStatus(ride.id,'COMPLETED',{userId:driver.id,role:'DRIVER'});
 let wallet=await db.wallet.findUnique({where:{userId:driver.id}});assert.equal(wallet.moneyRub,90);assert.equal(wallet.money,0);assert.equal(wallet.bonus,0);assert.equal(wallet.bonusRub,0);
 assert.equal(await db.walletTransaction.count({where:{idempotencyKey:'card-earnings:'+id}}),1);assert.equal(await db.walletTransaction.count({where:{idempotencyKey:'order-commission:'+ride.id+':driver:'+driver.id}}),1);
 await assert.rejects(orders.cancelOrder(ride.id,passenger.id),/завершённую/);
 for(const wrong of [{amount:69999},{currency:643},{orderNumber:randomUUID()},{actionCode:5}]){
  const bad=await make();await vtb.processPayment('CITY:'+bad.id);const bp=await db.tripCardPayment.findUniqueOrThrow({where:{id:'CITY:'+bad.id}});Object.assign(bank.get(bp.bankOrderId),{orderStatus:2},wrong);await vtb.processPayment(bp.id);assert.notEqual((await db.tripCardPayment.findUnique({where:{id:bp.id}})).status,'PAID');assert.equal((await vtb.checkout(passenger.id,'CITY',bad.id)).paymentUrl,null);await assert.rejects(orders.updateOrderStatus(bad.id,'IN_PROGRESS',{userId:driver.id,role:'DRIVER'}),/не подтвердил оплату/);
 }
 const cancelled=await make();await vtb.processPayment('CITY:'+cancelled.id);p=await db.tripCardPayment.findUniqueOrThrow({where:{id:'CITY:'+cancelled.id}});bank.get(p.bankOrderId).orderStatus=2;await vtb.processPayment(p.id);await db.order.update({where:{id:cancelled.id},data:{status:'CANCELLED'}});
 await Promise.all(Array.from({length:20},()=>vtb.processPayment(p.id)));await vtb.processPayment(p.id);assert.equal((await db.tripCardPayment.findUnique({where:{id:p.id}})).status,'REFUNDED');assert(refunds.has(p.bankOrderNumber));assert.equal(await db.walletTransaction.count({where:{orderId:cancelled.id,type:'CARD_RIDE_EARNINGS'}}),0);
 const initialRefunds=refunds.size;const bound=await vtb.bind(passenger.id);const binding=await db.cardBinding.findUniqueOrThrow({where:{id:bound.bindingId}});assert.equal(bank.get(binding.providerId).amount,100);bank.get(binding.providerId).orderStatus=2;
 bindings.push({bindingId:'test-only-bank-token',clientId:passenger.id,maskedPan:'220138******0062'});
 await Promise.all(Array.from({length:20},()=>vtb.processBinding(binding.id)));assert.equal((await db.cardBinding.findUnique({where:{id:binding.id}})).status,'SYNCED');assert.equal(refunds.size,initialRefunds+1);
 const cards=await vtb.cards(passenger.id);assert.equal(cards.cards.length,1);assert.deepEqual(Object.keys(cards.cards[0]).sort(),['id','isDefault','last4']);
 const card=await db.savedPaymentCard.findUniqueOrThrow({where:{id:cards.cards[0].id}});assert.notEqual(card.tokenEncrypted,'test-only-bank-token');await assert.rejects(vtb.select(other.id,card.id),/не найдена/);
 payAutomatically=true;const auto=await make(card.id);await Promise.all(Array.from({length:20},()=>vtb.processPayment('CITY:'+auto.id)));p=await db.tripCardPayment.findUniqueOrThrow({where:{id:'CITY:'+auto.id}});assert.equal(p.status,'PAID');assert.equal(charges.filter(c=>c.id===p.bankOrderId).length,1);
 payAutomatically=false;const cvc=await make(card.id);await vtb.processPayment('CITY:'+cvc.id);p=await db.tripCardPayment.findUniqueOrThrow({where:{id:'CITY:'+cvc.id}});for(let i=0;i<20;i++)await vtb.processPayment(p.id);assert.equal(charges.filter(c=>c.id===p.bankOrderId).length,1);assert.equal((await db.tripCardPayment.findUnique({where:{id:p.id}})).status,'ACTION_REQUIRED');assert.equal((await vtb.checkout(passenger.id,'CITY',cvc.id)).paymentUrl,p.paymentUrl);
 await assert.rejects(vtb.remove(passenger.id,card.id),/завершения оплаты/);
 const acceptingDriver=await user('DRIVER');
 await db.wallet.update({where:{userId:acceptingDriver.id},data:{moneyRub:100}});
 const acceptingProfile=await db.driverProfile.create({data:{userId:acceptingDriver.id,status:'APPROVED',acceptCityFixed:true}});
 const waiting=await db.order.create({data:{passengerId:other.id,status:'SEARCHING_DRIVER',mode:'CITY',requestType:'CITY_FIXED',currency:'RUB',price:100,commissionAmount:10,dispatchDriverId:acceptingProfile.id,dispatchExpiresAt:new Date(Date.now()+60000),fromLat:56.8,fromLng:60.6,toLat:56.81,toLng:60.61,fromAddress:'QA A',toAddress:'QA B',paymentMethod:'CARD'}});
 orderIds.push(waiting.id);
 const bankCountBeforeAcceptance=byNumber.size;
 for(let i=0;i<20;i++)await vtb.processPayment('CITY:'+waiting.id);
 assert.equal(await db.tripCardPayment.count({where:{id:'CITY:'+waiting.id}}),0);assert.equal(byNumber.size,bankCountBeforeAcceptance);
 const driverService=new DriverService(db,{},realtime,push,{},null,undefined,undefined,payments);
 await driverService.acceptOrder(acceptingDriver.id,waiting.id);
 let acceptedPayment;
 for(let i=0;i<20;i++){acceptedPayment=await vtb.checkout(other.id,'CITY',waiting.id);if(acceptedPayment.paymentUrl)break;await new Promise(r=>setTimeout(r,10));}
 assert.equal(acceptedPayment.status,'ACTION_REQUIRED');assert.equal(byNumber.size,bankCountBeforeAcceptance+1);
 assert.equal((await db.wallet.findUnique({where:{userId:acceptingDriver.id}})).moneyRub,100);
 await orders.cancelOrder(waiting.id,other.id);await vtb.processPayment('CITY:'+waiting.id);
 assert.equal((await db.tripCardPayment.findUnique({where:{id:'CITY:'+waiting.id}})).status,'CANCELLED');
 await db.order.updateMany({where:{passengerId:passenger.id,status:{notIn:['COMPLETED','CANCELLED']}},data:{status:'CANCELLED'}});
 const request=await db.intercityRequest.create({data:{passengerId:passenger.id,fromCity:'QA A',toCity:'QA B',date:new Date(),price:50,currency:'RUB',status:'DRIVER_ARRIVED',selectedDriverId:driver.id,paymentMethod:'CARD'}});requestIds.push(request.id);
 const offer=await db.intercityOffer.create({data:{requestId:request.id,driverId:driver.id,price:100,seats:1,status:'ACCEPTED'}});
 await db.intercityRequest.update({where:{id:request.id},data:{selectedOfferId:offer.id}});
 await db.$transaction(tx=>vtb.prepare(tx,'INTERCITY',{...request,price:100},driver.id));await vtb.processPayment('INTERCITY:'+request.id);const ip=await db.tripCardPayment.findUniqueOrThrow({where:{id:'INTERCITY:'+request.id}});bank.get(ip.bankOrderId).orderStatus=2;await vtb.processPayment(ip.id);
 await intercity.updateDriverRequestStatus(driver.id,request.id,'IN_PROGRESS');await intercity.updateDriverRequestStatus(driver.id,request.id,'COMPLETED');
 assert.equal((await db.tripCardPayment.findUnique({where:{id:ip.id}})).status,'SETTLED');
 assert.equal((await db.wallet.findUnique({where:{userId:driver.id}})).moneyRub,190);
 assert.equal((await payments.state('CITY',ride.id)).provider,'VTB_SANDBOX');
 console.log(JSON.stringify({cityNetRub:90,intercityAgreedFareRub:100,repeatedVerifications:20,repeatedCompletions:20,bindingRefundKzt:1,automaticChargeOnce:true,cvcFallbackSameOrder:true,rollbackVerified:true,paymentOnlyAfterDriverAcceptance:true}));
 }finally{
 await db.taxIncomeEntry.deleteMany({where:{sourceId:{in:[...orderIds,...requestIds]}}});
 await db.walletTransaction.deleteMany({where:{wallet:{userId:{in:users}}}});
 await db.tripVerification.deleteMany({where:{passengerId:{in:users}}});
 await db.rideEvent.deleteMany({where:{orderId:{in:orderIds}}});
 await db.driverActivityEvent.deleteMany({where:{driver:{userId:{in:users}}}}).catch(()=>{});
 await db.order.deleteMany({where:{id:{in:orderIds}}});await db.intercityOffer.deleteMany({where:{requestId:{in:requestIds}}});await db.intercityRequest.deleteMany({where:{id:{in:requestIds}}});
 await db.cardBinding.deleteMany({where:{userId:{in:users}}});await db.savedPaymentCard.deleteMany({where:{userId:{in:users}}});await db.tripCardPayment.deleteMany({where:{passengerId:{in:users}}});
await db.driverServiceStats.deleteMany({where:{driver:{userId:{in:users}}}}).catch(()=>{});
 await db.driverProfile.deleteMany({where:{userId:{in:users}}});await db.wallet.deleteMany({where:{userId:{in:users}}});await db.user.deleteMany({where:{id:{in:users}}});await db.city.deleteMany({where:{id:{in:cityIds}}});
 await db.$disconnect();for(const [key,value]of Object.entries(saved)){if(value===undefined)delete process.env[key];else process.env[key]=value;}
 }
});
