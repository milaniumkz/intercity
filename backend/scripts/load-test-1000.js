/*
  INTERCITY load test (1000 concurrent virtual users)
  Usage:
    API_URL=http://localhost:3000/api node scripts/load-test-1000.js
*/

const API_URL = process.env.API_URL || 'http://localhost:3000/api';
const USERS = Number(process.env.LOAD_USERS || 1000);
const PASSWORD = process.env.LOAD_PASSWORD || '123456';
const PHONE_PREFIX = process.env.LOAD_PHONE_PREFIX || '+7999';

function percentile(values, p) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const idx = Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length));
  return sorted[idx];
}

async function request(path, { method = 'GET', token, body, headers = {} } = {}) {
  const start = performance.now();
  try {
    const res = await fetch(`${API_URL}${path}`, {
      method,
      headers: {
        'content-type': 'application/json',
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...headers,
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    const elapsedMs = performance.now() - start;
    let data = null;
    try {
      data = await res.json();
    } catch {
      data = null;
    }
    return { ok: res.ok, status: res.status, elapsedMs, data };
  } catch (error) {
    return { ok: false, status: 0, elapsedMs: performance.now() - start, error };
  }
}

async function runTasks(name, taskFactories) {
  const started = Date.now();
  const results = await Promise.all(taskFactories.map((task) => task()));
  const elapsedTotal = Date.now() - started;
  const latencies = results.map((r) => r.elapsedMs);
  const okCount = results.filter((r) => r.ok).length;
  const failCount = results.length - okCount;
  const statuses = results.reduce((acc, r) => {
    const key = String(r.status);
    acc[key] = (acc[key] || 0) + 1;
    return acc;
  }, {});

  const report = {
    name,
    total: results.length,
    ok: okCount,
    failed: failCount,
    successRate: ((okCount / Math.max(1, results.length)) * 100).toFixed(2) + '%',
    rps: (results.length / Math.max(1, elapsedTotal / 1000)).toFixed(2),
    p50ms: percentile(latencies, 50).toFixed(2),
    p95ms: percentile(latencies, 95).toFixed(2),
    p99ms: percentile(latencies, 99).toFixed(2),
    maxMs: Math.max(...latencies).toFixed(2),
    statuses,
  };

  console.log('\n=== ' + name + ' ===');
  console.table(report);
  return { results, report };
}

function phoneByIndex(i) {
  const suffix = String(i).padStart(7, '0');
  return `${PHONE_PREFIX}${suffix}`;
}

async function ensureUsers() {
  console.log(`Preparing ${USERS} users via /auth/register ...`);
  const queue = Array.from({ length: USERS }, (_, i) => i + 1);
  const workers = 30;

  async function worker() {
    while (queue.length) {
      const index = queue.shift();
      if (!index) return;
      const phone = phoneByIndex(index);
      await request('/auth/register', {
        method: 'POST',
        body: {
          phone,
          password: PASSWORD,
          name: `LoadUser ${index}`,
          lat: 43.222,
          lng: 76.8512,
        },
      });
    }
  }

  await Promise.all(Array.from({ length: workers }, () => worker()));
}

async function main() {
  console.log('API_URL:', API_URL);
  console.log('USERS:', USERS);

  await ensureUsers();

  const loginTasks = Array.from({ length: USERS }, (_, i) => () => {
    const phone = phoneByIndex(i + 1);
    return request('/auth/login', {
      method: 'POST',
      body: { phone, password: PASSWORD },
      headers: { 'x-forwarded-for': `10.0.0.${(i % 250) + 1}` },
    });
  });

  const login = await runTasks('Login burst (1000 concurrent)', loginTasks);
  const tokens = login.results
    .filter((r) => r.ok && r.data?.accessToken)
    .map((r) => r.data.accessToken);

  const meTasks = tokens.slice(0, USERS).map((token, i) => () =>
    request('/me', {
      token,
      headers: { 'x-forwarded-for': `10.0.1.${(i % 250) + 1}` },
    })
  );
  await runTasks('GET /me burst', meTasks);

  const adminLogin = await request('/auth/login', {
    method: 'POST',
    body: { phone: '+70000000000', password: '123456' },
  });
  if (!adminLogin.ok || !adminLogin.data?.accessToken) {
    console.log('Admin login failed, skip admin collection burst');
    return;
  }

  const adminToken = adminLogin.data.accessToken;
  const collectionTasks = Array.from({ length: USERS }, (_, i) => () =>
    request('/admin/collections/User?take=50&skip=0', {
      token: adminToken,
      headers: { 'x-forwarded-for': `10.0.2.${(i % 250) + 1}` },
    })
  );
  await runTasks('Admin collections burst', collectionTasks);

  console.log('\nLoad test completed.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
