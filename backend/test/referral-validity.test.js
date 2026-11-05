const {test}=require('node:test'),assert=require('node:assert/strict');
const {AuthService}=require('../dist/src/auth/auth.service');
test('saved invitation validity checks do not expose the inviter or mutate referral data',async()=>{
 let searched;const service=Object.create(AuthService.prototype);service.prisma={user:{findUnique:async({where,select})=>{searched=where.refCode;assert.deepEqual(select,{phone:true});return where.refCode==='LIVE42'?{phone:'+77000000000'}:where.refCode==='ERASED'?{phone:'erased:account'}:null}}};
 assert.deepEqual(await service.referralValidity('https://example.test/#/ref/live42'),{valid:true});assert.equal(searched,'LIVE42');
 assert.deepEqual(await service.referralValidity('OLD123'),{valid:false});assert.deepEqual(await service.referralValidity('ERASED'),{valid:false});
 searched=null;assert.deepEqual(await service.referralValidity(''),{valid:false});assert.equal(searched,null);
});
