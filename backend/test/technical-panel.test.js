const { test } = require('node:test');
const assert = require('node:assert/strict');
const { PrismaClient } = require('@prisma/client');
const bcrypt = require('bcrypt');
const sharp = require('sharp');
const { randomUUID, randomBytes } = require('crypto');
const fs = require('fs/promises');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const net = require('net');
const database = process.env.TECH_TEST_DATABASE_URL;
test(
    'technical panel: real auth, permissions, events, photos, support, notifications and audit',
    { skip: !database, timeout: 120000 },
    async (t) => {
        const dburl = new URL(database);
        assert.equal(dburl.hostname, '127.0.0.1');
        assert.equal(dburl.pathname, '/technical_panel_test');
        const p = new PrismaClient({ datasources: { db: { url: database } } }),
            dir = path.join(
                os.tmpdir(),
                'intercity-technical-panel-integration',
            );
        const fixture = randomUUID(),
            password = randomBytes(20).toString('hex');
        const login = 'test-' + fixture;
        let child;
        let output = '';
        const srv = net.createServer();
        await new Promise((r) => srv.listen(0, '127.0.0.1', r));
        const port = srv.address().port;
        await new Promise((r) => srv.close(r));
        const base = 'http://127.0.0.1:' + port;
        async function request(route, body, headers = {}) {
            const res = await fetch(base + '/api/' + route, {
                method: body === undefined ? 'GET' : 'POST',
                headers:
                    body === undefined
                        ? headers
                        : { 'Content-Type': 'application/json', ...headers },
                body: body === undefined ? undefined : JSON.stringify(body),
            });
            return {
                status: res.status,
                headers: res.headers,
                data: await res.json().catch(() => null),
            };
        }
        try {
            const owner = await p.techAccount.create({
                data: {
                    login,
                    passwordHash: await bcrypt.hash(password, 4),
                    permissions: [
                        'events',
                        'personal',
                        'originals',
                        'users',
                        'danger',
                        'settings',
                    ],
                },
            });
            const reader = await p.techAccount.create({
                data: {
                    login: 'reader-' + fixture,
                    passwordHash: await bcrypt.hash(password, 4),
                    permissions: ['events'],
                },
            });
            child = spawn(process.execPath, ['dist/src/main.js'], {
                cwd: path.resolve(__dirname, '..'),
                env: {
                    ...process.env,
                    NODE_ENV: 'test',
                    DATABASE_URL: database,
                    PORT: String(port),
                    JWT_SECRET: randomBytes(32).toString('hex'),
                    JWT_REFRESH_SECRET: randomBytes(32).toString('hex'),
                    TECH_STORAGE_DIR: dir,
                    UPLOAD_DIR: path.join(dir, 'uploads'),
                },
            });
            child.stdout.on(
                'data',
                (d) => (output = (output + d).slice(-15000)),
            );
            child.stderr.on(
                'data',
                (d) => (output = (output + d).slice(-15000)),
            );
            let ready = false;
            for (let i = 0; i < 120; i++) {
                try {
                    const r = await fetch(base + '/api/technical/panel/');
                    if (r.ok) {
                        ready = true;
                        break;
                    }
                } catch {}
                if (child.exitCode !== null)
                    throw Error('Backend exited: ' + output);
                await new Promise((r) => setTimeout(r, 250));
            }
            assert.ok(ready, 'server must become ready: ' + output);
            const techHeaders = { 'X-Tech-Request': '1' };
            await t.test(
                'separate login, CSRF and ordinary JWT rejection',
                async () => {
                    assert.equal(
                        (await request('technical/overview')).status,
                        401,
                    );
                    assert.equal(
                        (await request('technical/login', { login, password }))
                            .status,
                        403,
                    );
                    assert.equal(
                        (
                            await request(
                                'technical/login',
                                { login, password: 'incorrect' },
                                techHeaders,
                            )
                        ).status,
                        401,
                    );
                    const auth = await request(
                        'technical/login',
                        { login, password },
                        techHeaders,
                    );
                    assert.equal(auth.status, 201);
                    techHeaders.Cookie = auth.headers
                        .get('set-cookie')
                        .split(';')[0];
                    assert.ok(
                        auth.headers.get('set-cookie').includes('HttpOnly'),
                    );
                    assert.equal(
                        (await request('technical/me', undefined, techHeaders))
                            .data.login,
                        login,
                    );
                    assert.equal(
                        (
                            await request(
                                'technical/logout',
                                {},
                                {
                                    ...techHeaders,
                                    Origin: 'https://attacker.invalid',
                                },
                            )
                        ).status,
                        403,
                    );
                },
            );
            let a, b, jwtA, jwtB;
            async function register(suffix) {
                const r = await request('auth/register', {
                    phone: '+7' + String(Date.now()).slice(-9) + suffix,
                    password: 'App-password-123',
                    name: 'Technical fixture ' + suffix,
                });
                assert.equal(r.status, 201, JSON.stringify(r.data));
                return r.data;
            }
            await t.test('app users and exact attribution', async () => {
                a = await register('1');
                b = await register('2');
                jwtA = a.accessToken;
                jwtB = b.accessToken;
                assert.equal(
                    (
                        await request('technical/me', undefined, {
                            Authorization: 'Bearer ' + jwtA,
                        })
                    ).status,
                    401,
                );
                await request(
                    'driver/profile',
                    { carModel: 'Test vehicle', carNumber: 'TEST123' },
                    {
                        Authorization: 'Bearer ' + jwtA,
                        'X-Client-Session': 'fixture-session-A',
                    },
                );
                await request(
                    'driver/profile',
                    { carModel: 'Test vehicle', carNumber: 'TEST123' },
                    {
                        Authorization: 'Bearer ' + jwtB,
                        'X-Client-Session': 'fixture-session-B',
                    },
                );
                const loginResult = await request('auth/login', {
                    phone: a.user.phone,
                    password: 'App-password-123',
                });
                assert.equal(loginResult.status, 201);
                jwtA = loginResult.data.accessToken;
            });
            let accepted, rejected, profile;
            await t.test(
                'accepted and rejected real photos, safe storage and exact event files',
                async () => {
                    profile = await p.driverProfile.findUnique({
                        where: { userId: a.user.id },
                    });
                    assert.ok(profile);
                    async function upload(bytes, name, token) {
                        const f = new FormData();
                        f.append('docType', 'passport');
                        f.append(
                            'file',
                            new Blob([bytes], { type: 'image/png' }),
                            name,
                        );
                        const r = await fetch(
                            base + '/api/driver/docs/upload',
                            {
                                method: 'POST',
                                headers: {
                                    Authorization: 'Bearer ' + token,
                                    'X-Client-Session': 'fixture-session-A',
                                },
                                body: f,
                            },
                        );
                        return {
                            status: r.status,
                            data: await r.json(),
                            requestId: r.headers.get('x-request-id'),
                        };
                    }
                    const noise = randomBytes(256 * 256 * 3);
                    const valid = await sharp(noise, {
                        raw: { width: 256, height: 256, channels: 3 },
                    })
                        .png()
                        .toBuffer();
                    const ok = await upload(valid, 'photo.png', jwtA);
                    assert.equal(ok.status, 201, JSON.stringify(ok.data));
                    assert.equal(ok.data.quality, 'ACCEPT');
                    accepted = ok.data.url.split('/').pop();
                    const blank = await sharp({
                        create: {
                            width: 256,
                            height: 256,
                            channels: 3,
                            background: '#eeeeee',
                        },
                    })
                        .png()
                        .toBuffer();
                    const bad = await upload(blank, 'blank.png', jwtA);
                    assert.equal(bad.status, 400);
                    rejected = await p.techFile.findFirst({
                        where: { requestId: bad.requestId },
                    });
                    assert.equal(rejected.verdict, 'REJECT');
                    assert.ok(await fs.stat(path.join(dir, rejected.path)));
                    assert.notEqual(
                        (
                            await p.driverProfile.findUnique({
                                where: { id: profile.id },
                            })
                        ).passportUrl,
                        '/api/driver/docs/files/' + rejected.id,
                    );
                    assert.equal(
                        (
                            await fetch(
                                base + '/api/driver/docs/files/' + accepted,
                                {
                                    headers: {
                                        Authorization: 'Bearer ' + jwtB,
                                    },
                                },
                            )
                        ).status,
                        403,
                    );
                    assert.equal(
                        (
                            await fetch(
                                base + '/api/driver/docs/files/' + accepted,
                                {
                                    headers: {
                                        Authorization: 'Bearer ' + jwtA,
                                    },
                                },
                            )
                        ).status,
                        200,
                    );
                    assert.equal(
                        (
                            await upload(
                                Buffer.from('<script>bad</script>'),
                                'bad.png',
                                jwtA,
                            )
                        ).status,
                        400,
                    );
                    const events = await request(
                        'technical/events?requestId=' + ok.requestId,
                        undefined,
                        techHeaders,
                    );
                    const finished = events.data.items.find(
                        (x) => x.stage === 'FINISH' && x.status === 201,
                    );
                    assert.ok(finished);
                    const detail = await request(
                        'technical/events/' + finished.id,
                        undefined,
                        techHeaders,
                    );
                    assert.equal(detail.data.actionFiles.length, 1);
                    assert.equal(detail.data.actionFiles[0].id, accepted);
                },
            );
            await t.test(
                'legacy files reject foreign IDs and encoded traversal before static delivery',
                async () => {
                    const peer = await p.driverProfile.findUnique({
                        where: { userId: b.user.id },
                    });
                    const image = await sharp({
                        create: {
                            width: 32,
                            height: 32,
                            channels: 3,
                            background: '#cccccc',
                        },
                    })
                        .png()
                        .toBuffer();
                    for (const profileId of [profile.id, peer.id]) {
                        await fs.mkdir(path.join(dir, 'uploads', profileId), {
                            recursive: true,
                        });
                        await fs.writeFile(
                            path.join(dir, 'uploads', profileId, 'legacy.png'),
                            image,
                        );
                    }
                    assert.equal(
                        (
                            await fetch(
                                base + '/uploads/' + peer.id + '/legacy.png',
                                {
                                    headers: {
                                        Authorization: 'Bearer ' + jwtB,
                                    },
                                },
                            )
                        ).status,
                        200,
                    );
                    assert.equal(
                        (
                            await fetch(
                                base + '/uploads/' + peer.id + '/legacy.png',
                                {
                                    headers: {
                                        Authorization: 'Bearer ' + jwtA,
                                    },
                                },
                            )
                        ).status,
                        403,
                    );
                    assert.equal(
                        (
                            await fetch(
                                base + '/uploads/' + peer.id + '/legacy.png',
                            )
                        ).status,
                        403,
                    );
                    const http = require('http');
                    const status = await new Promise((resolve, reject) => {
                        const req = http.request(
                            {
                                host: '127.0.0.1',
                                port,
                                path:
                                    '/uploads/' +
                                    profile.id +
                                    '/%2e%2e%2f' +
                                    peer.id +
                                    '/legacy.png',
                                headers: { Authorization: 'Bearer ' + jwtA },
                            },
                            (res) => {
                                res.resume();
                                res.on('end', () => resolve(res.statusCode));
                            },
                        );
                        req.on('error', reject);
                        req.end();
                    });
                    assert.equal(status, 403);
                },
            );
            await t.test(
                'least privilege, original audit, timeline and notifications',
                async () => {
                    const r = await request(
                        'technical/login',
                        { login: reader.login, password },
                        { 'X-Tech-Request': '1' },
                    );
                    const h = {
                        Cookie: r.headers.get('set-cookie').split(';')[0],
                        'X-Tech-Request': '1',
                    };
                    assert.equal(
                        (await request('technical/users', undefined, h)).status,
                        403,
                    );
                    assert.equal(
                        (
                            await request(
                                'technical/files/' + accepted + '/original',
                                undefined,
                                h,
                            )
                        ).status,
                        403,
                    );
                    const original = await fetch(
                        base + '/api/technical/files/' + accepted + '/original',
                        { headers: techHeaders },
                    );
                    assert.equal(original.status, 200);
                    assert.equal(
                        original.headers.get('cache-control'),
                        'no-store',
                    );
                    assert.ok(
                        await p.techAudit.findFirst({
                            where: {
                                action: 'file.original.view',
                                objectId: accepted,
                            },
                        }),
                    );
                    const timeline = await request(
                        'technical/events?userId=' + a.user.id + '&order=asc',
                        undefined,
                        techHeaders,
                    );
                    assert.ok(timeline.data.items.length);
                    assert.ok(
                        timeline.data.items.every(
                            (e) => e.userId === a.user.id,
                        ),
                    );
                    const readerEvents = await request(
                        'technical/events?userId=' + a.user.id,
                        undefined,
                        h,
                    );
                    assert.ok(
                        readerEvents.data.items.every(
                            (e) =>
                                e.ip === null &&
                                e.sessionId === null &&
                                e.details?.identity === null,
                        ),
                    );
                    const notifications = await request(
                        'technical/notifications',
                        undefined,
                        techHeaders,
                    );
                    assert.ok(notifications.data.items.length);
                    assert.ok(notifications.data.vapidPublicKey);
                    const n = notifications.data.items[0];
                    assert.equal(
                        (
                            await request(
                                'technical/notifications/' + n.id + '/ack',
                                {},
                                h,
                            )
                        ).data.count,
                        0,
                    );
                    assert.equal(
                        (
                            await request(
                                'technical/notifications/' + n.id + '/ack',
                                {},
                                techHeaders,
                            )
                        ).data.count,
                        1,
                    );
                    assert.equal(
                        (
                            await request(
                                'technical/push',
                                {
                                    endpoint: 'https://127.0.0.1/private',
                                    keys: { auth: 'x', p256dh: 'y' },
                                },
                                techHeaders,
                            )
                        ).status,
                        400,
                    );
                },
            );
            await t.test(
                'reason and reauthentication, token revocation, blocking and mandatory password change',
                async () => {
                    const action = 'technical/users/' + a.user.id + '/';
                    assert.equal(
                        (
                            await request(
                                action + 'block',
                                {
                                    reason: 'Support verification',
                                    confirm: true,
                                    password: 'wrong',
                                },
                                techHeaders,
                            )
                        ).status,
                        403,
                    );
                    assert.equal(
                        (
                            await request(
                                action + 'block',
                                {
                                    reason: 'Support verification',
                                    confirm: true,
                                    password,
                                },
                                techHeaders,
                            )
                        ).status,
                        201,
                    );
                    assert.equal(
                        (
                            await request('auth/me', undefined, {
                                Authorization: 'Bearer ' + jwtA,
                            })
                        ).status,
                        401,
                    );
                    assert.equal(
                        (
                            await request('auth/login', {
                                phone: a.user.phone,
                                password: 'App-password-123',
                            })
                        ).status,
                        401,
                    );
                    await request(
                        action + 'unblock',
                        {
                            reason: 'Verified account owner',
                            confirm: true,
                            password,
                        },
                        techHeaders,
                    );
                    await request(
                        action + 'temporary-password',
                        {
                            reason: 'Verified account owner',
                            confirm: true,
                            password,
                            temporaryPassword: 'Temporary-password-123',
                        },
                        techHeaders,
                    );
                    const r = await request('auth/login', {
                        phone: a.user.phone,
                        password: 'Temporary-password-123',
                    });
                    assert.equal(r.status, 201);
                    assert.equal(r.data.user.mustChangePassword, true);
                    assert.equal(
                        (
                            await request('driver/profile', undefined, {
                                Authorization: 'Bearer ' + r.data.accessToken,
                            })
                        ).status,
                        403,
                    );
                    const changed = await request(
                        'auth/change-password',
                        {
                            currentPassword: 'Temporary-password-123',
                            newPassword: 'New-private-password-123',
                        },
                        { Authorization: 'Bearer ' + r.data.accessToken },
                    );
                    assert.equal(changed.status, 201);
                    assert.equal(
                        (
                            await request('driver/profile', undefined, {
                                Authorization:
                                    'Bearer ' + changed.data.accessToken,
                            })
                        ).status,
                        200,
                    );
                    assert.equal(
                        (
                            await request('auth/me', undefined, {
                                Authorization: 'Bearer ' + r.data.accessToken,
                            })
                        ).status,
                        401,
                    );
                },
            );
            await t.test(
                'device-reported unfinished form, retries, and aborted HTTP stream remain visible',
                async () => {
                    const auth = await request('auth/login', {
                        phone: b.user.phone,
                        password: 'App-password-123',
                    });
                    const headers = {
                            Authorization: 'Bearer ' + auth.data.accessToken,
                            'X-Client-Session': 'unfinished-form-session',
                        },
                        objectId = 'draft-' + randomUUID();
                    for (const action of ['form.open', 'retry', 'retry'])
                        assert.equal(
                            (
                                await request(
                                    'technical-client/event',
                                    { action, objectId },
                                    headers,
                                )
                            ).status,
                            201,
                        );
                    const timeline = await request(
                        'technical/events?userId=' +
                            b.user.id +
                            '&objectId=' +
                            objectId +
                            '&order=asc',
                        undefined,
                        techHeaders,
                    );
                    assert.equal(
                        timeline.data.items.filter(
                            (x) => x.result === 'REPORTED',
                        ).length,
                        3,
                    );
                    assert.ok(
                        timeline.data.items.every(
                            (x) => x.userId === b.user.id,
                        ),
                    );
                    const abort = new AbortController();
                    const response = await fetch(
                        base + '/api/realtime/driver/me/stream',
                        { headers, signal: abort.signal },
                    );
                    const requestId = response.headers.get('x-request-id');
                    assert.equal(response.status, 200);
                    abort.abort();
                    // Stream close and persisted audit evidence complete asynchronously.
                    // Wait for the required record, rather than assuming a 150 ms write.
                    const deadline = Date.now() + 5000;
                    let records;
                    do {
                        records = await p.techEvent.findMany({where:{requestId}});
                        if (records.some(x => x.stage === 'ABORTED' && x.result === 'UNKNOWN')) break;
                        await new Promise(r => setTimeout(r, 25));
                    } while (Date.now() < deadline);
                    assert.ok(records.some((x) => x.stage === 'START'));
                    assert.ok(
                        records.some(
                            (x) =>
                                x.stage === 'PROCESSING' &&
                                x.userId === b.user.id,
                        ),
                    );
                    assert.ok(
                        records.some(
                            (x) =>
                                x.stage === 'ABORTED' && x.result === 'UNKNOWN',
                        ),
                    );
                },
            );
            await t.test(
                'push provider outage retains notification and schedules a retry',
                async () => {
                    const {
                            TechnicalService,
                        } = require('../dist/src/technical/technical.service'),
                        webpush = require('web-push');
                    const svc = new TechnicalService(p);
                    svc.vapid = webpush.generateVAPIDKeys();
                    const issue = await p.techIssue.create({
                        data: {
                            fingerprint: randomUUID(),
                            title: 'Test push outage',
                            kind: 'ERROR',
                            severity: 'CRITICAL',
                        },
                    });
                    const notification = await p.techNotification.create({
                        data: {
                            accountId: owner.id,
                            issueId: issue.id,
                            severity: 'CRITICAL',
                        },
                    });
                    const sub = await p.techPush.create({
                        data: {
                            accountId: owner.id,
                            endpoint:
                                'https://fcm.googleapis.com/test-' +
                                randomUUID(),
                            subscription: {
                                endpoint: 'https://fcm.googleapis.com/test',
                                keys: { p256dh: 'fixture', auth: 'fixture' },
                            },
                        },
                    });
                    const original = webpush.sendNotification;
                    try {
                        webpush.sendNotification = async () => {
                            const e = new Error('provider unavailable');
                            e.statusCode = 503;
                            throw e;
                        };
                        await svc.deliverPush();
                        const updated = await p.techNotification.findUnique({
                            where: { id: notification.id },
                        });
                        assert.equal(updated.pushAt, null);
                        assert.equal(updated.attempts, 1);
                        assert.ok(updated.nextAttemptAt > new Date());
                    } finally {
                        webpush.sendNotification = original;
                        await p.techPush.deleteMany({ where: { id: sub.id } });
                    }
                },
            );

            if (process.env.TECH_BROWSER_TEST_MODULE)
                await t.test(
                    'real Chromium UI: login, sections, files and responsive layout',
                    async () => {
                        const { chromium } = require(
                            process.env.TECH_BROWSER_TEST_MODULE,
                        );
                        const browser = await chromium.launch({
                            executablePath: '/usr/bin/chromium',
                            headless: true,
                            args: ['--no-sandbox'],
                        });
                        try {
                            const page = await browser.newPage({
                                viewport: { width: 1440, height: 1000 },
                            });
                            const errors = [];
                            page.on('pageerror', (e) => errors.push(e.message));
                            await page.goto(base + '/api/technical/panel/');
                            await page
                                .getByLabel('Логин', { exact: true })
                                .fill(login);
                            await page
                                .getByLabel('Пароль', { exact: true })
                                .fill(password);
                            await page
                                .getByRole('button', {
                                    name: 'Войти',
                                    exact: true,
                                })
                                .click();
                            await page
                                .getByRole('heading', {
                                    name: 'Обзор системы',
                                    exact: true,
                                })
                                .waitFor();
                            for (const name of [
                                'Проблемы и ошибки',
                                'Действия пользователей',
                                'Пользователи и организации',
                                'Безопасность',
                                'Отклонения процессов',
                                'Файлы и фотографии',
                                'Сервисы и фоновые задачи',
                                'Резервные копии и развёртывания',
                                'Уведомления',
                                'Настройки правил и доступа',
                            ]) {
                                await page
                                    .getByRole('navigation')
                                    .getByRole('link', { name, exact: true })
                                    .click();
                                await page
                                    .getByRole('heading', { name, exact: true })
                                    .waitFor();
                                await page.waitForTimeout(120);
                                assert.equal(
                                    await page.locator('#notice').textContent(),
                                    '',
                                );
                            }
                            await page.goto(
                                base +
                                    '/api/technical/panel/#files/' +
                                    accepted,
                            );
                            await page
                                .getByRole('img', {
                                    name: 'Оригинал документа целиком',
                                })
                                .waitFor();
                            await page
                                .getByRole('button', {
                                    name: 'Оригинал и увеличение',
                                })
                                .click();
                            await page.locator('dialog[open]').waitFor();
                            await page
                                .getByRole('button', {
                                    name: 'Закрыть',
                                    exact: true,
                                })
                                .click();
                            await page.setViewportSize({
                                width: 390,
                                height: 844,
                            });
                            await page.goto(
                                base + '/api/technical/panel/#overview',
                            );
                            await page
                                .getByRole('heading', {
                                    name: 'Обзор системы',
                                    exact: true,
                                })
                                .waitFor();
                            assert.ok(
                                await page.evaluate(
                                    () =>
                                        document.documentElement.scrollWidth <=
                                        window.innerWidth,
                                ),
                                'mobile layout must not overflow',
                            );
                            await page.screenshot({
                                path: '/workspace/.setup/technical-panel-mobile.png',
                                fullPage: true,
                            });
                            assert.deepEqual(errors, []);
                        } finally {
                            await browser.close();
                        }
                    },
                );
            await t.test(
                'issue resolution requires verification; truthful health; storage failure; immutable audit',
                async () => {
                    const issues = await request(
                        'technical/issues',
                        undefined,
                        techHeaders,
                    );
                    const issue = issues.data.items[0];
                    assert.ok(issue);
                    assert.equal(
                        (
                            await request(
                                'technical/issues/' + issue.id,
                                { status: 'RESOLVED' },
                                techHeaders,
                            )
                        ).status,
                        400,
                    );
                    const health = await request(
                        'technical/overview',
                        undefined,
                        techHeaders,
                    );
                    assert.equal(health.data.database.status, 'available');
                    assert.equal(health.data.storage.status, 'available');
                    assert.equal(health.data.application.status, 'unknown');
                    assert.equal(health.data.reports.length, 0);
                    await fs.rename(
                        path.join(dir, accepted + '.bin'),
                        path.join(dir, accepted + '.missing'),
                    );
                    assert.equal(
                        (
                            await fetch(
                                base +
                                    '/api/technical/files/' +
                                    accepted +
                                    '/original',
                                { headers: techHeaders },
                            )
                        ).status,
                        400,
                    );
                    await new Promise((r) => setTimeout(r, 250));
                    const audit = await request(
                        'technical/audit/verify',
                        {},
                        techHeaders,
                    );
                    assert.equal(
                        audit.data.valid,
                        true,
                        JSON.stringify(audit.data),
                    );
                    await assert.rejects(
                        p.$executeRawUnsafe(
                            'UPDATE "TechAudit" SET action=\'tamper\' WHERE seq=(SELECT min(seq) FROM "TechAudit")',
                        ),
                    );
                    const stored = JSON.stringify(await p.techEvent.findMany());
                    for (const secret of [
                        password,
                        'Temporary-password-123',
                        'New-private-password-123',
                        jwtA,
                        jwtB,
                    ])
                        assert.ok(!stored.includes(secret));
                },
            );
        } finally {
            if (child) {
                child.kill('SIGTERM');
                await new Promise((r) => child.once('exit', r));
            }
            await p.$disconnect(); /* Keep the isolated audit key for repeatable tests against this dedicated database. */
        }
    },
);
