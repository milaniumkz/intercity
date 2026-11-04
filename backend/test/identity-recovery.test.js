const {test}=require('node:test'),assert=require('node:assert/strict');
const {PrismaClient}=require('@prisma/client'),bcrypt=require('bcrypt'),fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path'),crypto=require('node:crypto');
const {IdentityService,IDENTITY_CONSENT}=require('../dist/src/identity/identity.service');
const database=process.env.DISPATCH_TEST_DATABASE_URL;
test('private video enrollment, matching, rejection, manual review and one-use reset against PostgreSQL',{skip:!database},async t=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/dispatch_test');
 const db=new PrismaClient({datasources:{db:{url:database}}}),root=await fs.mkdtemp(path.join(os.tmpdir(),'intercity-identity-')),previousRoot=process.env.TECH_STORAGE_DIR;
 process.env.TECH_STORAGE_DIR=root;
 const original=await db.appSettings.findUnique({where:{key:'identityVerificationEnabled'}}),users=[];
 const a=Array(128).fill(0),b=Array(128).fill(0);a[0]=1;b[1]=1;let result={verdict:'PASS',model:'test-face-v1',embedding:a,reference:Buffer.from('reference-image').toString('base64'),reason:''},calls=0,notifications=0;
 const engine={ready:async()=>true,verify:async()=>{calls++;return structuredClone(result)}};
 const service=new IdentityService(db,engine,{notifyReviews:async()=>{notifications++}});
 const video=()=>crypto.randomBytes(12000);
 try{
  await db.appSettings.upsert({where:{key:'identityVerificationEnabled'},create:{key:'identityVerificationEnabled',value:'true'},update:{value:'true'}});
  await service.onModuleInit();
  for(let i=0;i<3;i++)users.push(await db.user.create({data:{phone:'+7708'+String(crypto.randomInt(1e7)).padStart(7,'0'),name:'Identity local QA',password:await bcrypt.hash('initial-password-qa',4),role:i===2?'ADMIN':'PASSENGER',refCode:crypto.randomUUID(),refLink:''}}));
  const [alice,bob,admin]=users;
  const enroll=(u,extra={})=>service.challenge({userId:u.id,password:'initial-password-qa',ip:'127.0.0.1',consentVersion:IDENTITY_CONSENT,...extra});
  const recover=(u,ip='127.0.0.2')=>service.challenge({phone:u.phone,ip,consentVersion:IDENTITY_CONSENT});
  await t.test('binding requires password and explicit current consent',async()=>{
   await assert.rejects(enroll(alice,{password:'wrong'}),/Неверный пароль/);
   await assert.rejects(enroll(alice,{consentVersion:'old'}),/согласие/);
  });
  await t.test('successful initial enrollment encrypts and binds reference; no overwrite',async()=>{
   const c=await enroll(alice);assert.equal(new Set(c.actions).size,3);
   const r=await service.submit(c.challengeId,c.challengeToken,video(),alice.id);assert.equal(r.status,'VERIFIED');assert.equal(await service.needsVerification(alice.id,alice.role),false);
   const p=await db.biometricProfile.findUnique({where:{userId:alice.id}});assert(!p.template.includes(JSON.stringify(a)));
   assert.deepEqual(JSON.parse(service.vault.open(Buffer.from(p.template,'base64'),alice.id).toString()),a);
   assert.throws(()=>service.vault.open(Buffer.from(p.template,'base64'),bob.id));
   assert.equal((await service.vault.read(alice.id,p.referencePath)).toString(),'reference-image');
   await assert.rejects(enroll(alice),/нельзя заменить/);
  });
  await t.test('unknown or unenrolled recovery cannot create a reference or reset permission',async()=>{
   const c=await recover(bob);const r=await service.submit(c.challengeId,c.challengeToken,video());assert.equal(r.status,'REJECTED');assert.equal(r.resetToken,undefined);assert.equal(await db.biometricProfile.count({where:{userId:bob.id}}),0);
   const stored=await db.biometricChallenge.findUnique({where:{id:c.challengeId}});assert.equal(stored.userId,null);assert.equal(stored.resetHash,null);
  });
  await t.test('mismatch and spoof result never grant password reset',async()=>{
   result.embedding=b;let c=await recover(alice);assert.equal((await service.submit(c.challengeId,c.challengeToken,video())).status,'REJECTED');
   await assert.rejects(service.review(c.challengeId,admin.id,true,'Do not bypass a rejected mismatch'),/недоступна/);
   result={...result,embedding:a,verdict:'REJECT',reason:'photo rejected'};c=await recover(alice);assert.equal((await service.submit(c.challengeId,c.challengeToken,video())).status,'REJECTED');result.verdict='PASS';
  });
  await t.test('uncertain enrollment is retryable without manual review, storage or a total attempt limit',async()=>{
   result.verdict='REVIEW';result.reason='uncertain PAD';const before=notifications,c=await enroll(bob);
   assert.equal((await service.submit(c.challengeId,c.challengeToken,video(),bob.id)).status,'REJECTED');assert.equal(await service.needsVerification(bob.id,bob.role),true);assert.equal(notifications,before);
   const stored=await db.biometricChallenge.findUnique({where:{id:c.challengeId}});assert.equal(stored.candidate,null);assert.equal(stored.referencePath,null);assert.equal(stored.videoPath,null);
   await assert.rejects(service.review(c.challengeId,admin.id,true,'No manual initial enrollment approval'),/автоматически/);
   for(let i=0;i<20;i++)await enroll(bob);
   result.verdict='PASS';const next=await enroll(bob);assert.equal((await service.submit(next.challengeId,next.challengeToken,video(),bob.id)).status,'VERIFIED');
   assert.equal(await service.needsVerification(bob.id,bob.role),false);
  });
  await t.test('uncertain recovery still requires a manual decision and keeps its rate limits',async()=>{
   await db.biometricChallenge.updateMany({where:{userId:alice.id},data:{createdAt:new Date(Date.now()-2*3600000)}});
   result.verdict='REVIEW';const c=await recover(alice,'127.0.0.9');assert.equal((await service.submit(c.challengeId,c.challengeToken,video())).status,'REVIEW');
   await service.review(c.challengeId,admin.id,true,'Reviewed live video and compared with reference');assert.equal((await service.challengeStatus(c.challengeId,c.challengeToken)).status,'VERIFIED');result.verdict='PASS';
  });
  await t.test('expired challenge and foreign session secret are rejected before engine work',async()=>{
   const c=await recover(alice,'127.0.0.3'),before=calls;await db.biometricChallenge.update({where:{id:c.challengeId},data:{expiresAt:new Date(Date.now()-1)}});
   await assert.rejects(service.submit(c.challengeId,c.challengeToken,video()),/истекла/);await assert.rejects(service.challengeStatus(c.challengeId,'x'.repeat(43)),/не разрешено/);assert.equal(calls,before);
  });
  await t.test('valid reset token is consumed once, rotates authVersion and revokes refresh sessions',async()=>{
   // Earlier recovery attempts are intentionally rate limited; use a new hour for this fixture.
   await db.biometricChallenge.updateMany({where:{userId:alice.id},data:{createdAt:new Date(Date.now()-2*3600000)}});
   await db.refreshToken.create({data:{userId:alice.id,token:'local-old-session-'+crypto.randomUUID(),expiresAt:new Date(Date.now()+3600000)}});
   const c=await recover(alice,'127.0.0.4'),r=await service.submit(c.challengeId,c.challengeToken,video());assert.equal(r.status,'VERIFIED');assert.equal(r.resetToken.length,64);
   const outcomes=await Promise.allSettled([service.resetPassword(r.resetToken,'new-password-first'),service.resetPassword(r.resetToken,'new-password-second')]);assert.equal(outcomes.filter(x=>x.status==='fulfilled').length,1);
   const user=await db.user.findUnique({where:{id:alice.id}});assert.equal(user.authVersion,1);assert.equal(await db.refreshToken.count({where:{userId:alice.id}}),0);await assert.rejects(service.resetPassword(r.resetToken,'another-password-qa'),/не разрешено/);
   assert(await bcrypt.compare(outcomes[0].status==='fulfilled'?'new-password-first':'new-password-second',user.password));
  });
  await t.test('administrators never enroll or recover through passenger face flow',async()=>{
   assert.equal(await service.needsVerification(admin.id,admin.role),false);const c=await recover(admin);assert.equal((await service.submit(c.challengeId,c.challengeToken,video())).status,'REJECTED');
  });
 }finally{
  service.onModuleDestroy();const ids=users.map(u=>u.id);await db.adminAuditLog.deleteMany({where:{adminId:{in:ids}}});await db.refreshToken.deleteMany({where:{userId:{in:ids}}});await db.user.deleteMany({where:{id:{in:ids}}});
  if(original)await db.appSettings.update({where:{key:original.key},data:{value:original.value}});else await db.appSettings.deleteMany({where:{key:'identityVerificationEnabled'}});
  await db.$disconnect();await fs.rm(root,{recursive:true,force:true});if(previousRoot===undefined)delete process.env.TECH_STORAGE_DIR;else process.env.TECH_STORAGE_DIR=previousRoot;
 }
});
