const { test } = require('node:test');
const assert = require('node:assert/strict');
const { GeoService } = require('../dist/src/geo/geo.service');
const { OrdersService } = require('../dist/src/orders/orders.service');
const { IntercityService } = require('../dist/src/intercity/intercity.service');
const { RidesharingService } = require('../dist/src/ridesharing/ridesharing.service');
const { AdminService } = require('../dist/src/admin/admin.service');
const { currencyForCountry } = require('../dist/src/common/currency');

test('country currency uses departure country, never destination or phone', async () => {
    assert.equal(currencyForCountry('RU'), 'RUB');
    assert.equal(currencyForCountry('ru'), 'RUB');
    assert.equal(currencyForCountry('KZ'), 'KZT');
    const geo = new GeoService({ city: { findMany: async () => [
        {name:'Москва',aliases:[],countryCode:'RU',lat:55.75,lng:37.6},
        {name:'Алматы',aliases:[],countryCode:'KZ',lat:43.2,lng:76.9},
    ] } }, { get: () => undefined });
    assert.equal(await geo.departureCurrency(43.2, 76.9, 'Москва'), 'RUB');
    assert.equal(await geo.departureCurrency(55.8, 37.6, 'Алматы'), 'KZT');
});

test('same-named cities across countries use the selected departure point and country hint',async()=>{
    const geo=new GeoService({city:{findMany:async()=>[
        {id:'kz',name:'Актау',aliases:[],countryCode:'KZ',lat:43.65,lng:51.15},
        {id:'ru',name:'Актау',aliases:[],countryCode:'RU',lat:55,lng:70},
    ]}},{get:()=>undefined});
    assert.equal(await geo.departureCurrency(55,70,'Актау'),'RUB');
    assert.equal(await geo.departureCurrency(43.65,51.15,'Актау'),'KZT');
    assert.equal(await geo.departureCurrency(null,null,'Актау, Россия'),'RUB');
    assert.equal(await geo.departureCurrency(null,null,'Актау, Казахстан'),'KZT');
});

test('city preview uses only configured city rates and returns its currency', async () => {
    const tariffs = {
        ru: { basePrice: 150, pricePerKm: 20, pricePerMin: 5, minPrice: 200 },
        kz: { basePrice: 500, pricePerKm: 80, pricePerMin: 10, minPrice: 1000 },
    };
    const queries = [];
    const prisma = { tariffCity: { findMany: async ({ where }) => {
        queries.push(where); return tariffs[where.cityId] ? [tariffs[where.cityId]] : [];
    } } };
    const service = new OrdersService(prisma, {
        reverseGeocode: async (lat) => ({ cityId: lat === 55 ? 'ru' : lat === 43 ? 'kz' : 'missing', currency: lat === 43 ? 'KZT' : 'RUB' }),
        getRoute: async () => ({ distance: 3, duration: 6 }),
    }, {}, {}, {});
    const dto = { fromLat: 55, fromLng: 37, toLat: 55.01, toLng: 37.01, mode: 'CITY' };
    const ru = await service.previewOrder(dto);
    assert.equal(ru.currency, 'RUB');
    assert.equal(ru.price, 250);
    const kz = await service.previewOrder({ ...dto, fromLat: 43 });
    assert.equal(kz.currency, 'KZT');
    assert.equal(kz.price, 1000);
    await assert.rejects(service.previewOrder({ ...dto, fromLat: 56 }), /City tariff is not configured/);
    assert.deepEqual(queries, ['ru', 'kz', 'missing'].map(cityId => ({ cityId, isActive: true })));
});

