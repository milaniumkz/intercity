import { BadRequestException, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { createPublicKey, verify } from 'crypto';

const providers = {
    GOOGLE: { url: 'https://www.googleapis.com/oauth2/v3/certs', issuers: ['accounts.google.com', 'https://accounts.google.com'], audience: 'GOOGLE_RECOVERY_CLIENT_IDS' },
    APPLE: { url: 'https://appleid.apple.com/auth/keys', issuers: ['https://appleid.apple.com'], audience: 'APPLE_RECOVERY_CLIENT_IDS' },
};
const cache = new Map<string, { until: number; keys: any[] }>();

export function providerConfig(provider: string) {
    if (provider !== 'GOOGLE' && provider !== 'APPLE') throw new BadRequestException('Выберите Google или Apple');
    const config = providers[provider];
    const audiences = (process.env[config.audience] || '').split(',').map(value => value.trim()).filter(Boolean);
    if (!audiences.length) throw new ServiceUnavailableException('Вход через выбранный сервис пока не настроен');
    return { ...config, audiences };
}

export async function verifiedSubject(provider: string, token: string, nonce: string) {
    const config = providerConfig(provider);
    const invalid = () => new UnauthorizedException('Не удалось подтвердить аккаунт. Начните ещё раз');
    if (typeof token !== 'string' || token.length > 16000) throw invalid();
    const parts = token.split('.');
    if (parts.length !== 3) throw invalid();
    let header, claims;
    try {
        header = JSON.parse(Buffer.from(parts[0], 'base64url').toString());
        claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
    } catch { throw invalid(); }
    if (header?.alg !== 'RS256' || typeof header.kid !== 'string') throw invalid();
    let entry = cache.get(provider);
    if (!entry || entry.until < Date.now()) {
        const result = await fetch(config.url, { signal: AbortSignal.timeout(5000) });
        if (!result.ok) throw new ServiceUnavailableException('Сервис входа временно недоступен');
        const data = await result.json();
        if (!Array.isArray(data.keys)) throw invalid();
        entry = { until: Date.now() + 300000, keys: data.keys };
        cache.set(provider, entry);
    }
    const key = entry.keys.find(k => k.kid === header.kid && k.kty === 'RSA');
    if (!key || !verify('RSA-SHA256', Buffer.from(parts[0]+'.'+parts[1]), createPublicKey({key,format:'jwk'}), Buffer.from(parts[2],'base64url'))) throw invalid();
    const now = Date.now() / 1000;
    if (!config.issuers.includes(claims?.iss) || !config.audiences.includes(claims.aud) ||
        !Number.isFinite(claims.exp) || claims.exp <= now || !Number.isFinite(claims.iat) ||
        claims.iat > now + 60 || claims.iat < now - 600 || claims.nonce !== nonce ||
        typeof claims.sub !== 'string' || !claims.sub || claims.sub.length > 255) throw invalid();
    return claims.sub as string;
}

export function browserProvider(provider:string) {
    const config=providerConfig(provider);
    const client=config.audiences[0];
    const redirect=process.env.RECOVERY_OAUTH_CALLBACK;
    const secret=process.env[provider==='APPLE'?'APPLE_RECOVERY_CLIENT_SECRET':'GOOGLE_RECOVERY_CLIENT_SECRET'];
    if(!redirect?.startsWith('https://')||!secret)throw new ServiceUnavailableException('Подключение провайдера пока не настроено');
    const apple=provider==='APPLE';
    return {client,redirect,secret,authorize:apple?'https://appleid.apple.com/auth/authorize':'https://accounts.google.com/o/oauth2/v2/auth',exchange:apple?'https://appleid.apple.com/auth/token':'https://oauth2.googleapis.com/token'};
}
