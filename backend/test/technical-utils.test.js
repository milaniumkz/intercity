const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
    safeMessage,
    canonical,
    pageArgs,
} = require('../dist/src/technical/technical-utils');
test('technical collector redacts common credentials and rejects unbounded pagination', () => {
    for (const raw of [
        'password=hidden-value',
        '"refreshToken":"hidden-value"',
        "'api_key': 'hidden-value'",
        'Authorization: Bearer hidden-value',
        'https://private.invalid/?token=hidden-value',
    ])
        assert.ok(!safeMessage(raw).includes('hidden-value'), raw);
    assert.throws(() => pageArgs({ page: 0 }));
    assert.throws(() => pageArgs({ limit: 10001 }));
    assert.deepEqual(pageArgs({ page: 2, limit: 25 }), { skip: 25, take: 25 });
});
test('audit canonicalization is independent of JSONB key order', () => {
    assert.equal(
        canonical({ z: { b: 2, a: 1 }, a: [2, 1] }),
        canonical({ a: [2, 1], z: { a: 1, b: 2 } }),
    );
    assert.notEqual(canonical({ a: [1, 2] }), canonical({ a: [2, 1] }));
});
