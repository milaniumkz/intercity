// Read a non-secret deployment/backup report from stdin, not from an HTTP endpoint.
const { PrismaClient } = require('@prisma/client');
let input = '';
process.stdin.on('data', (b) => {
    input += b;
    if (input.length > 10000) process.exit(1);
});
process.stdin.on('end', async () => {
    const p = new PrismaClient();
    try {
        const r = JSON.parse(input);
        if (
            !['BACKUP', 'DEPLOYMENT', 'RESTORE'].includes(r.kind) ||
            !['SUCCESS', 'FAILURE'].includes(r.status)
        )
            throw Error();
        await p.techReport.create({
            data: {
                kind: r.kind,
                status: r.status,
                version: String(r.version || 'unknown').slice(0, 80),
                ...(r.at && Number.isFinite(Date.parse(r.at))
                    ? { at: new Date(r.at) }
                    : {}),
                details: {
                    databaseVerified: r.databaseVerified === true,
                    filesVerified: r.filesVerified === true,
                    note: String(r.note || '').slice(0, 200),
                },
            },
        });
        console.log('Maintenance report saved');
    } catch {
        console.error('Maintenance report failed');
        process.exitCode = 1;
    } finally {
        await p.$disconnect();
    }
});
