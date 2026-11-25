import { BadGatewayException, BadRequestException, ForbiddenException, Injectable, NotFoundException, ServiceUnavailableException, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { VtbSandboxGateway, verifiedVtbSandboxState } from '../payments/vtb-sandbox-gateway';

export const VTB_KZT_PER_RUB = 7;
const terminal = ['SUCCEEDED', 'FAILED', 'CANCELLED'];
@Injectable()
export class VtbSandboxService implements OnModuleInit, OnModuleDestroy {
    private readonly logger = new Logger(VtbSandboxService.name);
    private reconcileTimer?: NodeJS.Timeout;
    private reconciling = false;
    private readonly gateway = new VtbSandboxGateway({
        userName: process.env.VTB_SANDBOX_USER_NAME || '',
        password: process.env.VTB_SANDBOX_PASSWORD || Buffer.from(process.env.VTB_SANDBOX_PASSWORD_B64 || '', 'base64').toString('utf8'),
    });
    constructor(private readonly prisma: PrismaService) {}

    private get walletCreditsEnabled() { return process.env.VTB_SANDBOX_WALLET_CREDITS_ENABLED === 'true'; }

    onModuleInit() {
        this.reconcileTimer = setInterval(() => {
            void this.reconcileTopups().catch(() => this.logger.warn('VTB reconciliation will retry'));
        }, 30_000);
        this.reconcileTimer.unref();
    }

    onModuleDestroy() {
        if (this.reconcileTimer) clearInterval(this.reconcileTimer);
    }

    async reconcileTopups() {
        if (!this.enabled || this.reconciling) return;
        this.reconciling = true;
        try {
            const payments = await this.prisma.vtbSandboxPayment.findMany({
                where: { purpose: 'TOPUP', creditsWallet: true, creditedAt: null,
                    status: { in: ['REGISTERING', 'PENDING', 'UNKNOWN', 'UNVERIFIED', 'SUCCEEDED'] },
                    createdAt: { gte: new Date(Date.now() - 7 * 86400000), lte: new Date(Date.now() - 5000) } },
                orderBy: { updatedAt: 'asc' }, take: 20,
            });
            for (let i = 0; i < payments.length; i += 4) {
                const results = await Promise.allSettled(payments.slice(i, i + 4).map(payment => this.verify(payment)));
                if (results.some(result => result.status === 'rejected')) this.logger.warn('VTB credit will retry');
            }
        } finally { this.reconciling = false; }
    }

    private get enabled() { return process.env.VTB_SANDBOX_ENABLED === 'true' && this.gateway.configured; }

    private async actor(userId: string) {
        const user = await this.prisma.user.findUnique({ where: { id: userId }, include: { city: true, driverProfile: { select: { id: true } } } });
        if (!user) throw new NotFoundException('Пользователь не найден');
        return { user, eligible: user.city?.countryCode?.toUpperCase() === 'RU', canTopup: user.role !== 'PASSENGER' || !!user.driverProfile };
    }

    private publicPayment(payment: any) {
        if (!payment) return null;
        return {
            id: payment.id, purpose: payment.purpose, amount: payment.amountMinor / 100, currency: 'RUB',
            bankAmount: payment.bankAmountMinor / 100, bankCurrency: 'KZT', conversionRate: payment.conversionRate,
            status: payment.status, paymentUrl: payment.paymentUrl || null,
            paymentMode: 'TEST', creditsWallet: payment.creditsWallet === true && payment.purpose === 'TOPUP',
            creditedAt: payment.creditedAt || null, message: payment.lastError || null,
            verifiedAt: payment.verifiedAt || null,
        };
    }

    async instructions(userId: string) {
        const { eligible } = await this.actor(userId);
        const latest = eligible ? await this.prisma.vtbSandboxPayment.findFirst({ where: { userId, purpose: 'TOPUP' }, orderBy: { createdAt: 'desc' } }) : null;
        return {
            eligible, configured: this.gateway.configured, available: eligible && this.enabled, currency: 'RUB', bankCurrency: 'KZT', conversionRate: VTB_KZT_PER_RUB, paymentMode: 'TEST', creditsWallet: this.walletCreditsEnabled,
            message: !eligible ? 'ВТБ доступен только для российского профиля и рублёвого баланса.'
                : !this.enabled ? 'Тестовая оплата ВТБ ещё не настроена.'
                : this.walletCreditsEnabled
                    ? 'ВТБ: тестовый контур. После подтверждения оплаты сумма зачисляется на рублёвый баланс. Курс: 1 ₽ = 7 ₸.'
                    : 'Тестовый контур ВТБ. Зачисление на баланс отключено. Курс: 1 ₽ = 7 ₸.',
            latestPayment: this.publicPayment(latest),
        };
    }

    private apiUrl(path: string) {
        const base = process.env.PUBLIC_API_URL || process.env.BACKEND_PUBLIC_URL || 'https://api.intercity.89-207-255-27.sslip.io';
        const url = new URL(base);
        if (url.protocol !== 'https:' || url.username || url.password) throw new ServiceUnavailableException('Адрес возврата ВТБ не настроен');
        return url.origin + '/api/payments/vtb/sandbox/' + path;
    }

    async returnTarget(paymentId: string) {
        const base = process.env.PUBLIC_WEB_URL || process.env.FRONTEND_URL || 'https://intercity.89-207-255-27.sslip.io';
        const url = new URL(base);
        if (url.protocol !== 'https:' || url.username || url.password) throw new ServiceUnavailableException('Адрес возврата ВТБ не настроен');
        const payment = /^[a-f0-9-]{36}$/i.test(paymentId) ? await this.prisma.vtbSandboxPayment.findUnique({ where: { id: paymentId }, select: { purpose: true } }) : null;
        url.hash = (payment?.purpose === 'TRIP_TEST' ? '/order' : '/driver/wallet') + (/^[a-f0-9-]{36}$/i.test(paymentId) ? '?vtbSandboxPaymentId=' + encodeURIComponent(paymentId) : '');
        return url.toString();
    }

    private bankError(error: unknown) {
        return error instanceof BadGatewayException || error instanceof ServiceUnavailableException
            ? error.message : 'Не удалось получить ответ тестового шлюза ВТБ. Проверьте статус операции.';
    }

    async create(userId: string, input: { amount: number; currency?: string; requestKey?: string; purpose?: string }) {
        const { eligible, canTopup } = await this.actor(userId);
        const purpose = input.purpose || 'TOPUP';
        if (!['TOPUP', 'TRIP_TEST'].includes(purpose)) throw new BadRequestException('Некорректное назначение тестовой оплаты');
        if (purpose === 'TOPUP' && !canTopup) throw new BadRequestException('Пополнение основного баланса доступно водителю');
        if (!eligible) throw new ForbiddenException('ВТБ доступен только для российского профиля');
        if (input.currency !== 'RUB') throw new BadRequestException('Сумма в приложении указывается только в рублях');
        if (!this.enabled) throw new ServiceUnavailableException('Тестовая оплата ВТБ ещё не настроена');
        const minor = Math.round(input.amount * 100);
        if (!Number.isFinite(input.amount) || input.amount < 1 || input.amount > 100000 ||
            Math.abs(input.amount * 100 - minor) > 0.00001) throw new BadRequestException('Тестовая сумма: от 1 до 100 000 рублей, не больше двух знаков после запятой');
        const requestKey = input.requestKey || randomUUID();
        if (!/^[A-Za-z0-9_-]{1,80}$/.test(requestKey)) throw new BadRequestException('Некорректный идентификатор тестового запроса');
        const payment = await this.prisma.vtbSandboxPayment.upsert({
            where: { userId_requestKey: { userId, requestKey } }, update: {},
            create: { userId, requestKey, amountMinor: minor, bankAmountMinor: minor * VTB_KZT_PER_RUB, conversionRate: VTB_KZT_PER_RUB, purpose, creditsWallet: purpose === 'TOPUP' && this.walletCreditsEnabled },
        }).catch(async error => {
            // Concurrent compound-key upserts can race before Prisma's create.
            // Reuse the winner; never turn a retry into another bank payment.
            if (error?.code !== 'P2002') throw error;
            return this.prisma.vtbSandboxPayment.findUniqueOrThrow({ where: { userId_requestKey: { userId, requestKey } } });
        });
        if (payment.amountMinor !== minor || payment.purpose !== purpose) throw new BadRequestException('Повторный запрос должен содержать ту же сумму');
        const claim = await this.prisma.vtbSandboxPayment.updateMany({ where: { id: payment.id, status: 'CREATED' }, data: { status: 'REGISTERING' } });
        if (claim.count === 1) {
            let registered: { orderId: string; paymentUrl: string };
            try {
                registered = await this.gateway.register({ orderNumber: payment.id, amountMinor: payment.bankAmountMinor,
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
        if (terminal.includes(payment.status) &&
            !(payment.status === 'SUCCEEDED' && payment.creditsWallet && !payment.creditedAt)) return this.publicPayment(payment);
        let state: string;
        try {
            const data = payment.bankOrderId ? await this.gateway.status(payment.bankOrderId) : await this.gateway.statusByOrderNumber(payment.id);
            state = verifiedVtbSandboxState(data, { orderNumber: payment.id, bankAmountMinor: payment.bankAmountMinor });
        } catch (error) {
            await this.prisma.vtbSandboxPayment.updateMany({ where: { id: payment.id, creditedAt: null, status: { notIn: ['FAILED', 'CANCELLED'] } }, data: { lastError: this.bankError(error) } });
            return this.publicPayment(await this.prisma.vtbSandboxPayment.findUniqueOrThrow({ where: { id: payment.id } }));
        }
        if (state === 'SUCCEEDED') {
            try { await this.settleSucceeded(payment.id); }
            catch {
                const message = 'Банк подтвердил оплату. Зачисление ещё не завершено: повторите проверку, повторно платить не нужно.';
                await this.prisma.vtbSandboxPayment.updateMany({
                    where: { id: payment.id, creditedAt: null, status: { notIn: ['FAILED', 'CANCELLED'] } },
                    data: { lastError: message },
                }).catch(() => undefined);
                throw new ServiceUnavailableException(message);
            }
            return this.publicPayment(await this.prisma.vtbSandboxPayment.findUniqueOrThrow({ where: { id: payment.id } }));
        }
        await this.prisma.vtbSandboxPayment.updateMany({
            where: { id: payment.id, creditedAt: null, status: { notIn: ['FAILED', 'CANCELLED'] } },
            data: { status: state, lastError: state === 'UNVERIFIED' ? 'Не удалось подтвердить сумму, валюту или номер платежа ВТБ.' : null,
                ...(state !== 'UNVERIFIED' ? { verifiedAt: new Date() } : {}) },
        });
        return this.publicPayment(await this.prisma.vtbSandboxPayment.findUniqueOrThrow({ where: { id: payment.id } }));
    }

    private async settleSucceeded(id: string) {
        await this.prisma.$transaction(async tx => {
            const current = await tx.vtbSandboxPayment.findUnique({ where: { id } });
            if (!current || ['FAILED', 'CANCELLED'].includes(current.status)) return;
            const verifiedAt = new Date();
            if (!current.creditsWallet || current.purpose !== 'TOPUP') {
                await tx.vtbSandboxPayment.updateMany({
                    where: { id, status: { notIn: terminal } },
                    data: { status: 'SUCCEEDED', verifiedAt, lastError: null },
                });
                return;
            }
            const claimed = await tx.vtbSandboxPayment.updateMany({
                where: { id, purpose: 'TOPUP', creditsWallet: true, creditedAt: null,
                    status: { notIn: ['FAILED', 'CANCELLED'] } },
                data: { status: 'SUCCEEDED', verifiedAt, creditedAt: verifiedAt, lastError: null },
            });
            if (claimed.count !== 1) return;
            const amount = current.amountMinor / 100;
            const wallet = await tx.wallet.upsert({
                where: { userId: current.userId },
                create: { userId: current.userId, moneyRub: amount },
                update: { moneyRub: { increment: amount } },
            });
            await tx.topupRequest.create({ data: {
                id, walletId: wallet.id, amount, currency: 'RUB', status: 'APPROVED',
                provider: 'VTB_SANDBOX', externalOrderId: 'vtb-sandbox:' + (current.bankOrderId || id),
            } });
            await tx.walletTransaction.create({ data: {
                id, walletId: wallet.id, type: 'TOPUP_DEMO_CREDIT', direction: 'CREDIT',
                balanceSource: 'MONEY', amount, currency: 'RUB', topupRequestId: id,
                idempotencyKey: 'vtb-sandbox:' + id + ':credit',
                note: 'Пополнение ВТБ · тестовый контур',
            } });
        });
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
        return { success: true, paymentId: payment.id, status: result?.status, creditsWallet: result?.creditsWallet === true, creditedAt: result?.creditedAt || null };
    }
}