test('intercity requests preserve departure currency including cross-border trips', async () => {
    const tx = { $queryRaw: async () => [{ id: 'passenger' }], order: { findFirst: async () => null }, intercityRequest: { findFirst: async () => null, create: async ({ data }) => data } };
    const service = new IntercityService({ $transaction: async run => run(tx) }, {
        departureCurrency: async (_lat, _lng, city) => city === 'Москва' ? 'RUB' : 'KZT',
    });
    const date = new Date(Date.now() + 86400000).toISOString();
    for (const [fromCity, toCity, currency] of [['Москва', 'Казань', 'RUB'], ['Москва', 'Алматы', 'RUB'], ['Алматы', 'Москва', 'KZT']]) {
        const result = await service.createRequest('passenger', { fromCity, toCity, date, price: 1500 });
        assert.equal(result.currency, currency);
        assert.equal(result.price, 1500);
    }
});

test('ridesharing persists authoritative currency for seat prices', async () => {
    const service = new RidesharingService({ rideSharingTrip: { create: async ({ data }) => data } }, {
        departureCurrency: async () => 'RUB',
    });
    const trip = await service.createTrip('driver', {
        fromCity: 'Москва', toCity: 'Казань', fromLat: 55.75, fromLng: 37.6,
        toLat: 55.8, toLng: 49.1, seatsTotal: 3, pricePerSeat: 1200,
        currency: 'KZT', departureTime: new Date(Date.now() + 86400000).toISOString(),
    });
    assert.equal(trip.currency, 'RUB');
    assert.equal(trip.pricePerSeat, 1200);
});

test('admin rejects unsupported countries and invalid city prices', async () => {
    const service = new AdminService({}, {}, {});
    await assert.rejects(service.createCity({ name: 'Paris', countryCode: 'FR', lat: 48, lng: 2 }), /Country must/);
    for (const amount of [-1, NaN, Infinity, '500']) {
        await assert.rejects(service.updateCityTariff('tariff', { pricePerKm: amount }), /Invalid tariff amount/);
    }
});

test('RUB bonuses cannot be funded from the KZT balance', async () => {
    const orders = new OrdersService({
        tariffCity: { findMany: async () => [{ basePrice: 150, pricePerKm: 20, pricePerMin: 5, minPrice: 200 }] },
        appSettings: { findMany: async () => [] },
        wallet: { findUnique: async () => ({ bonus: 100000, bonusRub: 0 }) },
    }, {
        reverseGeocode: async () => ({ cityId: 'ru', currency: 'RUB' }),
        getRoute: async () => ({ distance: 3, duration: 6 }),
    }, {}, {}, {});
    await assert.rejects(orders.createOrder('passenger', {
        fromLat: 55, fromLng: 37, toLat: 56, toLng: 38, fromAddress: 'A', toAddress: 'B',
        mode: 'CITY', vehicleClass: 'ECONOMY', paymentMethod: 'BONUSES',
    }), /Insufficient bonus balance/);
});

test('RUB intercity commissions use their own configuration, without KZT fees', async () => {
    const keys = [];
    let rubFee;
    const service = new IntercityService({
        user: { findUnique: async () => ({ phone: '+79991234567' }) },
        appSettings: { findUnique: async ({ where }) => {
            keys.push(where.key);
            return where.key === 'intercityAcceptedRequestFeeRub' && rubFee != null ? { value: String(rubFee) } : null;
        } },
    }, {});
    const request = { currency: 'RUB', price: 2000 };
    assert.equal(await service.getIntercityAcceptedRequestFee(request, 'driver'), 0);
    rubFee = 30;
    assert.equal(await service.getIntercityAcceptedRequestFee(request, 'driver'), 30);
    assert.ok(keys.every(key => key.endsWith('Rub')));
});

test('financial totals and CSV queries never combine RUB and KZT', async () => {
    const seen = [];
    const read = async ({ where }) => { seen.push(where.currency); return { _sum: { price: 500, commissionAmount: 50, amount: 100 } }; };
    const admin = new AdminService({
        order: { count: async ({ where }) => { seen.push(where.currency); return 1; }, aggregate: read },
        topupRequest: { aggregate: read }, payoutRequest: { aggregate: read },
    }, {}, {});
    assert.equal((await admin.getFinanceReport(undefined, undefined, 'RUB')).currency, 'RUB');
    assert.deepEqual(seen, Array(5).fill('RUB'));
    seen.length = 0;
    assert.equal((await admin.getFinanceReport()).currency, 'KZT');
    assert.deepEqual(seen, Array(5).fill('KZT'));
});

