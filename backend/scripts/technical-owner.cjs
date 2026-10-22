// Run on the server console. Credentials go only to a mode-0600 file, never stdout.
const { PrismaClient } = require('@prisma/client');
const bcrypt = require('bcrypt');
const { randomBytes } = require('crypto');
const fs = require('fs/promises');
const path = require('path');
(async () => {
    const p = new PrismaClient();
    try {
        if (await p.techAccount.count()) {
            if (process.argv.includes('--if-empty')) {
                console.log('Technical access already provisioned');
                return;
            }
            throw Error(
                'Technical accounts already exist; refusing to overwrite access',
            );
        }
        const storage = path.resolve(
            process.env.TECH_STORAGE_DIR || 'technical-data',
        );
        await fs.mkdir(storage, { recursive: true, mode: 0o700 });
        const file = path.join(storage, 'owner-access.json');
        const login = 'owner',
            password = randomBytes(24).toString('base64url');
        await fs.writeFile(
            file,
            JSON.stringify({
                login,
                password,
                createdAt: new Date().toISOString(),
            }),
            { flag: 'wx', mode: 0o600 },
        );
        try {
            await p.techAccount.create({
                data: {
                    login,
                    passwordHash: await bcrypt.hash(password, 12),
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
        } catch (e) {
            await fs.unlink(file);
            throw e;
        }
        console.log(
            'Owner created. Retrieve credentials securely from ' +
                file +
                ' and remove this file after saving them in your password manager.',
        );
    } finally {
        await p.$disconnect();
    }
})().catch(() => {
    console.error(
        'Owner setup failed or technical accounts already exist. No credentials printed.',
    );
    process.exitCode = 1;
});
