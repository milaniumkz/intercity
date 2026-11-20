const test = require('node:test');
const assert = require('node:assert/strict');
const { VtbSandboxGateway, verifiedVtbSandboxState } = require('../dist/src/payments/vtb-sandbox-gateway');
const id = '11111111-2222-3333-4444-555555555555';
const expected = { orderNumber: id, amountMinor: 10000 };
const paid = { errorCode: '0', orderNumber: id, amount: 10000, currency: '643', orderStatus: 2, actionCode: 0 };
const options = { userName: 'fixture-api', password: 'fixture-only' };
const input = { orderNumber: id, amountMinor: 10000, returnUrl: 'https://example.test/return' };

test('VTB uses only sandbox, RUB minor units, POST body authentication, and hosted checkout', async () => {
    let request;
    const gateway = new VtbSandboxGateway(options, async (url, init) => {
        request = { url: String(url), init };
        return new Response(JSON.stringify({ errorCode: '0', orderId: id, formUrl: 'https://vtbkz.rbsuat.com/payment/merchants/temp/payment_ru.html?mdOrder=' + id }));
    });
    assert.equal((await gateway.register(input)).orderId, id);
    assert.equal(request.url, 'https://vtbkz.rbsuat.com/payment/rest/register.do');
    assert.equal(request.init.method, 'POST');
    assert.equal(request.init.redirect, 'error');
    const body = new URLSearchParams(request.init.body);
    assert.equal(body.get('currency'), '643');
    assert.equal(body.get('amount'), '10000');
    assert.equal(body.get('userName'), options.userName);
    assert.equal(body.get('password'), options.password);
    assert.ok(!request.url.includes(options.password));
});

test('VTB rejects misleading success flags and never exposes provider credentials in errors', async () => {
    const gateway = new VtbSandboxGateway(options, async () => new Response(JSON.stringify({ success: false, errorCode: 0, errorMessage: options.password })));
    await assert.rejects(gateway.register(input), error => error.message.includes('код 0') && !error.message.includes(options.password));
});

test('VTB accepts payment only after matching currency, amount, order and captured status', () => {
    assert.equal(verifiedVtbSandboxState(paid, expected), 'SUCCEEDED');
    for (const patch of [{currency:'398'}, {currency:undefined}, {amount:9999}, {amount:'10000'}, {orderNumber:'foreign'}, {success:false}, {errorCode:5}]) {
        assert.equal(verifiedVtbSandboxState({...paid,...patch},expected), 'UNVERIFIED');
    }
    assert.equal(verifiedVtbSandboxState({...paid,orderStatus:1},expected),'PENDING');
    assert.equal(verifiedVtbSandboxState({...paid,orderStatus:5},expected),'PENDING');
    assert.equal(verifiedVtbSandboxState({...paid,orderStatus:6},expected),'FAILED');
    assert.equal(verifiedVtbSandboxState({...paid,orderStatus:4},expected),'CANCELLED');
    assert.notEqual(verifiedVtbSandboxState({...paid,actionCode:5},expected),'SUCCEEDED');
});

test('VTB rejects non-bank redirects, malformed payloads, HTTP failures and missing configuration', async () => {
    for (const formUrl of ['https://evil.test/pay','http://vtbkz.rbsuat.com/payment/pay','https://vtbkz.rbsuat.com.evil.test/payment/pay']) {
        const g = new VtbSandboxGateway(options, async () => new Response(JSON.stringify({orderId:id,formUrl})));
        await assert.rejects(g.register(input),/адрес/);
    }
    for(const response of [new Response('broken'),new Response('[]'),new Response('{}',{status:503})]) {
        await assert.rejects(new VtbSandboxGateway(options,async()=>response).register(input));
    }
    let calls=0;
    await assert.rejects(new VtbSandboxGateway({userName:'',password:''},async()=>{calls++;return new Response('{}')}).register(input));
    assert.equal(calls,0);
    await assert.rejects(new VtbSandboxGateway(options).register({...input,returnUrl:'http://example.test'}));
    await assert.rejects(new VtbSandboxGateway(options).register({...input,amountMinor:100.1}));
});