test('local database stores city rates and immutable order/request currencies', {
    skip: !process.env.CURRENCY_TEST_DATABASE_URL,
}, async () => {
    const url = new URL(process.env.CURRENCY_TEST_DATABASE_URL);
    assert.equal(url.hostname, '127.0.0.1');
    assert.equal(url.pathname, '/intercity_currency_test');
    const { PrismaClient } = require('@prisma/client');
    const prisma = new PrismaClient({ datasources: { db: { url: url.toString() } } });
    try {
        const admin = new AdminService(prisma, { publish: () => {} }, {});
        const suffix = require('node:crypto').randomUUID();
        const ru = await admin.createCity({ name: `TEST_RU_${suffix}`, countryCode: 'RU', lat: 55, lng: 37 });
        const kz = await admin.createCity({ name: `TEST_KZ_${suffix}`, countryCode: 'KZ', lat: 43, lng: 76 });
        const tariff = await admin.createCityTariff({ cityId: ru.id, name: 'Стандарт', basePrice: 150, pricePerKm: 20, pricePerMin: 5, minPrice: 200 });
        await admin.createCityTariff({ cityId: kz.id, name: 'Стандарт', basePrice: 500, pricePerKm: 80, pricePerMin: 10, minPrice: 1000 });
        const geo = {
            reverseGeocode: async (lat) => ({ cityId: lat === 55 ? ru.id : kz.id, currency: lat === 55 ? 'RUB' : 'KZT' }),
            getRoute: async () => ({ distance: 3, duration: 6 }),
            departureCurrency: async (_lat, _lng, name) => name === ru.name ? 'RUB' : 'KZT',
        };
        const orders = new OrdersService(prisma, geo, { assignCityOrder: async () => {} }, { publish: () => {} }, { sendOrderStatusToPassenger: async () => {} });
        const user = await prisma.user.create({ data: { phone: '+7700' + Date.now().toString().slice(-7), password: 'test-only', name: 'Currency test', refCode: suffix, refLink: `test://${suffix}` } });
        const dto = { fromLat: 55, fromLng: 37, toLat: 55.01, toLng: 37.01, fromAddress: 'A', toAddress: 'B', mode: 'CITY', vehicleClass: 'ECONOMY', paymentMethod: 'CASH' };
        assert.equal((await orders.previewOrder(dto)).price, 250);
        await admin.updateCityTariff(tariff.id, { pricePerKm: 100 });
        assert.equal((await orders.previewOrder(dto)).price, 500);
        const order = await orders.createOrder(user.id, dto);
        assert.equal(order.currency, 'RUB');
        assert.equal(order.price, 500);
        const intercity = new IntercityService(prisma, geo);
        await assert.rejects(intercity.createRequest(user.id, { fromCity: ru.name, toCity: kz.name, price: 2000, date: new Date(Date.now() + 86400000).toISOString() }), /активный заказ/);
        await orders.cancelOrder(order.id, user.id);
        const request = await intercity.createRequest(user.id, { fromCity: ru.name, toCity: kz.name, price: 2000, date: new Date(Date.now() + 86400000).toISOString() });
        assert.equal(request.currency, 'RUB');
        await assert.rejects(orders.createOrder(user.id, dto), /активный заказ/);
        await intercity.cancelRequest(user.id, request.id);
        const { WalletService } = require('../dist/src/wallet/wallet.service');
        const wallets = new WalletService(prisma);
        const original = await prisma.wallet.create({ data: { userId: user.id, money: 7000, bonus: 8000, moneyRub: 2000, bonusRub: 3000 } });
        const recipient = await prisma.user.create({ data: { phone: '+7999' + Date.now().toString().slice(-7), password: 'test-only', name: 'Wallet recipient', refCode: ('r' + suffix).toUpperCase(), refLink: 'test://r' + suffix, wallet: { create: {} } } });
        const rub = await wallets.getWallet(user.id, 'RUB');
        assert.equal(rub.money, 2000);
        assert.equal(rub.bonus, 3000);
        assert.deepEqual(rub.balances.KZT, { money: 7000, bonus: 8000 });
        await assert.rejects(wallets.getWallet(user.id, 'USD'), /Unsupported/);
        await wallets.transferBonusByPhone(user.id, recipient.phone, 100, 'RUB');
        assert.equal((await wallets.getWallet(recipient.id, 'RUB')).bonus, 100);
        assert.equal((await wallets.getWallet(recipient.id, 'KZT')).bonus, 0);
        const bonusOrder = await orders.createOrder(user.id, { ...dto, paymentMethod: 'BONUSES' });
        assert.equal((await wallets.getWallet(user.id, 'RUB')).bonus, 2400);
        await orders.cancelOrder(bonusOrder.id, user.id);
        assert.equal((await wallets.getWallet(user.id, 'RUB')).bonus, 2900);
        await assert.rejects(orders.cancelOrder(bonusOrder.id, user.id), /already/);
        const bonusRequest = await intercity.createRequest(user.id, { fromCity: ru.name, toCity: kz.name, paymentMethod: 'BONUSES', price: 600, date: new Date(Date.now() + 86400000).toISOString() });
        await prisma.$transaction(tx => intercity.chargePassengerBonusForAcceptedOffer(tx, user.id, bonusRequest, 600));
        assert.equal((await wallets.getWallet(user.id, 'RUB')).bonus, 2300);
        await prisma.$transaction(tx => intercity.refundPassengerBonusForCancelledRequest(tx, user.id, bonusRequest.id));
        await prisma.$transaction(tx => intercity.refundPassengerBonusForCancelledRequest(tx, user.id, bonusRequest.id));
        assert.equal((await wallets.getWallet(user.id, 'RUB')).bonus, 2900);
        await intercity.cancelRequest(user.id, bonusRequest.id);
        await prisma.driverProfile.create({ data: { userId: user.id } });
        const auctionDriver = await prisma.driverProfile.create({ data: { userId: recipient.id } });
        const auction = await orders.createOrder(user.id, { ...dto, requestType: 'CITY_AUCTION', paymentMethod: 'BONUSES' });
        assert.equal((await wallets.getWallet(user.id, 'RUB')).bonus, 2900);
        const offer = await prisma.orderOffer.create({ data: { orderId: auction.id, driverId: auctionDriver.id, price: 200 } });
        await orders.acceptOrderOffer(offer.id, user.id);
        assert.equal((await wallets.getWallet(user.id, 'RUB')).bonus, 2700);
        await assert.rejects(orders.acceptOrderOffer(offer.id, user.id));
        await orders.cancelOrder(auction.id, user.id);
        assert.equal((await wallets.getWallet(user.id, 'RUB')).bonus, 2900);
        const createCity = () => orders.createOrder(user.id, dto);
        const createIntercity = () => intercity.createRequest(user.id, { fromCity: ru.name, toCity: kz.name, price: 2000, date: new Date(Date.now() + 86400000).toISOString() });
        for (const creators of [[createCity, createCity], [createCity, createIntercity], [createIntercity, createIntercity]]) {
            const outcomes = await Promise.allSettled(creators.map(create => create()));
            assert.equal(outcomes.filter(x => x.status === 'fulfilled').length, 1);
            assert.equal(outcomes.find(x => x.status === 'rejected').reason.getStatus(), 409);
            const cityOrders = await prisma.order.findMany({ where: { passengerId: user.id, status: { notIn: ['COMPLETED', 'CANCELLED'] } } });
            const requests = await prisma.intercityRequest.findMany({ where: { passengerId: user.id, status: { notIn: ['COMPLETED', 'CANCELLED'] } } });
            assert.equal(cityOrders.length + requests.length, 1);
            for (const item of cityOrders) await orders.cancelOrder(item.id, user.id);
            for (const item of requests) await intercity.cancelRequest(user.id, item.id);
        }
        const topup = await wallets.createTopupRequest(user.id, { amount: 400, currency: 'RUB' }, 'DRIVER');
        assert.equal(topup.provider, 'MANUAL');
        assert.equal((await wallets.handleTopupPaymentCallback({ topupRequestId: topup.id, paid: true })).ignored, true);
        await admin.approveTopup(topup.id);
        await assert.rejects(admin.approveTopup(topup.id), /already/);
        assert.equal((await wallets.getWallet(user.id, 'RUB')).money, 2400);
        const payout = await wallets.createPayoutRequest(user.id, { amount: 1000, currency: 'RUB', cardNumber: '4400430154321098' }, 'DRIVER');
        assert.equal(payout.provider, 'MANUAL');
        assert.equal((await wallets.getWallet(user.id, 'RUB')).money, 1400);
        await admin.rejectPayout(payout.id);
        assert.equal((await wallets.getWallet(user.id, 'RUB')).money, 2400);
        await orders.applyDriverOrderCommissionDebit({ id: order.id, price: 500, currency: 'RUB', commissionAmount: 50, driver: { userId: user.id } });
        assert.equal((await wallets.getWallet(user.id, 'RUB')).money, 2350);
        await orders.applyDriverOrderCommissionDebit({ id: order.id, price: 500, currency: 'RUB', commissionAmount: 50, driver: { userId: user.id } });
        assert.equal((await wallets.getWallet(user.id, 'RUB')).money, 2350);
        await prisma.user.update({ where: { id: user.id }, data: { referredBy: recipient.refCode } });
        await orders.applyReferralCommissionBonuses({ id: order.id, currency: 'RUB', price: 500, commissionAmount: 50, passengerId: user.id });
        assert.equal((await wallets.getWallet(recipient.id, 'RUB')).bonus, 112.5);
        const bonusPayout = await wallets.createPayoutRequest(user.id, { amount: 2500, currency: 'RUB', cardNumber: '4400430154321098' }, 'DRIVER');
        assert.equal(bonusPayout.source, 'BONUS');
        assert.equal((await wallets.getWallet(user.id, 'RUB')).bonus, 400);
        await admin.rejectPayout(bonusPayout.id);
        assert.equal((await wallets.getWallet(user.id, 'RUB')).bonus, 2900);
        const race = await Promise.allSettled([
            wallets.transferBonusByPhone(recipient.id, user.phone, 100, 'RUB'),
            wallets.transferBonusByPhone(recipient.id, user.phone, 100, 'RUB'),
        ]);
        assert.equal(race.filter(result => result.status === 'fulfilled').length, 1);
        assert.equal((await wallets.getWallet(recipient.id, 'RUB')).bonus, 12.5);
        const unchanged = await prisma.wallet.findUnique({ where: { id: original.id } });
        assert.equal(unchanged.money, 7000);
        assert.equal(unchanged.bonus, 8000);
        const ledger = await wallets.getWallet(user.id, 'RUB');
        assert.ok(ledger.transactions.length > 0);
        assert.ok(ledger.transactions.every(row => row.currency === 'RUB'));
        assert.ok(ledger.topups.every(row => row.currency === 'RUB'));
        assert.ok(ledger.payouts.every(row => row.currency === 'RUB'));
        assert.equal((await wallets.getWallet(user.id, 'KZT')).transactions.length, 0);
        await admin.updateCity(ru.id, { countryCode: 'KZ' });
        assert.equal((await prisma.order.findUnique({ where: { id: order.id } })).currency, 'RUB');
        assert.equal((await prisma.intercityRequest.findUnique({ where: { id: request.id } })).currency, 'RUB');
    } finally {
        await prisma.$disconnect();
    }
});
