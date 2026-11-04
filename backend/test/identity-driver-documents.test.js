const {test}=require('node:test'),assert=require('node:assert/strict'),crypto=require('node:crypto'),fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path');
const {PrismaClient}=require('@prisma/client');
const {IdentityService}=require('../dist/src/identity/identity.service');
const {DriverDocumentService}=require('../dist/src/identity/driver-document.service');
const database=process.env.DISPATCH_TEST_DATABASE_URL;
test('driver document matching, authoritative vehicle correction and uncertain-document review',{skip:!database},async t=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/dispatch_test');
 const db=new PrismaClient({datasources:{db:{url:database}}}),root=await fs.mkdtemp(path.join(os.tmpdir(),'intercity-driver-identity-')),oldRoot=process.env.TECH_STORAGE_DIR;
 process.env.TECH_STORAGE_DIR=root;const settings=await db.appSettings.findUnique({where:{key:'identityVerificationEnabled'}});const users=[],files=[];let driver,make,model;const v=Array(128).fill(0);v[0]=1;const other=Array(128).fill(0);other[1]=1;let face=v,uncertain=false;
 const picture=Buffer.from('synthetic-test-document').toString('base64');
 const engine={ready:async()=>true,document:async(_buffer,kind)=>kind==='face'?{model:'test-face',embedding:face,reference:picture,quality:true}:{model:'test-ocr',reference:picture,lines:(uncertain?['Регистрационный номер','123 ABC 01','Марка модель','QA MOTORS Q1']:['Регистрационный номер','123 ABC 01','Марка модель','QA MOTORS Q1','Год выпуска','2020']).map(text=>({text,confidence:98}))}};
 const identity=new IdentityService(db,engine,{notifyReviews:async()=>{}});
 const tech={fileBytes:async id=>({row:await db.techFile.findUnique({where:{id}}),buffer:Buffer.from('document')})};
 const docs=new DriverDocumentService(db,identity,engine,tech,{notifyReviews:async()=>{}});
 const file=async(docType,userId=users[0].id)=>{const id=crypto.randomBytes(16).toString('hex');const r=await db.techFile.create({data:{id,userId,requestId:'qa',objectId:driver.id,docType,path:id+'.bin',mime:'image/jpeg',size:10000,sha256:crypto.randomBytes(32).toString('hex'),verdict:'PASS',reason:'QA',algorithm:'qa'}});files.push(id);return r;};
 try{
  await db.appSettings.upsert({where:{key:'identityVerificationEnabled'},create:{key:'identityVerificationEnabled',value:'true'},update:{value:'true'}});await identity.onModuleInit();
  for(const role of ['DRIVER','ADMIN'])users.push(await db.user.create({data:{phone:'+7706'+String(crypto.randomInt(1e7)).padStart(7,'0'),name:'Local document QA',password:'unusable',role,refCode:crypto.randomUUID(),refLink:''}}));
  const [user,admin]=users;driver=await db.driverProfile.create({data:{userId:user.id,carModel:'Incorrect car',carNumber:'A111AA77'}});
  make=await db.carMake.create({data:{id:2000000000+crypto.randomInt(1e6),name:'QA MOTORS'}});model=await db.carModel.create({data:{id:2000000000+crypto.randomInt(1e6),makeId:make.id,name:'Q1'}});
  await db.biometricProfile.create({data:{userId:user.id,model:'test-face',template:identity.vault.seal(Buffer.from(JSON.stringify(v)),user.id).toString('base64'),referencePath:await identity.vault.write(user.id,Buffer.from('reference')),consentVersion:'qa',driverConsent:true}});
  const passport=await file('passport'),front=await file('techPassportFront'),license=await file('driverLicense');
  await db.driverProfile.update({where:{id:driver.id},data:{driverLicenseUrl:`/api/driver/docs/files/${license.id}`,passportUrl:`/api/driver/docs/files/${passport.id}`,techPassportFrontUrl:`/api/driver/docs/files/${front.id}`}});
  await t.test('verified document face and high-confidence vehicle data are bound to current files',async()=>{
   const r=await docs.check(user.id);assert.equal(r.identityStatus,'VERIFIED');assert.equal(r.vehicleStatus,'VERIFIED');const actual=await db.driverProfile.findUnique({where:{id:driver.id}});assert.equal(actual.carModel,'QA MOTORS Q1');assert.equal(actual.carNumber,'123ABC01');const car=await db.vehicle.findFirst({where:{driverId:driver.id,isActive:true}});assert.equal(car.year,2020);await docs.assertVerified(user.id);
  });
  await t.test('subsequent manual vehicle changes invalidate work and are corrected from the same document',async()=>{
   await db.driverProfile.update({where:{id:driver.id},data:{carNumber:'A999AA77'}});await assert.rejects(docs.assertVerified(user.id),/проверку автомобиля/);await docs.check(user.id);assert.equal((await db.driverProfile.findUnique({where:{id:driver.id}})).carNumber,'123ABC01');await docs.assertVerified(user.id);
  });
  await t.test('uncertain vehicle fields require explicit administrative data and cannot auto-approve',async()=>{
   const next=await file('techPassportFront');await db.driverProfile.update({where:{id:driver.id},data:{techPassportFrontUrl:`/api/driver/docs/files/${next.id}`}});uncertain=true;
   const r=await docs.check(user.id);assert.equal(r.vehicleStatus,'REVIEW');await assert.rejects(docs.assertVerified(user.id),/проверку автомобиля/);
   const c=await db.biometricChallenge.findFirst({where:{userId:user.id,purpose:'VEHICLE',status:'REVIEW'}});assert(c);await assert.rejects(docs.review(c.id,admin.id,true,'Read the technical passport',{}),/Укажите/);
   await docs.review(c.id,admin.id,true,'Read all four fields from the original document',{brand:'QA MOTORS',model:'Q1',year:2020,plateNumber:'123ABC01'});await docs.assertVerified(user.id);
   await assert.rejects(docs.review(c.id,admin.id,true,'Try to reuse reviewed document',{}),/недоступна/);
  });
  await t.test('mismatching identity photo is denied, including administrative bypass attempt',async()=>{
   face=other;const next=await file('passport');await db.driverProfile.update({where:{id:driver.id},data:{passportUrl:`/api/driver/docs/files/${next.id}`}});const r=await docs.check(user.id);assert.equal(r.identityStatus,'REJECTED');await assert.rejects(docs.assertVerified(user.id),/сверку/);
   const c=await db.biometricChallenge.findFirst({where:{userId:user.id,purpose:'DRIVER_IDENTITY',status:'REJECTED'}});await assert.rejects(docs.review(c.id,admin.id,true,'Cannot approve a rejected mismatch'),/недоступна/);
  });
  await t.test('a driver cannot submit another account’s document',async()=>{
   const foreign=await file('passport',admin.id);await db.driverProfile.update({where:{id:driver.id},data:{passportUrl:`/api/driver/docs/files/${foreign.id}`}});await assert.rejects(docs.check(user.id),/Недопустимый документ/);
  });
 }finally{
  identity.onModuleDestroy();if(driver){await db.vehicle.deleteMany({where:{driverId:driver.id}});await db.driverProfile.deleteMany({where:{id:driver.id}});}await db.techFile.deleteMany({where:{id:{in:files}}});await db.adminAuditLog.deleteMany({where:{adminId:{in:users.map(u=>u.id)}}});await db.user.deleteMany({where:{id:{in:users.map(u=>u.id)}}});if(model)await db.carModel.deleteMany({where:{id:model.id}});if(make)await db.carMake.deleteMany({where:{id:make.id}});
  if(settings)await db.appSettings.update({where:{key:settings.key},data:{value:settings.value}});else await db.appSettings.deleteMany({where:{key:'identityVerificationEnabled'}});await db.$disconnect();await fs.rm(root,{recursive:true,force:true});if(oldRoot===undefined)delete process.env.TECH_STORAGE_DIR;else process.env.TECH_STORAGE_DIR=oldRoot;
 }
});
