const { test } = require('node:test');
const assert = require('node:assert/strict');
const { requireNoActivePassengerOrder } = require('../dist/src/common/active-passenger-order');

for (const type of ['CITY', 'INTERCITY']) {
    test(`rejects new orders while a ${type} order is active`, async () => {
        let locked = false;
        const tx = {
            $queryRaw: async (_sql, userId) => { assert.equal(userId, 'account'); locked = true; return [{ id: userId }]; },
            order: { findFirst: async ({ where }) => { assert.ok(locked); assert.equal(where.passengerId, 'account'); assert.deepEqual(where.status.notIn, ['COMPLETED', 'CANCELLED']); return type === 'CITY' ? { id: 'existing' } : null; } },
            intercityRequest: { findFirst: async ({ where }) => { assert.ok(locked); assert.deepEqual(where.status.notIn, ['COMPLETED', 'CANCELLED']); return { id: 'existing' }; } },
        };
        await assert.rejects(requireNoActivePassengerOrder(tx, 'account'), e => {
            assert.equal(e.getStatus(), 409);
            assert.equal(e.getResponse().activeOrderId, 'existing');
            assert.equal(e.getResponse().activeOrderType, type);
            return true;
        });
    });
}

test('allows creation when both order tables have no active order', async () => {
    await requireNoActivePassengerOrder({
        $queryRaw: async () => [{ id: 'account' }],
        order: { findFirst: async () => null },
        intercityRequest: { findFirst: async () => null },
    }, 'account');
});
