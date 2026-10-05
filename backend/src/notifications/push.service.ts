import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

type PushPayload = {
    title: string;
    body: string;
    data?: Record<string, string | number | boolean | null | undefined>;
};

@Injectable()
export class PushService {
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
        const serverKey = (process.env.FCM_SERVER_KEY || '').trim();
        if (!serverKey) return false;
        try {
            const response = await fetch('https://fcm.googleapis.com/fcm/send', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    Authorization: `key=${serverKey}`,
                },
                body: JSON.stringify({
                    to: token,
                    notification: {
                        title: payload.title,
                        body: payload.body,
                    },
                    data: this.stringifyData(payload.data ?? {}),
                    priority: 'high',
                }),
            });
            return response.ok;
        } catch (_) {
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
