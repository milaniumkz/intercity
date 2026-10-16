const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { PrismaClient } = require('@prisma/client');
const { DriverEarningsService, earningsMonth } = require('../dist/src/driver/driver-earnings.service');

test('earnings month uses exclusive Kazakhstan month boundaries and rejects malformed input', () => {
  const { start, end } = earningsMonth('2026-10');
  assert.equal(start.toISOString(), '2026-09-30T19:00:00.000Z');
  assert.equal(end.toISOString(), '2026-10-31T19:00:00.000Z');
  assert.equal(earningsMonth('2026-12').end.toISOString(), '2026-12-31T19:00:00.000Z');
  for (const period of ['2026-00', '2026-13', '2026-10-01', '', ['2026-10']]) assert.throws(() => earningsMonth(period));
});

test('driver earnings reconcile actual commissions, settled cards, tax records, ownership and currencies', {
  skip: !process.env.DISPATCH_TEST_DATABASE_URL,
}, async () => {
  const url = new URL(process.env.DISPATCH_TEST_DATABASE_URL);
  assert.equal(url.hostname, '127.0.0.1');
  assert.equal(url.pathname, '/dispatch_test');
  const p = new PrismaClient({ datasources: { db: { url: url.toString() } } });
  const service = new DriverEarningsService(p), key = `earnings:${randomUUID()}`;
  const users = [], orders = [], requests = [], offers = [];
  const at = new Date('2026-10-10T12:00:00Z'), period = '2026-10';
  async function user(driver = false) {
    const u = await p.user.create({ data: { phone: `${key}:${users.length}`, name: 'Earnings fixture', password: 'test',
      refCode: randomUUID(), refLink: 'test', wallet: { create: {} }, ...(driver ? { driverProfile: { create: {} } } : {}) },
      include: { wallet: true, driverProfile: true } });
    users.push(u.id); return u;
  }
  try {
    const driver = await user(true), other = await user(true), passenger = await user();
    await p.taxProfile.create({ data: { userId: driver.id, kind: 'SELF_EMPLOYED', countryCode: 'KZ', status: 'VERIFIED',
      consentVersion: 'test', consentAt: at } });
    async function order(price, extra = {}) {
      const row = await p.order.create({ data: { passengerId: passenger.id, driverId: driver.driverProfile.id,
        fromLat: 50, fromLng: 80, toLat: 51, toLng: 81, fromAddress: 'Test A', toAddress: 'Test B',
        price, currency: 'KZT', paymentMethod: 'CASH', status: 'COMPLETED', completedAt: at, ...extra } });
      orders.push(row.id); return row;
    }
    const cash = await order(10000, { completedAt: new Date('2026-09-30T19:00:00Z') }); // Included boundary.
    const settled = await order(2000, { paymentMethod: 'CARD' });
    const pending = await order(3000, { paymentMethod: 'CARD' });
    const refunded = await order(500, { paymentMethod: 'CARD' });
    const legacy = await order(100, { completedAt: null, updatedAt: at });
    await order(90000, { completedAt: new Date('2026-10-31T19:00:00Z') }); // Excluded boundary.
    await order(80000, { status: 'CANCELLED' });
    await order(70000, { driverId: other.driverProfile.id });
    await order(600, { currency: 'RUB' });
    const request = await p.intercityRequest.create({ data: { passengerId: passenger.id, selectedDriverId: driver.id,
      fromCity: 'Test A', toCity: 'Test B', price: 900, date: at, status: 'COMPLETED', completedAt: at, currency: 'KZT' } });
    requests.push(request.id);
    const offer = await p.intercityOffer.create({ data: { requestId: request.id, driverId: driver.id, price: 4000, seats: 1 } });
    offers.push(offer.id);
    await p.intercityRequest.update({ where: { id: request.id }, data: { selectedOfferId: offer.id } });
    await p.tripCardPayment.create({ data: { id: `CITY:${settled.id}`, kind: 'CITY', tripId: settled.id,
      passengerId: passenger.id, driverUserId: driver.id, cardId: 'test-only', amount: 2000, currency: 'KZT',
      status: 'SETTLED', earningsCredited: true } });
    await p.tripCardPayment.create({ data: { id: `CITY:${refunded.id}`, kind: 'CITY', tripId: refunded.id,
      passengerId: passenger.id, driverUserId: driver.id, cardId: 'test-only', amount: 500, currency: 'KZT',
      status: 'REFUNDED', refundedAt: at } });
    const ledger = async (type, amount, extra = {}) => p.walletTransaction.create({ data: {
      walletId: driver.wallet.id, type, amount, direction: 'DEBIT', currency: 'KZT', ...extra } });
    await ledger('ORDER_COMMISSION_DEBIT', 1000, { orderId: cash.id });
    await ledger('DEBIT_INTERCITY_ACCEPTED_REQUEST', 100, { intercityRequestId: request.id, createdAt: new Date('2026-09-01') });
    await ledger('DEBIT_INTERCITY_COMPLETED_REQUEST', 200, { intercityRequestId: request.id });
    await ledger('ROUTE_TOP_PURCHASE', 50000); // Not a commission.
    await ledger('ORDER_COMMISSION_DEBIT', 60000, { walletId: other.wallet.id, orderId: cash.id });
    await p.taxIncomeEntry.createMany({ data: [
      { eventKey: `${key}:cash`, ownerKey: driver.id, sourceKind: 'CITY', sourceId: cash.id, currency: 'KZT',
        occurredAt: at, period, profileKind: 'SELF_EMPLOYED', status: 'ACCOUNTED', gross: 10000,
        opv: 100, opvr: 100, so: 100, osms: 100, withheld: 300 },
      { eventKey: `${key}:referral`, ownerKey: driver.id, sourceKind: 'REFERRAL', sourceId: key, currency: 'KZT',
        occurredAt: at, period, profileKind: 'SELF_EMPLOYED', status: 'ACCOUNTED', gross: 1000,
        opv: 10, opvr: 10, so: 10, osms: 10, withheld: 40 },
      { eventKey: `${key}:review`, ownerKey: driver.id, sourceKind: 'CITY', sourceId: legacy.id, currency: 'KZT',
        occurredAt: at, period, profileKind: 'SELF_EMPLOYED', status: 'REVIEW', gross: 100, opv: 999 },
    ] });
    await p.taxRemittance.create({ data: { ownerKey: driver.id, period, component: 'OPV', amount: 50,
      reference: key, paidAt: at, recordedBy: 'test-only', note: 'Test remittance' } });
    const result = await service.summary(driver.id, period, 'KZT');
    assert.equal(result.trips.total, 6);
    assert.equal(result.trips.legacyDates, 1);
    assert.equal(result.gross.toString(), '19600'); // Uses agreed intercity offer, not request price.
    assert.equal(result.cash.toString(), '14100');
    assert.equal(result.card.toString(), '2000');
    assert.equal(result.pendingCard.toString(), '3000');
    assert.equal(result.refundedCard.toString(), '500');
    assert.equal(result.commission.toString(), '1300');
    assert.equal(result.net.toString(), '14400'); // Received - actual commissions - ride social liability.
    assert.equal(result.tax.accrued.toString(), '440');
    assert.equal(result.tax.rideAccrued.toString(), '400');
    assert.equal(result.tax.referralAccrued.toString(), '40');
    assert.equal(result.tax.withheld.toString(), '340');
    assert.equal(result.tax.debt.toString(), '100');
    assert.equal(result.tax.remitted.toString(), '50');
    assert.equal(result.tax.payable.toString(), '390');
    assert.equal(result.tax.reviewCount, 1);
    assert.equal(JSON.stringify(result).includes('iin'), false);
    const rub = await service.summary(driver.id, period, 'RUB');
    assert.equal(rub.gross.toString(), '600');
    assert.equal(rub.tax.showSocialPayments, false);
    assert.equal(rub.tax.remitted.toString(), '0');
    const empty = await service.summary(driver.id, '2026-08', 'KZT');
    assert.equal(empty.trips.total, 0); assert.equal(empty.gross.toString(), '0');
    await p.taxProfile.update({ where: { userId: driver.id }, data: { kind: 'INDIVIDUAL' } });
    assert.equal((await service.summary(driver.id, period, 'KZT')).tax.showSocialPayments, true);
    assert.equal((await service.summary(driver.id, '2026-08', 'KZT')).tax.showSocialPayments, false);
    await assert.rejects(service.summary(passenger.id, period), /Профиль водителя/);
    await assert.rejects(service.summary(driver.id, period, 'USD'), /KZT или RUB/);
  } finally {
    await p.taxIncomeEntry.deleteMany({ where: { ownerKey: { in: users } } });
    await p.taxRemittance.deleteMany({ where: { ownerKey: { in: users } } });
    await p.tripCardPayment.deleteMany({ where: { driverUserId: { in: users } } });
    await p.walletTransaction.deleteMany({ where: { wallet: { userId: { in: users } } } });
    await p.intercityOffer.deleteMany({ where: { id: { in: offers } } });
    await p.intercityRequest.deleteMany({ where: { id: { in: requests } } });
    await p.order.deleteMany({ where: { id: { in: orders } } });
    await p.driverProfile.deleteMany({ where: { userId: { in: users } } });
    await p.wallet.deleteMany({ where: { userId: { in: users } } });
    await p.user.deleteMany({ where: { id: { in: users } } });
    await p.$disconnect();
  }
});
