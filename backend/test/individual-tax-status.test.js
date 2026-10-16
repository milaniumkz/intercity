const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { validateSync } = require('class-validator');
const { PrismaClient } = require('@prisma/client');
const { DeclareTaxProfileDto } = require('../dist/src/tax/tax.dto');
const { TaxService } = require('../dist/src/tax/tax.service');
const { recordTaxIncome, kazakhstanPeriod } = {
  ...require('../dist/src/tax/tax-ledger'),
  ...require('../dist/src/tax/kz-social-calculator'),
};
const { canWorkInKazakhstan } = require('../dist/src/tax/tax-profile-policy');
const { WalletService } = require('../dist/src/wallet/wallet.service');
const { DriverService } = require('../dist/src/driver/driver.service');

test('individual declaration needs no IIN or activity; registered regimes keep their validation', () => {
  for (const kind of ['INDIVIDUAL', 'SELF_EMPLOYED', 'IE']) {
    const dto = Object.assign(new DeclareTaxProfileDto(), { countryCode: 'KZ', kind, consent: true });
    assert.equal(validateSync(dto).length === 0, kind === 'INDIVIDUAL');
  }
});

test('KZ individuals work without verification, while self-employed and IE still require approval', () => {
  assert.equal(canWorkInKazakhstan({ countryCode: 'KZ', kind: 'INDIVIDUAL', status: 'DECLARED', activities: [] }), true);
  assert.equal(canWorkInKazakhstan(null), false);
  for (const kind of ['SELF_EMPLOYED', 'IE']) {
    for (const status of ['PENDING', 'REJECTED', 'VERIFIED']) {
      assert.equal(canWorkInKazakhstan({ countryCode: 'KZ', kind, status, activities: ['49320'] }), status === 'VERIFIED');
    }
    assert.equal(canWorkInKazakhstan({ countryCode: 'KZ', kind, status: 'VERIFIED', activities: [] }), false);
  }
});

