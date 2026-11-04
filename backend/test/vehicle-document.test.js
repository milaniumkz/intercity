const {test}=require('node:test'),assert=require('node:assert/strict');
const {parseVehicleDocument,validateVehicleData}=require('../dist/src/identity/vehicle-document');
const catalogue=[{name:'BMW',models:[{name:'X5'},{name:'X3'}]},{name:'Toyota',models:[{name:'Camry'}]}];
const rows=(strings,confidence=98)=>strings.map(text=>({text,confidence}));
test('RU STS labelled vehicle fields are extracted without owner matching',()=>{
 const result=parseVehicleDocument(rows(['Государственный регистрационный знак','А123ВС777','Марка, модель','BMW X5','Год выпуска','2020','Владелец','Другое физическое лицо']),catalogue);
 assert.deepEqual(result,{brand:'BMW',model:'X5',year:2020,plateNumber:'A123BC777'});
});
test('KZ registration fields and plate spacing are supported',()=>{
 const result=parseVehicleDocument(rows(['Мемлекеттік тіркеу нөмірі','123 ABC 01','Маркасы, моделі','Toyota Camry','Шығарылған жылы','2021']),catalogue);
 assert.deepEqual(result,{brand:'Toyota',model:'Camry',year:2021,plateNumber:'123ABC01'});
});
test('contradicting years, missing labels, unknown models and uncertain OCR require manual review',()=>{
 const fixture=['Регистрационный номер','123 ABC 01','Марка модель','BMW X5','Год выпуска','2020'];
 for(const input of [rows([...fixture,'2021']),rows(fixture.map(x=>x==='BMW X5'?'BMW Unknown':x)),rows(fixture,60),rows(['123 ABC 01','BMW X5','2020'])])assert.equal(parseVehicleDocument(input,catalogue),null);
});
test('manual vehicle decision validates year and plate instead of accepting arbitrary strings',()=>{
 assert.throws(()=>validateVehicleData({brand:'BMW',model:'X5',year:9999,plateNumber:'anything'}));
 assert.throws(()=>validateVehicleData({brand:{},model:'X5',year:2020,plateNumber:'A123BC77'}));
 assert.deepEqual(validateVehicleData({brand:' BMW ',model:' X5 ',year:'2020',plateNumber:'А123ВС77'}),{brand:'BMW',model:'X5',year:2020,plateNumber:'A123BC77'});
});
const {repeatedVideo}=require('../dist/src/identity/identity.service');
test('temporal replay detection tolerates tiny re-encoding noise without searching across users',()=>{
 const a=Array(40).fill('123456789abcdef0'),b=[...a];b[10]='123456789abcdef1';assert.equal(repeatedVideo(a,b),true);
 assert.equal(repeatedVideo(a,Array(40).fill('fedcba9876543210')),false);assert.equal(repeatedVideo(a,['bad']),false);
});
const {AuthService}=require('../dist/src/auth/auth.service');
const {AdminService}=require('../dist/src/admin/admin.service');
test('legacy phone-only password reset stays disabled even with the former unsafe environment switch',async()=>{
 const old=process.env.ALLOW_UNVERIFIED_PASSWORD_RESET;process.env.ALLOW_UNVERIFIED_PASSWORD_RESET='true';
 try{await assert.rejects(new AuthService().resetPassword({phone:'+77000000000',password:'arbitrary-new-password'}),/видеопроверку/);}finally{if(old===undefined)delete process.env.ALLOW_UNVERIFIED_PASSWORD_RESET;else process.env.ALLOW_UNVERIFIED_PASSWORD_RESET=old;}
});
test('biometric review permissions fail closed when RBAC lookup fails',async()=>{
 const admin=new AdminService({user:{findUnique:async()=>({role:'ADMIN'})},adminRole:{count:async()=>{throw new Error('unavailable')}}});
 assert.equal(await admin.adminHasPermission('admin','identity.review',true),false);
});
