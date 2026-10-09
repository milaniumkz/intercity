// Read-only Firebase verification: validate_only never delivers a notification.
const { createSign } = require('node:crypto');
const { readFileSync } = require('node:fs');

async function verifyFirebaseConfiguration(env = process.env, transport = fetch) {
  const configured = Boolean(env.FIREBASE_SERVICE_ACCOUNT_JSON || env.GOOGLE_APPLICATION_CREDENTIALS);
  if (!configured) return { configured: false, verified: false };
  try {
    const account = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON || readFileSync(env.GOOGLE_APPLICATION_CREDENTIALS, 'utf8'));
    if (account.project_id !== 'inter-city-pkzpps' || !account.client_email || !account.private_key) {
      return { configured: true, verified: false, error: 'Wrong project or incomplete service account' };
    }
    const now = Math.floor(Date.now() / 1000);
    const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
    const unsigned = `${encode({ alg: 'RS256', typ: 'JWT' })}.${encode({ iss: account.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600 })}`;
    const signature = createSign('RSA-SHA256').update(unsigned).sign(account.private_key, 'base64url');
    const auth = await transport('https://oauth2.googleapis.com/token', { method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${signature}` }),
      signal: AbortSignal.timeout(10000) });
    if (!auth.ok) return { configured: true, verified: false, error: `OAuth HTTP ${auth.status}` };
    const { access_token } = await auth.json();
    if (!access_token) return { configured: true, verified: false, error: 'OAuth returned no access token' };
    const check = await transport(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${access_token}` },
      body: JSON.stringify({ validate_only: true, message: { topic: 'intercity_configuration_check',
        notification: { title: 'Configuration validation', body: 'Validation only; no delivery' } } }),
      signal: AbortSignal.timeout(10000),
    });
    return { configured: true, verified: check.ok, ...(check.ok ? {} : { error: `FCM validation HTTP ${check.status}` }) };
  } catch (_) { return { configured: true, verified: false, error: 'Credential format or network error' }; }
}
module.exports = { verifyFirebaseConfiguration };
if (process.argv.includes('--run')) {
  verifyFirebaseConfiguration().then(result => console.log('Firebase configuration verification: ' + JSON.stringify(result)));
}
