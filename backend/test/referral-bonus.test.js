const { test } = require('node:test');
const assert = require('node:assert/strict');
const { creditRideReferrals } = require('../dist/src/common/referral-bonus');
const { IntercityService } = require('../dist/src/intercity/intercity.service');
const { OrdersService } = require('../dist/src/orders/orders.service');

test('invalid or zero referral rates do not create credits', async () => {
    for (const value of ['0', '-1', '101', 'invalid']) {
        await creditRideReferrals({ appSettings: { findUnique: async () => ({ value }) } }, { commissionAmount: 100 });
    }
});

test('admin validates referral percentages and actual app store hosts', async () => {
    const { AdminService } = require('../dist/src/admin/admin.service');
    const admin = new AdminService({ appSettings: { upsert: async ({ create }) => create } }, {}, {});
    for (const value of ['-1', '101', 'invalid', '']) await assert.rejects(admin.setSetting('referralCommissionPercent', value));
    for (const value of ['http://apps.apple.com/app/id123', 'https://apps.apple.com.evil.invalid/app/id123', 'not-a-url']) await assert.rejects(admin.setSetting('appStoreUrl', value));
    assert.equal((await admin.setSetting('referralCommissionPercent', '25')).value, '25');
    assert.equal((await admin.setSetting('googlePlayUrl', 'https://play.google.com/store/apps/details?id=test')).key, 'googlePlayUrl');
});

