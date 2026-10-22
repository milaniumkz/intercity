import { createHash, createHmac, randomUUID } from 'crypto';
import { AsyncLocalStorage } from 'async_hooks';
export const techContext = new AsyncLocalStorage<{
    requestId: string;
    userId?: string;
}>();
export const PERMISSIONS = [
    'events',
    'personal',
    'originals',
    'users',
    'danger',
    'settings',
] as const;
export const digest = (value: string | Buffer) =>
    createHash('sha256').update(value).digest('hex');
export const hmac = (key: Buffer, value: string) =>
    createHmac('sha256', key).update(value).digest('hex');
export const safeId = (v: any): string | undefined =>
    typeof v === 'string' && /^[a-zA-Z0-9_.:-]{1,120}$/.test(v) ? v : undefined;
// Never record arbitrary bodies, response objects, headers or exception stacks.
export function safeMessage(v: any): string {
    return String(v ?? '')
        .slice(0, 1500)
        .replace(/Bearer\s+\S+/gi, '[REDACTED]')
        .replace(
            /\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g,
            '[REDACTED]',
        )
        .replace(
            /((?:["']?[a-z_]*(?:password|token|secret|cookie|authorization|api[_-]?key)[a-z_]*["']?)\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;]+)/gi,
            '$1[REDACTED]',
        )
        .replace(/https?:\/\/[^\s]+/g, '[URL]')
        .replace(/\+?\d[\d ()-]{8,}\d/g, '[NUMBER]');
}
export function requestIdentity(req: any) {
    return {
        requestId: randomUUID(),
        sessionId: safeId(req.headers['x-client-session']),
        client: {
            source: 'Сообщено устройством',
            userAgent: safeMessage(req.headers['user-agent'] ?? '').slice(
                0,
                180,
            ),
            platform: safeId(req.headers['x-client-platform']) ?? null,
            version: safeId(req.headers['x-app-version']) ?? null,
        },
        ip: req.ip ?? req.socket?.remoteAddress ?? null,
    };
}
export function pageArgs(q: any) {
    const page = Number(q.page ?? 1),
        limit = Number(q.limit ?? 50);
    if (
        !Number.isInteger(page) ||
        page < 1 ||
        page > 10000 ||
        !Number.isInteger(limit) ||
        limit < 1 ||
        limit > 100
    )
        throw new Error('Некорректная страница');
    return { skip: (page - 1) * limit, take: limit };
}
export const RULE_DEFAULTS: any = {
    retention: { eventDays: 90, fileDays: 90 },
    image: {
        version: 'quality-v1',
        rejectVariance: 8,
        reviewVariance: 35,
        maxBytes: 10485760,
    },
    security: { windowMinutes: 10, threshold: 8 },
};

export function canonical(v: any): string {
    if (v === null || typeof v !== 'object') return JSON.stringify(v);
    if (Array.isArray(v)) return '[' + v.map(canonical).join(',') + ']';
    return (
        '{' +
        Object.keys(v)
            .sort()
            .map((k) => JSON.stringify(k) + ':' + canonical(v[k]))
            .join(',') +
        '}'
    );
}
