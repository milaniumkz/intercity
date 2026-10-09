import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

type PushPayload = {
    title: string;
    body: string;
    data?: Record<string, string | number | boolean | null | undefined>;
};

@Injectable()
export class PushService {
    private readonly logger = new Logger(PushService.name);
    private accessToken: { value: string; expires: number } | null = null;
    constructor(private readonly prisma: PrismaService) { }

    async sendToUser(userId: string | null | undefined, payload: PushPayload): Promise<boolean> {
        if (!userId) return false;
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            select: { pushToken: true },
        });
        const token = (user?.pushToken ?? '').trim();
        if (!token) return false;
        return this.sendToToken(token, payload);
    }

    async sendOrderStatusToPassenger(orderId: string, status: string): Promise<boolean> {
        const order = await this.prisma.order.findUnique({
            where: { id: orderId },
            include: {
                passenger: { select: { id: true } },
                driver: {
                    include: {
                        user: { select: { name: true, phone: true } },
                    },
                },
            },
        });
        if (!order) return false;
        const message = this.orderStatusMessage(status, order.driver?.user?.name);
        if (!message) return false;
        return this.sendToUser(order.passengerId, {
            title: message.title,
            body: message.body,
            data: {
                type: 'order_status',
                orderId,
                status: status.toUpperCase(),
            },
        });
    }

    private orderStatusMessage(status: string, driverName?: string | null): { title: string; body: string } | null {
        const name = (driverName ?? '').trim() || 'Водитель';
        switch (status.toUpperCase()) {
            case 'DRIVER_ASSIGNED':
            case 'DRIVER_EN_ROUTE':
                return {
                    title: 'Водитель назначен',
                    body: `${name} принял заказ и едет к вам.`,
                };
            case 'DRIVER_ARRIVED':
                return {
                    title: 'Водитель прибыл',
                    body: `${name} уже на месте подачи.`,
                };
            case 'IN_PROGRESS':
                return {
                    title: 'Поездка началась',
                    body: 'Хорошей поездки. Статус заказа обновлён.',
                };
            case 'COMPLETED':
                return {
                    title: 'Поездка завершена',
                    body: 'Спасибо за поездку. Оцените водителя.',
                };
            case 'CANCELLED':
                return {
                    title: 'Заказ отменён',
                    body: 'Заказ был отменён.',
                };
            default:
                return null;
        }
    }

    private async sendToToken(token: string, payload: PushPayload): Promise<boolean> {
        try {
            const inline = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
            const path = process.env.GOOGLE_APPLICATION_CREDENTIALS;
            if (!inline && !path) {
                this.logger.warn('Push unavailable: Firebase service account is not configured');
                return false;
            }
            const credentials = JSON.parse(inline || readFileSync(path!, 'utf8'));
            if (!credentials.project_id || !credentials.client_email || !credentials.private_key) {
                throw new Error('Invalid Firebase service account configuration');
            }
            if (!this.accessToken || this.accessToken.expires <= Date.now()) {
                const now = Math.floor(Date.now() / 1000);
                const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');
                const unsigned = `${encode({ alg: 'RS256', typ: 'JWT' })}.${encode({
                    iss: credentials.client_email,
                    scope: 'https://www.googleapis.com/auth/firebase.messaging',
                    aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600,
                })}`;
                const signature = createSign('RSA-SHA256').update(unsigned).sign(credentials.private_key, 'base64url');
                const auth = await fetch('https://oauth2.googleapis.com/token', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${signature}` }),
                    signal: AbortSignal.timeout(10000),
                });
                if (!auth.ok) throw new Error(`Firebase authorization HTTP ${auth.status}`);
                const result = await auth.json() as { access_token: string; expires_in: number };
                if (!result.access_token) throw new Error('Firebase authorization returned no token');
                this.accessToken = { value: result.access_token, expires: Date.now() + (result.expires_in - 60) * 1000 };
            }
            const offer = payload.data?.type === 'driver_offer';
            const expiresAt = Date.parse(String(payload.data?.expiresAt ?? ''));
            const ttl = offer && Number.isFinite(expiresAt)
                ? Math.max(0, Math.min(120, Math.floor((expiresAt - Date.now()) / 1000)))
                : offer ? 30 : 3600;
            if (offer && ttl === 0) return false;
            const response = await fetch(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(credentials.project_id)}/messages:send`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${this.accessToken.value}` },
                body: JSON.stringify({ message: {
                    token,
                    notification: { title: payload.title, body: payload.body },
                    data: this.stringifyData(payload.data ?? {}),
                    android: { priority: 'high', ttl: `${ttl}s`, notification: { channel_id: offer ? 'intercity_driver_offers_v2' : 'intercity_default_channel', sound: offer ? 'intercity_order' : 'default' } },
                    apns: { payload: { aps: { sound: offer ? 'intercity_order.wav' : 'default', ...(offer ? { 'interruption-level': 'time-sensitive' } : {}) } } },
                    webpush: { headers: { Urgency: 'high', TTL: String(ttl) }, notification: { tag: offer ? `driver-offer-${payload.data?.orderId}` : undefined, requireInteraction: offer } },
                } }),
                signal: AbortSignal.timeout(10000),
            });
            if (!response.ok) {
                if (response.status === 401) this.accessToken = null;
                this.logger.warn(`Firebase push failed: HTTP ${response.status}`);
            }
            return response.ok;
        } catch (_) {
            this.logger.warn('Firebase push failed: check service account and network configuration');
            return false;
        }
    }

    private stringifyData(data: Record<string, string | number | boolean | null | undefined>) {
        return Object.fromEntries(
            Object.entries(data)
                .filter(([, value]) => value !== null && value !== undefined)
                .map(([key, value]) => [key, String(value)]),
        );
    }
}
