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
