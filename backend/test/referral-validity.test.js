const {test}=require('node:test'),assert=require('node:assert/strict');
const {AuthService}=require('../dist/src/auth/auth.service');
test('saved invitation validity checks do not expose the inviter or mutate referral data',async()=>{
 let searched;const service=Object.create(AuthService.prototype);service.prisma={user:{findUnique:async({where,select})=>{searched=where.refCode;assert.deepEqual(select,{phone:true});return where.refCode==='LIVE42'?{phone:'+77000000000'}:where.refCode==='ERASED'?{phone:'erased:account'}:null}}};
 assert.deepEqual(await service.referralValidity('https://example.test/#/ref/live42'),{valid:true});assert.equal(searched,'LIVE42');
 assert.deepEqual(await service.referralValidity('OLD123'),{valid:false});assert.deepEqual(await service.referralValidity('ERASED'),{valid:false});
 searched=null;assert.deepEqual(await service.referralValidity(''),{valid:false});assert.equal(searched,null);
});
test('registration ignores invalid and erased invitations and preserves valid attribution',async()=>{
 for(const [code,expected]of [['OLD123',null],['live42','LIVE42'],['ERASED',null]]){
  const service=Object.create(AuthService.prototype);let created,wallet=false;
  service.generateUniquePublicId=async()=>'10000001';service.generateUniqueRefCode=async()=>'OWN123';service.buildReferralLink=c=>'https://example.test/#/ref/'+c;service.generateTokens=async()=>({accessToken:'test',refreshToken:'test'});service.identity={needsVerification:async()=>true};
  const tx={user:{create:async({data})=>{created=data;return{id:'fixture',...data,mustChangePassword:false}}},wallet:{create:async()=>{wallet=true}}};
  service.prisma={user:{findUnique:async({where})=>where.phone?null:where.refCode==='LIVE42'?{refCode:'LIVE42',phone:'+77000000000',cityId:'city'}:where.refCode==='ERASED'?{refCode:'ERASED',phone:'erased:fixture'}:null},$transaction:fn=>fn(tx)};
  const result=await service.register({phone:'+77000000001',password:'123456',name:'Fixture',referralCode:code});
  assert.equal(created.referredBy,expected);assert(wallet);assert.equal(result.user.refCode,'OWN123');assert.equal(created.cityId,expected?'city':null);
 }
});