test('completed city and intercity rides credit both inviters once in the ride currency', {
    skip: !process.env.CURRENCY_TEST_DATABASE_URL,
}, async () => {
    const url = new URL(process.env.CURRENCY_TEST_DATABASE_URL);
    assert.equal(url.hostname, '127.0.0.1');
    assert.equal(url.pathname, '/intercity_currency_test');
    const { PrismaClient } = require('@prisma/client');
    const db = new PrismaClient({ datasources: { db: { url: url.toString() } } });
    const users = [];
    const orderIds = [];
    const requestIds = [];
    const originalSettings = new Map();
    try {
        for (const [key, value] of [['referralCommissionPercent', '25'], ['intercityAcceptedRequestFeeRub', '200'], ['intercityCommissionByDistanceKmRub', '[]']]) {
            originalSettings.set(key, await db.appSettings.findUnique({ where: { key } }));
            await db.appSettings.upsert({ where: { key }, create: { key, value }, update: { value } });
        }
        const { AuthService } = require('../dist/src/auth/auth.service');
        const { JwtService } = require('@nestjs/jwt');
        const auth = new AuthService(db, new JwtService(), {}, { get: key => key === 'PUBLIC_WEB_URL' ? 'https://inter-city-pkzpps.web.app' : 'local-test-signing-secret' });
        for (let i = 0; i < 4; i++) {
            const id = require('node:crypto').randomUUID();
            if (i < 2) {
                users.push(await db.user.create({ data: {
                    phone: 'test-referral-' + id, name: 'Referral test', password: 'test-only',
                    refCode: id.replaceAll('-', '').toUpperCase(), refLink: 'test://' + id,
                    wallet: { create: { money: 1000, moneyRub: 1000 } },
                } }));
            } else {
                const phone = '+7999' + String(Date.now() + i).slice(-7);
                await auth.register({ phone, name: 'Invited test', password: 'test-password',
                    referralCode: 'https://intercity.89-207-255-27.sslip.io/#/ref/' + users[i - 2].refCode.toLowerCase() });
                const invited = await db.user.findUniqueOrThrow({ where: { phone } });
                users.push(invited);
                assert.equal(invited.referredBy, users[i - 2].refCode);
                await db.wallet.update({ where: { userId: invited.id }, data: { money: 1000, moneyRub: 1000 } });
                const login = await auth.login({ phone, password: 'test-password' });
                assert.ok(login.accessToken);
                const profile = await auth.validateUser(invited.id);
                assert.ok(profile.refLink.startsWith('https://intercity.89-207-255-27.sslip.io/#/ref/'));
                assert.equal((await auth.getReferralSummary(users[i - 2].id)).invitedCount, 1);
            }
        }
        const driver = await db.driverProfile.create({ data: { userId: users[3].id } });
        const orders = new OrdersService(db, {}, {}, { publish: () => {} }, { sendOrderStatusToPassenger: async () => {} });
        for (const currency of ['KZT', 'RUB']) {
            const order = await db.order.create({ data: {
                passengerId: users[2].id, driverId: driver.id, status: 'IN_PROGRESS',
                fromLat: 55, fromLng: 37, toLat: 56, toLng: 38,
                fromAddress: 'A', toAddress: 'B', price: 1000, commissionAmount: 100, currency,
            } });
            orderIds.push(order.id);
            await orders.updateOrderStatus(order.id, 'COMPLETED', { userId: users[3].id, role: 'DRIVER' });
            const ride = { id: order.id, passengerId: users[2].id, driverUserId: users[3].id, commissionAmount: 100, currency };
            await Promise.all([db.$transaction(tx => creditRideReferrals(tx, ride)), db.$transaction(tx => creditRideReferrals(tx, ride))]);
            const ledger = await db.walletTransaction.findMany({ where: { orderId: order.id, type: 'REFERRAL_ORDER_BONUS' } });
            assert.equal(ledger.length, 2);
            assert.ok(ledger.every(x => x.currency === currency && x.amount === 25));
        }
        const request = await db.intercityRequest.create({ data: {
            passengerId: users[2].id, selectedDriverId: users[3].id, status: 'IN_PROGRESS',
            fromCity: 'Москва', toCity: 'Казань', price: 2000, currency: 'RUB', date: new Date(),
        } });
        requestIds.push(request.id);
        const intercity = new IntercityService(db, {});
        await Promise.all([intercity.updateDriverRequestStatus(users[3].id, request.id, 'COMPLETED'), intercity.updateDriverRequestStatus(users[3].id, request.id, 'COMPLETED')]);
        const ledger = await db.walletTransaction.findMany({ where: { intercityRequestId: request.id, type: 'REFERRAL_ORDER_BONUS' } });
        assert.equal(ledger.length, 2);
        assert.ok(ledger.every(x => x.currency === 'RUB' && x.amount === 50));
        for (const user of users.slice(0, 2)) {
            const wallet = await db.wallet.findUnique({ where: { userId: user.id } });
            assert.equal(wallet.bonus, 25);
            assert.equal(wallet.bonusRub, 75);
        }
        assert.equal((await db.wallet.findUnique({ where: { userId: users[3].id } })).moneyRub, 700);
        // A failed ledger write must roll back the matching wallet credit.
        const before = await db.wallet.findUnique({ where: { userId: users[0].id } });
        await assert.rejects(db.$transaction(async tx => {
            await creditRideReferrals(tx, { id: 'rollback-test', passengerId: users[2].id, commissionAmount: 100, currency: 'RUB' });
            throw Error('simulate failure');
        }), /simulate failure/);
        assert.equal((await db.wallet.findUnique({ where: { userId: users[0].id } })).bonusRub, before.bonusRub);
    } finally {
        const ids = users.map(x => x.id);
        await db.walletTransaction.deleteMany({ where: { wallet: { userId: { in: ids } } } });
        await db.rideEvent.deleteMany({ where: { orderId: { in: orderIds } } });
        await db.order.deleteMany({ where: { id: { in: orderIds } } });
        await db.intercityRequest.deleteMany({ where: { id: { in: requestIds } } });
        await db.driverProfile.deleteMany({ where: { userId: { in: ids } } });
        await db.wallet.deleteMany({ where: { userId: { in: ids } } });
        await db.refreshToken.deleteMany({ where: { userId: { in: ids } } });
        await db.user.deleteMany({ where: { id: { in: ids } } });
        for (const [key, original] of originalSettings) {
            if (original) await db.appSettings.update({ where: { key }, data: { value: original.value } });
            else await db.appSettings.deleteMany({ where: { key } });
        }
        await db.$disconnect();
    }
});
