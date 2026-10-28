const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {PrismaClient}=require('@prisma/client'),bcrypt=require('bcrypt'),{AuthService}=require('../dist/src/auth/auth.service');
const database=process.env.TARIFF_TEST_DATABASE_URL;
test('temporary password requires change; only correct current password replaces it and revokes old sessions',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/(ui_review_|dispatch_test)/);
 const p=new PrismaClient({datasources:{db:{url:database}}}),rollback=Error('rollback recovery');
 try{await assert.rejects(p.$transaction(async tx=>{
  const db=new Proxy(tx,{get:(t,k)=>k==='$transaction'?arg=>Array.isArray(arg)?Promise.all(arg):arg(db):t[k]});
  const phone='recovery:'+randomUUID();const user=await tx.user.create({data:{phone,password:await bcrypt.hash('123456',12),mustChangePassword:true,authVersion:1,name:'QA',refCode:randomUUID(),refLink:'test'}});
  const auth=new AuthService(db,{}, {}, {});auth.generateTokens=async()=>({accessToken:'local-only',refreshToken:'local-only'});
  assert.equal((await auth.login({phone,password:'123456'})).user.mustChangePassword,true);
  await tx.refreshToken.create({data:{userId:user.id,token:randomUUID(),expiresAt:new Date(Date.now()+86400000)}});
  await assert.rejects(auth.changePassword(user.id,'wrong','New-long-password-9'),/Неверный текущий/);
  assert.equal((await tx.user.findUnique({where:{id:user.id}})).mustChangePassword,true);
  await auth.changePassword(user.id,'123456','New-long-password-9');
  const changed=await tx.user.findUnique({where:{id:user.id}});assert.equal(changed.mustChangePassword,false);assert.equal(changed.authVersion,2);assert.equal(await tx.refreshToken.count({where:{userId:user.id}}),0);
  await assert.rejects(auth.login({phone,password:'123456'}),/Invalid credentials/);
  assert.equal((await auth.login({phone,password:'New-long-password-9'})).user.mustChangePassword,false);
  throw rollback;
 },{timeout:60000}),e=>e===rollback)}finally{await p.$disconnect()}
});
