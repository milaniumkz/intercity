import { BadGatewayException, BadRequestException, ForbiddenException, Injectable, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { VtbSandboxGateway, verifiedVtbSandboxState } from '../payments/vtb-sandbox-gateway';

const terminal = ['SUCCEEDED', 'FAILED', 'CANCELLED'];
@Injectable()
export class VtbSandboxService {
    private readonly gateway = new VtbSandboxGateway({
        userName: process.env.VTB_SANDBOX_USER_NAME || '',
        password: process.env.VTB_SANDBOX_PASSWORD || '',
    });
    constructor(private readonly prisma: PrismaService) {}

    private get enabled() { return process.env.VTB_SANDBOX_ENABLED === 'true' && this.gateway.configured; }

    private async actor(userId: string) {
        const user = await this.prisma.user.findUnique({ where: { id: userId }, include: { city: true, driverProfile: { select: { id: true } } } });
        if (!user) throw new NotFoundException('Пользователь не найден');
        return { user, eligible: user.city?.countryCode === 'RU' && (user.role !== 'PASSENGER' || !!user.driverProfile) };
    }

    private publicPayment(payment: any) {
        if (!payment) return null;
        return {
            id: payment.id, amount: payment.amountMinor / 100, currency: 'RUB',
            status: payment.status, paymentUrl: payment.paymentUrl || null,
            paymentMode: 'TEST', creditsWallet: false, message: payment.lastError || null,
            verifiedAt: payment.verifiedAt || null,
        };
    }

    async instructions(userId: string) {
        const { eligible } = await this.actor(userId);
        const latest = eligible ? await this.prisma.vtbSandboxPayment.findFirst({ where: { userId }, orderBy: { createdAt: 'desc' } }) : null;
        return {
            eligible, available: eligible && this.enabled, currency: 'RUB', paymentMode: 'TEST', creditsWallet: false,
            message: !eligible ? 'ВТБ доступен только для российского профиля и рублёвого баланса.'
                : !this.enabled ? 'Тестовая оплата ВТБ ещё не настроена.'
                : 'Тестовый контур ВТБ. Реальные деньги не списываются, настоящий баланс не пополняется.',
            latestPayment: this.publicPayment(latest),
        };
    }

    private apiUrl(path: string) {
        const base = process.env.PUBLIC_API_URL || process.env.BACKEND_PUBLIC_URL || 'https://api.intercity.89-207-255-27.sslip.io';
        const url = new URL(base);
        if (url.protocol !== 'https:' || url.username || url.password) throw new ServiceUnavailableException('Адрес возврата ВТБ не настроен');
        return url.origin + '/api/payments/vtb/sandbox/' + path;
    }

    returnTarget(paymentId: string) {
        const base = process.env.PUBLIC_WEB_URL || process.env.FRONTEND_URL || 'https://intercity.89-207-255-27.sslip.io';
        const url = new URL(base);
        if (url.protocol !== 'https:' || url.username || url.password) throw new ServiceUnavailableException('Адрес возврата ВТБ не настроен');
        url.hash = '/driver/wallet' + (/^[a-f0-9-]{36}$/i.test(paymentId) ? '?vtbSandboxPaymentId=' + encodeURIComponent(paymentId) : '');
        return url.toString();
    }

    private bankError(error: unknown) {
        return error instanceof BadGatewayException || error instanceof ServiceUnavailableException
            ? error.message : 'Не удалось получить ответ тестового шлюза ВТБ. Проверьте статус операции.';
    }

    async create(userId: string, input: { amount: number; currency?: string; requestKey?: string }) {
        const { eligible } = await this.actor(userId);
        if (!eligible) throw new ForbiddenException('ВТБ доступен только для российского профиля');
        if (input.currency !== 'RUB') throw new BadRequestException('ВТБ принимает только рубли');
        if (!this.enabled) throw new ServiceUnavailableException('Тестовая оплата ВТБ ещё не настроена');
        const minor = Math.round(input.amount * 100);
        if (!Number.isFinite(input.amount) || input.amount < 1 || input.amount > 100000 ||
            Math.abs(input.amount * 100 - minor) > 0.00001) throw new BadRequestException('Тестовая сумма: от 1 до 100 000 рублей, не больше двух знаков после запятой');
        const requestKey = input.requestKey || randomUUID();
        if (!/^[A-Za-z0-9_-]{1,80}$/.test(requestKey)) throw new BadRequestException('Некорректный идентификатор тестового запроса');
        const payment = await this.prisma.vtbSandboxPayment.upsert({
            where: { userId_requestKey: { userId, requestKey } }, update: {},
            create: { userId, requestKey, amountMinor: minor },
        });
        if (payment.amountMinor !== minor) throw new BadRequestException('Повторный запрос должен содержать ту же сумму');
        const claim = await this.prisma.vtbSandboxPayment.updateMany({ where: { id: payment.id, status: 'CREATED' }, data: { status: 'REGISTERING' } });
        if (claim.count === 1) {
            let registered: { orderId: string; paymentUrl: string };
            try {
                registered = await this.gateway.register({ orderNumber: payment.id, amountMinor: minor,
                    returnUrl: this.apiUrl('return') + '?paymentId=' + encodeURIComponent(payment.id) });
            } catch (error) {
                await this.prisma.vtbSandboxPayment.updateMany({ where: { id: payment.id, status: 'REGISTERING' }, data: { status: 'UNKNOWN', lastError: this.bankError(error) } });
                return this.publicPayment(await this.prisma.vtbSandboxPayment.findUniqueOrThrow({ where: { id: payment.id } }));
            }
            await this.prisma.vtbSandboxPayment.update({ where: { id: payment.id }, data: {
                status: 'PENDING', bankOrderId: registered.orderId, paymentUrl: registered.paymentUrl, lastError: null,
            } });
        }
        return this.publicPayment(await this.prisma.vtbSandboxPayment.findUniqueOrThrow({ where: { id: payment.id } }));
    }

    async check(userId: string, id: string) {
        const payment = await this.prisma.vtbSandboxPayment.findFirst({ where: { id, userId } });
        if (!payment) throw new NotFoundException('Тестовый платёж не найден');
        return this.verify(payment);
    }

    private async verify(payment: any) {
        if (terminal.includes(payment.status)) return this.publicPayment(payment);
        let state: string;
        try {
            const data = payment.bankOrderId ? await this.gateway.status(payment.bankOrderId) : await this.gateway.statusByOrderNumber(payment.id);
            state = verifiedVtbSandboxState(data, { orderNumber: payment.id, amountMinor: payment.amountMinor });
        } catch (error) {
            await this.prisma.vtbSandboxPayment.updateMany({ where: { id: payment.id, status: { notIn: terminal } }, data: { lastError: this.bankError(error) } });
            return this.publicPayment(await this.prisma.vtbSandboxPayment.findUniqueOrThrow({ where: { id: payment.id } }));
        }
        await this.prisma.vtbSandboxPayment.updateMany({
            where: { id: payment.id, status: { notIn: terminal } },
            data: { status: state, lastError: state === 'UNVERIFIED' ? 'Не удалось подтвердить сумму, валюту или номер платежа ВТБ.' : null,
                ...(state !== 'UNVERIFIED' ? { verifiedAt: new Date() } : {}) },
        });
        return this.publicPayment(await this.prisma.vtbSandboxPayment.findUniqueOrThrow({ where: { id: payment.id } }));
    }

    async callback(input: Record<string, any>) {
        const bankOrderId = typeof input.mdOrder === 'string' ? input.mdOrder : '';
        const orderNumber = typeof input.orderNumber === 'string' ? input.orderNumber : '';
        if (!bankOrderId && !orderNumber) return { success: true, ignored: true };
        const payment = await this.prisma.vtbSandboxPayment.findFirst({ where: { OR: [
            ...(bankOrderId ? [{ bankOrderId }] : []), ...(orderNumber ? [{ id: orderNumber }] : []),
        ] } });
        if (!payment || (orderNumber && orderNumber !== payment.id) || (bankOrderId && payment.bankOrderId && bankOrderId !== payment.bankOrderId)) return { success: true, ignored: true };
        // Callback status and redirects are hints only; always ask the authenticated bank API.
        const result = await this.verify(payment);
        return { success: true, paymentId: payment.id, status: result?.status, creditsWallet: false };
    }
}
