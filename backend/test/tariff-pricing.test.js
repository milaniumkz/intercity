const {test}=require('node:test');
const assert=require('node:assert/strict');
const {OrdersService}=require('../dist/src/orders/orders.service');
const {AdminService}=require('../dist/src/admin/admin.service');
const {IntercityService}=require('../dist/src/intercity/intercity.service');
const route={fromLat:43,fromLng:76,toLat:43.1,toLng:76.1};
function service(currency='KZT') {
 const country=currency==='RUB'?'RU':'KZ';
 const p={tariffCity:{findMany:async()=>[
  {id:'economy',vehicleClass:'ECONOMY',basePrice:100,pricePerKm:20,pricePerMin:5,minPrice:200},
  {id:'comfort',vehicleClass:'COMFORT',basePrice:500,pricePerKm:60,pricePerMin:10,minPrice:900},
 ]},tariffCargo:{findFirst:async({where})=>{assert.equal(where.countryCode,country);return{id:'cargo',basePrice:1000,pricePerKm:100,pricePerKg:20,minPrice:1500}}},tariffDelivery:{findFirst:async({where})=>{assert.equal(where.countryCode,country);return{id:'delivery',basePrice:300,pricePerKm:50,pricePerKg:10,minPrice:500,doorToDoorFee:200}}}};
 return new OrdersService(p,{getRoute:async()=>({distance:3,duration:6}),reverseGeocode:async()=>({cityId:'city',currency})},{},{},{});
}
test('city price follows the selected configured class and refuses an unconfigured class',async()=>{
 const s=service();assert.equal((await s.previewOrder({...route,mode:'CITY',vehicleClass:'ECONOMY'})).price,200);
 assert.equal((await s.previewOrder({...route,mode:'CITY',vehicleClass:'COMFORT'})).price,900);
 await assert.rejects(s.previewOrder({...route,mode:'CITY',vehicleClass:'BUSINESS'}),/not configured/);
});
for(const currency of ['KZT','RUB']) test(`freight uses weight, minimum, door fee and departure country in ${currency}`,async()=>{
 const s=service(currency);
 assert.equal((await s.previewOrder({...route,mode:'CARGO',itemWeightKg:5})).price,1500);
 const heavy=await s.previewOrder({...route,requestType:'CARGO',itemWeightKg:20});assert.equal(heavy.price,1700);assert.equal(heavy.currency,currency);
 assert.equal((await s.previewOrder({...route,mode:'DELIVERY',itemWeightKg:10,doorToDoor:true})).price,750);
 await assert.rejects(s.previewOrder({...route,mode:'CARGO'}),/вес/);
 await assert.rejects(s.previewOrder({...route,mode:'CARGO',itemWeightKg:-1}),/вес/);
 await assert.rejects(s.previewOrder({...route,requestType:'CARGO',mode:'CITY',itemWeightKg:10}),/does not match/);
});
test('admin rejects negative, infinite and non-number freight rates and invalid countries',async()=>{
 const s=new AdminService({}, {}, {});
 for(const method of ['updateCargoTariff','updateDeliveryTariff']) for(const bad of [-1,NaN,Infinity,'20',null]) await assert.rejects(s[method]('id',{pricePerKg:bad}),/Invalid tariff amount/);
 await assert.rejects(s.createCargoTariff({name:'x',basePrice:10}),/Invalid tariff amount/);
 await assert.rejects(s.updateDeliveryTariff('id',{countryCode:'US'}),/Country/);
});
test('market rejects missing locations, invalid types, coordinates and weights before persistence',async()=>{
 const s=new IntercityService({},{});const data={requestType:'DELIVERY_CITY',fromCity:'Алматы',toCity:'Алматы, Абая',itemDescription:'Коробка',date:new Date(Date.now()+86400000).toISOString()};
 for(const extra of [{fromCity:'',toCity:''},{requestType:'UNKNOWN'},{itemWeightKg:-1},{itemWeightKg:'20'},{fromLat:95}]) await assert.rejects(s.createRequest('passenger',{...data,...extra}));
});

const {DriverService}=require('../dist/src/driver/driver.service');
test('driver active-order recovery queries the driver profile, not passenger history',async()=>{
 const s=new DriverService({driverProfile:{findUnique:async({where})=>{assert.equal(where.userId,'driver-user');return{id:'profile'}}},order:{findFirst:async({where})=>{assert.equal(where.driverId,'profile');assert(!where.passengerId);assert.deepEqual(where.status.in,['DRIVER_ASSIGNED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS']);return{id:'active-cargo',mode:'CARGO'}}}},{},{},{},{},{});
 assert.equal((await s.getActiveOrder('driver-user')).id,'active-cargo');
});

test('cargo preview reports absent or invalid tariff instead of returning zero price',async()=>{
 for(const tariff of [null,{basePrice:1000,pricePerKm:0,pricePerKg:20,minPrice:1500}]) {
  const s=new OrdersService({tariffCargo:{findFirst:async()=>tariff}},{getRoute:async()=>({distance:3,duration:6}),reverseGeocode:async()=>({currency:'KZT'})},{},{},{});
  await assert.rejects(s.previewOrder({...route,requestType:'CARGO',itemWeightKg:20}),/Грузовой тариф/);
 }
});
