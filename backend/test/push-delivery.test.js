const { test } = require('node:test');
const assert = require('node:assert/strict');
const { generateKeyPairSync } = require('node:crypto');
const { PushService } = require('../dist/src/notifications/push.service');

test('Firebase HTTP v1 authenticates, caches tokens and sends audible driver offers', async () => {
  const previous = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  const originalFetch = global.fetch;
  const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  process.env.FIREBASE_SERVICE_ACCOUNT_JSON = JSON.stringify({ project_id: 'test-project', client_email: 'test@example.invalid', private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }) });
  const calls = [];
  global.fetch = async (url, options) => {
    calls.push({ url, options });
    if (url.includes('oauth2')) return { ok: true, json: async () => ({ access_token: 'test-token', expires_in: 3600 }) };
    return { ok: true };
  };
  try {
    const service = new PushService({ user: { findUnique: async () => ({ pushToken: 'device-token' }) } });
    const payload = { title: 'Новый заказ', body: 'Заказ', data: { type: 'driver_offer', orderId: 'test-order' } };
    assert.equal(await service.sendToUser('driver', payload), true);
    assert.equal(await service.sendToUser('driver', payload), true);
    assert.equal(calls.length, 3);
    assert.match(calls[1].url, /v1\/projects\/test-project\/messages:send/);
    const message = JSON.parse(calls[1].options.body).message;
    assert.equal(message.token, 'device-token');
    assert.equal(message.data.type, 'driver_offer');
    assert.equal(message.android.notification.sound, 'intercity_order');
    assert.equal(message.apns.payload.aps.sound, 'intercity_order.wav');
    assert.equal(message.webpush.headers.TTL, '30');
  } finally {
    global.fetch = originalFetch;
    if (previous === undefined) delete process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    else process.env.FIREBASE_SERVICE_ACCOUNT_JSON = previous;
  }
});

test('permanently invalid FCM registrations are removed; transient errors retain registrations', async () => {
  const previous=process.env.FIREBASE_SERVICE_ACCOUNT_JSON,originalFetch=global.fetch;
  process.env.FIREBASE_SERVICE_ACCOUNT_JSON=JSON.stringify({project_id:'test-project',client_email:'test@example.invalid',private_key:'unused-cached-auth'});
  const cleared=[];let requests=0;
  const service=new PushService({user:{updateMany:async query=>{cleared.push(query);return {count:1}}}});
  service.accessToken={value:'cached-local-test',expires:Date.now()+60000};
  global.fetch=async (_url,options)=>{requests++;const token=JSON.parse(options.body).message.token;return {ok:false,status:token==='stale-device'?404:503,json:async()=>({error:{details:[{'@type':'type.googleapis.com/google.firebase.fcm.v1.FcmError',errorCode:token==='stale-device'?'UNREGISTERED':'UNAVAILABLE'}]}})}};
  try {
    assert.equal(await service.sendToToken('stale-device',{title:'Local mock',body:'No network'}),false);
    assert.deepEqual(cleared,[{where:{pushToken:'stale-device'},data:{pushToken:null}}]);
    assert.equal(await service.sendToToken('stale-device',{title:'Local mock',body:'No network'}),false);assert.equal(requests,1);
    assert.equal(await service.sendToToken('temporary-failure',{title:'Local mock',body:'No network'}),false);assert.equal(cleared.length,1);
  } finally {global.fetch=originalFetch;if(previous===undefined)delete process.env.FIREBASE_SERVICE_ACCOUNT_JSON;else process.env.FIREBASE_SERVICE_ACCOUNT_JSON=previous;}
});


test('web duplicate event tags stay stable without merging distinct trip states or messages',()=>{
 const {webNotificationTag}=require('../dist/src/notifications/push.service');
 const event={title:'Водитель прибыл',body:'Ожидает вас',data:{type:'order_status',orderId:'qa',status:'DRIVER_ARRIVED'}};
 assert.equal(webNotificationTag(event),webNotificationTag({...event}));
 assert.notEqual(webNotificationTag(event),webNotificationTag({...event,data:{...event.data,status:'COMPLETED'}}));
 assert.notEqual(webNotificationTag(event),webNotificationTag({...event,data:{...event.data,orderId:'other'}}));
 const chat={title:'Сообщение',body:'Здравствуйте',data:{type:'chat_message',orderId:'qa',messageId:'first'}};
 assert.notEqual(webNotificationTag(chat),webNotificationTag({...chat,data:{...chat.data,messageId:'second'}}));
 assert.equal(webNotificationTag({title:'Без заказа',body:'Тест'}),undefined);
});