test('passenger referral accruals and payouts need no profile; individual drivers need no tax approval', {
  skip: !process.env.DISPATCH_TEST_DATABASE_URL,
}, async () => {
  const url = new URL(process.env.DISPATCH_TEST_DATABASE_URL);
  assert.equal(url.hostname, '127.0.0.1');
  assert.equal(url.pathname, '/dispatch_test');
  const p = new PrismaClient({ datasources: { db: { url: url.toString() } } });
  const tax = new TaxService(p);
  const key = `individual-test:${randomUUID()}`, users = [];
  const settingKeys = ['kzTaxEnabled', 'kzTaxOperatorReference', 'kzTaxReferralContractReference', 'referralMinPayoutKzt', `kzTaxPolicy${new Date().getUTCFullYear()}`];
  const previous = await p.appSettings.findMany({ where: { key: { in: settingKeys } } });
  const oldFetch = global.fetch;
  global.fetch = async () => ({ ok: false, json: async () => ({}) }); // Never call a real payment provider.
  let city;
  const createUser = async () => {
    const u = await p.user.create({ data: { phone: `${key}:${users.length}`, password: 'test-only', name: key,
      refCode: randomUUID(), refLink: 'test', wallet: { create: { bonus: 321 } } }, include: { wallet: true } });
    users.push(u.id);
    return u;
  };
  const credit = (userId, id, sourceKind = 'REFERRAL', gross = 7500) => p.$transaction(tx => recordTaxIncome(tx, {
    key: `${key}:${id}`, userId, sourceKind, sourceId: id, gross, currency: 'KZT', occurredAt: new Date(),
  }));
  try {
    // Passenger money does not depend on the self-employed operator rollout.
    await p.appSettings.upsert({ where: { key: 'kzTaxEnabled' }, create: { key: 'kzTaxEnabled', value: 'false' }, update: { value: 'false' } });
    const passenger = await createUser();
    await Promise.all([credit(passenger.id, 'passenger'), credit(passenger.id, 'passenger')]);
    assert.equal(await p.taxProfile.count({ where: { userId: passenger.id } }), 0);
    assert.equal((await p.wallet.findUnique({ where: { userId: passenger.id } })).referralMoney.toString(), '7500');
    assert.equal((await p.taxIncomeEntry.findUnique({ where: { eventKey: `${key}:passenger` } })).withheld.toString(), '0');
    await p.taxIncomeEntry.create({ data: { eventKey: `${key}:pending`, ownerKey: passenger.id, sourceKind: 'REFERRAL',
      sourceId: 'old-pending', currency: 'KZT', occurredAt: new Date(), period: kazakhstanPeriod(new Date()), gross: 500,
      status: 'REVIEW', reviewReason: 'PROFILE_VERIFICATION' } });
    await tax.summary(passenger.id);
    const summary = await tax.summary(passenger.id);
    assert.equal(summary.referralBalance.toString(), '8000');
    assert.equal(summary.pendingReferral.toString(), '0');
    assert.equal(await p.taxAccountingIdentity.count({ where: { ownerKey: passenger.id } }), 0);
    // Even a legacy rejected tax profile cannot block a passenger's payout.
    await p.taxProfile.create({ data: { userId: passenger.id, kind: 'IE', status: 'REJECTED',
      consentVersion: 'legacy', consentAt: new Date() } });
    const payouts = new WalletService(p, { collectDebt: () => { throw Error('No passenger tax gate'); } });
    const dto = { source: 'REFERRAL', currency: 'KZT', amount: 5000, cardNumber: '4000000000000002' };
    await assert.rejects(payouts.createPayoutRequest(passenger.id, { ...dto, amount: 4999 }), /Минимальная/);
    const results = await Promise.allSettled([payouts.createPayoutRequest(passenger.id, dto), payouts.createPayoutRequest(passenger.id, dto)]);
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    const balance = await p.wallet.findUnique({ where: { userId: passenger.id } });
    assert.equal(balance.referralMoney.toString(), '3000');
    assert.equal(balance.bonus, 321);

    const driver = await createUser();
    const profile = await tax.declare(driver.id, { countryCode: 'KZ', kind: 'INDIVIDUAL', consent: true });
    assert.equal(profile.status, 'DECLARED');
    assert.equal(profile.iinLast4, null);
    assert.equal(profile.verifiedAt, null);
    await credit(driver.id, 'individual-before-driver-profile');
    await assert.rejects(tax.verify(driver.id, { status: 'VERIFIED', quickApproval: true }, 'test-admin'), /не требуется/);
    city = await p.city.create({ data: { name: key, countryCode: 'KZ', lat: 50, lng: 80 } });
    const dp = await p.driverProfile.create({ data: { userId: driver.id, status: 'APPROVED', online: { create: { cityId: city.id, isOnline: true } } } });
    await credit(driver.id, 'individual-before-rollout');
    await tax.configure({ enabled: true, operatorReference: '', referralContractReference: '', minPayout: 5000,
      year: new Date().getUTCFullYear().toString(), mrp: 4325, mzp: 85000, policyReference: 'TEST annual policy' });
    assert.equal((await p.driverOnline.findUnique({ where: { driverId: dp.id } })).isOnline, true);
    const drivers = new DriverService(p, {}, { publish() {} }, {}, {}, { collectDebt() { throw Error('No individual tax gate'); } });
    drivers.ensureDriverActivityState = async () => ({ activityScore: 100 });
    drivers.ensureDriverCanStayOnline = async () => {};
    assert.equal((await drivers.setOnline(driver.id, { isOnline: true, cityId: city.id })).isOnline, true);
    const ride = await credit(driver.id, 'individual-ride', 'CITY', 10000);
    assert.equal(ride.status, 'ACCOUNTED');
    assert.equal(ride.opv.toString(), '0');
    assert.equal(ride.withheld.toString(), '0');
    await credit(driver.id, 'individual-referral');
    const individualPayout = await payouts.createPayoutRequest(driver.id, dto);
    assert.equal(individualPayout.source, 'REFERRAL');
    assert.equal(await p.taxAccountingIdentity.count({ where: { ownerKey: driver.id } }), 0);
    assert.ok((await tax.exportRegistry(kazakhstanPeriod(new Date()))).csv.includes('INDIVIDUAL'));
  } finally {
    global.fetch = oldFetch;
    await p.taxIncomeEntry.deleteMany({ where: { ownerKey: { in: users } } });
    await p.taxAccountingIdentity.deleteMany({ where: { ownerKey: { in: users } } });
    const wallets = await p.wallet.findMany({ where: { userId: { in: users } } });
    const ids = wallets.map(w => w.id);
    await p.walletTransaction.deleteMany({ where: { walletId: { in: ids } } });
    await p.payoutRequest.deleteMany({ where: { walletId: { in: ids } } });
    await p.driverOnline.deleteMany({ where: { driver: { userId: { in: users } } } });
    await p.driverProfile.deleteMany({ where: { userId: { in: users } } });
    await p.wallet.deleteMany({ where: { userId: { in: users } } });
    await p.user.deleteMany({ where: { id: { in: users } } });
    if (city) await p.city.delete({ where: { id: city.id } });
    await p.appSettings.deleteMany({ where: { key: { in: settingKeys } } });
    for (const row of previous) await p.appSettings.create({ data: { key: row.key, value: row.value } });
    await p.$disconnect();
  }
});
