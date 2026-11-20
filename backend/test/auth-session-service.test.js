const {test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const bcrypt = require('bcrypt');
const {PrismaClient} = require('@prisma/client');
const {JwtService} = require('@nestjs/jwt');
const {ConfigService} = require('@nestjs/config');
const {AuthService} = require('../dist/src/auth/auth.service');

const database = process.env.AUTH_SESSION_TEST_DATABASE_URL;
test('durable refresh sessions, concurrent devices and revocation against PostgreSQL',
  {skip: !database}, async t => {
  const url = new URL(database);
  assert.equal(url.hostname, '127.0.0.1');
  assert.equal(url.pathname, '/auth_session_test');
  const db = new PrismaClient({datasources:{db:{url:database}}});
  const jwt = new JwtService();
  const accessSecret = 'isolated-auth-access-secret-not-production';
  const refreshSecret = 'isolated-auth-refresh-secret-not-production';
  const config = new ConfigService({JWT_SECRET:accessSecret, JWT_REFRESH_SECRET:refreshSecret});
  const identity = {needsVerification:async()=>false};
  const service = client => new AuthService(client, jwt, {}, config, identity);
  const auth = service(db);
  const password = 'isolated-login-password-only';
  const users = [];
  async function account(role='PASSENGER') {
    const user = await db.user.create({data:{
      phone:'qa-session:'+randomUUID(), name:'Isolated session QA', role,
      password:await bcrypt.hash(password,4), refCode:randomUUID(), refLink:'',
    }});
    users.push(user.id);
    return user;
  }
  const login = user => auth.login({phone:user.phone,password});
  const unauthorized = error => error?.getStatus?.() === 401;
  const verify = pair => {
    const access = jwt.verify(pair.accessToken,{secret:accessSecret});
    const refresh = jwt.verify(pair.refreshToken,{secret:refreshSecret});
    assert.equal(access.sub,refresh.sub);
    assert.equal(refresh.type,'refresh');
    return access;
  };
  try {
    await t.test('an expired next-day access token refreshes without another password', async()=>{
      const user = await account(), first = await login(user);
      const tomorrow = Math.floor(Date.now()/1000)+86401;
      assert.throws(()=>jwt.verify(first.accessToken,{secret:accessSecret,clockTimestamp:tomorrow}),/expired/);
      jwt.verify(first.refreshToken,{secret:refreshSecret,clockTimestamp:tomorrow});
      const next = await auth.refreshToken(first.refreshToken);
      assert.equal(verify(next).sub,user.id);
      assert.notEqual(next.refreshToken,first.refreshToken);
      assert(await db.refreshToken.findUnique({where:{token:next.refreshToken}}));
    });

    await t.test('two phones keep separate sessions through twenty rotations each', async()=>{
      const user = await account('DRIVER');
      let a = await login(user), b = await login(user);
      assert.notEqual(a.refreshToken,b.refreshToken);
      assert.equal(await db.refreshToken.count({where:{userId:user.id,rotatedAt:null}}),2);
      for(let i=0;i<20;i++) {
        a = await auth.refreshToken(a.refreshToken);
        b = await auth.refreshToken(b.refreshToken);
        assert.equal(verify(a).sub,user.id);
        assert.equal(verify(b).sub,user.id);
      }
      assert.equal(await db.refreshToken.count({where:{userId:user.id,rotatedAt:null}}),2);
    });

    await t.test('different accounts retain independent sessions', async()=>{
      const alice=await account(), bob=await account('DRIVER');
      let a=await login(alice), b=await login(bob);
      for(let i=0;i<20;i++) {
        a=await auth.refreshToken(a.refreshToken);
        b=await auth.refreshToken(b.refreshToken);
        assert.equal(verify(a).sub,alice.id);
        assert.equal(verify(b).sub,bob.id);
      }
    });

    await t.test('twenty concurrent refreshes reuse one replacement without logging out other phones', async()=>{
      const user=await account(), first=await login(user), other=await login(user);
      const results=await Promise.all(Array.from({length:20},()=>auth.refreshToken(first.refreshToken)));
      assert.equal(new Set(results.map(x=>x.refreshToken)).size,1);
      assert.equal(await db.refreshToken.count({where:{userId:user.id,rotatedAt:null}}),2);
      for(const pair of results) assert.equal(verify(pair).sub,user.id);
      const next=await auth.refreshToken(results[0].refreshToken);
      const duplicate=await auth.refreshToken(first.refreshToken);
      assert.equal(duplicate.refreshToken,next.refreshToken);
      await auth.refreshToken(other.refreshToken);
    });

    await t.test('old rotated tokens stop working after the bounded retry window', async()=>{
      const user=await account(), first=await login(user);
      const next=await auth.refreshToken(first.refreshToken);
      await db.refreshToken.update({where:{token:first.refreshToken},
        data:{rotatedAt:new Date(Date.now()-31000)}});
      await assert.rejects(auth.refreshToken(first.refreshToken),unauthorized);
      assert.equal(verify(await auth.refreshToken(next.refreshToken)).sub,user.id);
    });

    await t.test('failed replacement creation rolls the old session back and reports a temporary failure', async()=>{
      const user=await account(), first=await login(user);
      const unavailable=db.$extends({query:{refreshToken:{
        async create(){throw new Error('isolated simulated storage outage');}
      }}});
      await assert.rejects(service(unavailable).refreshToken(first.refreshToken),
        error=>error?.getStatus?.()===503);
      const old=await db.refreshToken.findUnique({where:{token:first.refreshToken}});
      assert.equal(old.rotatedAt,null);
      assert.equal(old.replacementId,null);
      assert.equal(verify(await auth.refreshToken(first.refreshToken)).sub,user.id);
    });

    await t.test('password change still revokes every previous session of that account', async()=>{
      const user=await account(), another=await account();
      const other=await login(another);
      const sessions=[];
      for(let i=0;i<20;i++) sessions.push(await login(user));
      const next=await auth.changePassword(user.id,password,'changed-isolated-password-only');
      for(const pair of sessions) await assert.rejects(auth.refreshToken(pair.refreshToken),unauthorized);
      assert.equal(verify(await auth.refreshToken(next.refreshToken)).sub,user.id);
      assert.equal(verify(await auth.refreshToken(other.refreshToken)).sub,another.id);
    });

    await t.test('blocked, erased and version-revoked accounts cannot refresh', async()=>{
      for(const patch of [{blockedAt:new Date()},{authVersion:1},{phone:'erased:'+randomUUID()}]) {
        const user=await account(), pair=await login(user);
        await db.user.update({where:{id:user.id},data:patch});
        await assert.rejects(auth.refreshToken(pair.refreshToken),unauthorized);
      }
    });

    await t.test('expiry, token type and database ownership remain enforced', async()=>{
      const user=await account(), other=await account(), pair=await login(user);
      await db.refreshToken.update({where:{token:pair.refreshToken},data:{userId:other.id}});
      await assert.rejects(auth.refreshToken(pair.refreshToken),unauthorized);
      const fresh=await login(user);
      await db.refreshToken.update({where:{token:fresh.refreshToken},data:{expiresAt:new Date(Date.now()-1000)}});
      await assert.rejects(auth.refreshToken(fresh.refreshToken),unauthorized);
      const token=jwt.sign({sub:user.id,ver:0,type:'access'},{secret:refreshSecret,expiresIn:'7d'});
      await db.refreshToken.create({data:{userId:user.id,token,expiresAt:new Date(Date.now()+86400000)}});
      await assert.rejects(auth.refreshToken(token),unauthorized);
      await assert.rejects(auth.refreshToken('not-a-token'),unauthorized);
    });
  } finally {
    await db.refreshToken.deleteMany({where:{userId:{in:users}}});
    await db.user.deleteMany({where:{id:{in:users}}});
    await db.$disconnect();
  }
});
