import {
    Injectable,
    NotFoundException,
    BadRequestException,
    ServiceUnavailableException,
} from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { TopupRequestDto, PayoutRequestDto } from './dto/wallet.dto';

@Injectable()
export class WalletService {
    private readonly kassa24BaseUrl =
        process.env.KASSA24_API_URL ||
        'https://ecommerce.pult24.kz';
    private readonly kassa24Login =
        process.env.KASSA24_LOGIN ||
        process.env.KASSA24_MERCHANT_ID ||
        '';
    private readonly kassa24Password = process.env.KASSA24_PASSWORD || '';
    private readonly kassa24Demo =
        (process.env.KASSA24_DEMO || 'false').toLowerCase() === 'true';
    private payoutSourceColumnSupported: boolean | null = null;

    constructor(private prisma: PrismaService) { }

    async getWallet(userId: string) {
        const wallet = await this.prisma.wallet.findUnique({
            where: { userId },
            select: {
                id: true,
                userId: true,
                money: true,
                bonus: true,
                createdAt: true,
                updatedAt: true,
            },
        });

        if (!wallet) {
            throw new NotFoundException('Кошелёк не найден');
        }

        const [topups, payouts] = await Promise.all([
            this.prisma.topupRequest.findMany({
                where: { walletId: wallet.id },
                orderBy: { createdAt: 'desc' },
                take: 10,
            }),
            this.prisma.payoutRequest.findMany({
                where: { walletId: wallet.id },
                orderBy: { createdAt: 'desc' },
                take: 10,
                select: {
                    id: true,
                    walletId: true,
                    amount: true,
                    status: true,
                    adminId: true,
                    createdAt: true,
                    updatedAt: true,
                },
            }),
        ]);

        return {
            ...wallet,
            topups,
            payouts,
        };
    }

    async createTopupRequest(userId: string, dto: TopupRequestDto, userRole?: string) {
        const driverProfile = await this.prisma.driverProfile.findUnique({
            where: { userId },
            select: { id: true },
        });

        if ((userRole ?? '').toUpperCase() === 'PASSENGER' && !driverProfile) {
            throw new BadRequestException('Пассажирам доступен только бонусный баланс. Пополнение счёта недоступно.');
        }

        const wallet = await this.prisma.wallet.findUnique({
            where: { userId },
            include: { user: true },
        });

        if (!wallet) {
            throw new NotFoundException('Кошелёк не найден');
        }

        if (dto.amount <= 0) {
            throw new BadRequestException('Введите сумму больше нуля');
        }

        let localTopup = await this.prisma.topupRequest.create({
            data: {
                walletId: wallet.id,
                amount: dto.amount,
                status: 'PENDING',
                provider: 'ONLINE',
            },
        });

        let paymentUrl: string | null = null;
        let externalOrderId: string | null = null;
        let provider = 'ONLINE';
        let message = 'Заявка на пополнение создана';
        try {
            const response = await fetch(this.kassa24Endpoint('payment/create'), {
                method: 'POST',
                headers: this.kassa24Headers(),
                body: JSON.stringify({
                    amount: Math.round(dto.amount * 100),
                    externalId: localTopup.id,
                    merchantId: this.kassa24Login,
                    description: `Пополнение InterCity ${localTopup.id}`,
                    userId,
                    phone: this.normalizePhone(wallet.user?.phone || ''),
                    email: '',
                    callbackUrl: this.backendCallbackUrl('/wallet/topup/callback'),
                    backUrl: process.env.PUBLIC_WEB_URL || process.env.FRONTEND_URL || undefined,
                    demo: this.kassa24Demo,
                }),
            });
            const data: any = await response.json().catch(() => ({}));
            if (!response.ok) {
                throw new Error(
                    this.normalizeOnlinePaymentError(
                        data?.error || data?.message || 'Не удалось создать ссылку на онлайн-оплату',
                        'payment',
                    ),
                );
            }
            paymentUrl = data?.url || data?.payment_url || data?.paymentUrl || data?.link || null;
            externalOrderId = (
                data?.id ||
                data?.paymentId ||
                data?.order_id ||
                data?.orderId ||
                data?.invoice_id ||
                data?.invoiceId ||
                localTopup.id
            )?.toString?.() ?? null;
            if (!paymentUrl) {
                throw new Error(
                    this.normalizeOnlinePaymentError(
                        'Ссылка на онлайн-оплату не была возвращена',
                        'payment',
                    ),
                );
            }
            if (externalOrderId) {
                localTopup = await this.prisma.topupRequest.update({
                    where: { id: localTopup.id },
                    data: {
                        provider: 'KASSA24',
                        externalOrderId,
                    },
                });
            }
            message = 'Ссылка на онлайн-пополнение создана';
        } catch (e: any) {
            provider = 'MANUAL';
            localTopup = await this.prisma.topupRequest.update({
                where: { id: localTopup.id },
                data: { provider: 'MANUAL' },
            });
            const onlineError = this.normalizeOnlinePaymentError(
                e?.message || 'Не удалось создать ссылку на онлайн-оплату',
                'payment',
            );
            message = `Заявка на пополнение создана. ${onlineError} Администратор сможет обработать заявку вручную.`;
        }

        return {
            ...localTopup,
            paymentUrl,
            orderId: externalOrderId,
            provider,
            message,
        };
    }

    async handleTopupPaymentCallback(body: Record<string, any>) {
        const externalOrderId = this.extractExternalOrderId(body);
        const localTopupId = this.extractLocalTopupId(body);
        const paid = this.isPaymentPaid(body);
        if (!paid) {
            return { success: true, ignored: true, reason: 'payment_not_paid' };
        }
        if (!externalOrderId && !localTopupId) {
            throw new BadRequestException('Не передан идентификатор платежа');
        }
        const topup = await this.prisma.topupRequest.findFirst({
            where: {
                OR: [
                    ...(externalOrderId ? [{ externalOrderId }] : []),
                    ...(localTopupId ? [{ id: localTopupId }] : []),
                ],
            },
            include: { wallet: true },
        });
        if (!topup) {
            throw new NotFoundException('Заявка на пополнение не найдена');
        }
        if (topup.status !== 'PENDING') {
            return { success: true, alreadyProcessed: true, topupId: topup.id };
        }

        await this.prisma.$transaction(async (tx) => {
            const current = await tx.topupRequest.findUnique({ where: { id: topup.id } });
            if (!current || current.status !== 'PENDING') return;
            await tx.topupRequest.update({
                where: { id: topup.id },
                data: {
                    status: 'APPROVED',
                    provider: topup.provider ?? 'KASSA24',
                    externalOrderId: externalOrderId ?? topup.externalOrderId,
                },
            });
            await tx.wallet.update({
                where: { id: topup.walletId },
                data: { money: { increment: topup.amount } },
            });
            await (tx as any).walletTransaction.create({
                data: {
                    walletId: topup.walletId,
                    type: 'TOPUP_PAID_ONLINE',
                    direction: 'CREDIT',
                    balanceSource: 'MONEY',
                    amount: topup.amount,
                    topupRequestId: topup.id,
                    idempotencyKey: `topup:${topup.id}:paid`,
                    note: 'Online topup paid',
                },
            }).catch(() => null);
        });

        return { success: true, topupId: topup.id };
    }

    async createPayoutRequest(userId: string, dto: PayoutRequestDto, userRole?: string) {
        const wallet = await this.prisma.wallet.findUnique({
            where: { userId },
        });

        if (!wallet) {
            throw new NotFoundException('Кошелёк не найден');
        }

        const isPassenger = (userRole ?? '').toUpperCase() === 'PASSENGER';
        const passengerBonusPayoutMin = 5000;

        if (isPassenger) {
            if (wallet.bonus < passengerBonusPayoutMin) {
                throw new BadRequestException(
                    `Вывод бонусов доступен после накопления ${passengerBonusPayoutMin} бонусов`,
                );
            }
            if (dto.amount < passengerBonusPayoutMin) {
                throw new BadRequestException(
                    `Минимальная сумма вывода — ${passengerBonusPayoutMin} бонусов`,
                );
            }
            if (wallet.bonus < dto.amount) {
                throw new BadRequestException('Недостаточно бонусов');
            }
        }

        // Check minimum payout amount
        const settings = await this.prisma.appSettings.findMany();
        const minPayout = parseFloat(settings.find(s => s.key === 'minPayoutAmount')?.value || '1000');

        if (!isPassenger && dto.amount < minPayout) {
            throw new BadRequestException(`Минимальная сумма вывода — ${minPayout}`);
        }

        const payoutFromBonus = isPassenger || (wallet.money < dto.amount && wallet.bonus >= dto.amount);
        if (wallet.money < dto.amount && !payoutFromBonus) {
            throw new BadRequestException('Недостаточно средств');
        }

        if (!dto.cardNumber || dto.cardNumber.trim().length < 12) {
            throw new BadRequestException('Введите корректный номер карты для вывода');
        }

        const payoutSource = payoutFromBonus ? 'BONUS' : 'MONEY';
        let localPayout: { id: string; walletId: string; amount: number; status: string };
        try {
            localPayout = await this.prisma.$transaction(async (tx) => {
                await tx.wallet.update({
                    where: { userId },
                    data: payoutFromBonus
                        ? { bonus: { decrement: dto.amount } }
                        : { money: { decrement: dto.amount } },
                });
                return this.createPayoutRequestCompat(tx, {
                    walletId: wallet.id,
                    amount: dto.amount,
                    source: payoutSource,
                });
            });
        } catch (error) {
            if (this.isPayoutStorageUnavailableError(error)) {
                throw new ServiceUnavailableException(
                    'Модуль вывода временно недоступен, пока не применены миграции базы данных',
                );
            }
            throw error;
        }

        await this.recordWalletTransactionSafe({
            walletId: wallet.id,
            type: 'PAYOUT_REQUEST_CREATED',
            direction: 'DEBIT',
            balanceSource: payoutSource,
            amount: dto.amount,
            payoutRequestId: localPayout.id,
            actorUserId: userId,
            note: 'Создана заявка пользователя на вывод',
        });

        try {
            const response = await fetch(this.kassa24Endpoint('withdraw'), {
                method: 'POST',
                headers: this.kassa24Headers(),
                body: JSON.stringify({
                    amount: Math.round(dto.amount * 100),
                    externalId: localPayout.id,
                    merchantId: this.kassa24Login,
                    userId,
                    cardNumber: dto.cardNumber.replace(/\s+/g, ''),
                    callbackUrl: this.backendCallbackUrl('/wallet/payout/callback'),
                    demo: this.kassa24Demo,
                }),
            });
            const data: any = await response.json().catch(() => ({}));
            if (!response.ok) {
                return {
                    ...localPayout,
                    provider: 'MANUAL',
                    source: payoutSource,
                    withdrawId: null,
                    message: 'Заявка на вывод создана. Онлайн-сервис временно недоступен, администратор обработает её вручную.',
                };
            }
            return {
                ...localPayout,
                provider: 'ONLINE',
                source: payoutSource,
                withdrawId:
                    data?.id ||
                    data?.withdraw_id ||
                    data?.withdrawId ||
                    data?.payoutId ||
                    localPayout.id,
                message: data?.message || 'Заявка на вывод создана',
            };
        } catch (e: any) {
            if (e instanceof BadRequestException) throw e;
            return {
                ...localPayout,
                provider: 'MANUAL',
                source: payoutSource,
                withdrawId: null,
                message: 'Заявка на вывод создана. Онлайн-сервис временно недоступен, администратор обработает её вручную.',
            };
        }
    }

    async addBonus(userId: string, amount: number) {
        const wallet = await this.prisma.wallet.findUnique({
            where: { userId },
        });

        if (!wallet) {
            throw new NotFoundException('Кошелёк не найден');
        }

        return this.prisma.wallet.update({
            where: { userId },
            data: { bonus: wallet.bonus + amount },
        });
    }

    async addMoney(userId: string, amount: number) {
        const wallet = await this.prisma.wallet.findUnique({
            where: { userId },
        });

        if (!wallet) {
            throw new NotFoundException('Кошелёк не найден');
        }

        return this.prisma.wallet.update({
            where: { userId },
            data: { money: wallet.money + amount },
        });
    }

    async deductMoney(userId: string, amount: number) {
        const wallet = await this.prisma.wallet.findUnique({
            where: { userId },
        });

        if (!wallet) {
            throw new NotFoundException('Кошелёк не найден');
        }

        if (wallet.money < amount) {
            throw new BadRequestException('Недостаточно средств');
        }

        return this.prisma.wallet.update({
            where: { userId },
            data: { money: wallet.money - amount },
        });
    }

    async transferBonusByPhone(senderUserId: string, recipientPhoneRaw: string, amount: number) {
        const phone = this.normalizePhone(recipientPhoneRaw);
        if (!phone) {
            throw new BadRequestException('Введите корректный номер получателя');
        }
        if (!Number.isFinite(amount) || amount <= 0) {
            throw new BadRequestException('Введите сумму больше нуля');
        }

        const sender = await this.prisma.user.findUnique({
            where: { id: senderUserId },
            include: { wallet: true },
        });
        if (!sender || !sender.wallet) {
            throw new NotFoundException('Кошелёк не найден');
        }

        const recipient = await this.prisma.user.findUnique({
            where: { phone },
            include: { wallet: true },
        });
        if (!recipient || !recipient.wallet) {
            throw new NotFoundException('Пользователь с таким номером не найден');
        }
        if (recipient.id === senderUserId) {
            throw new BadRequestException('Нельзя переводить бонусы себе');
        }
        if (sender.wallet.bonus < amount) {
            throw new BadRequestException('Недостаточно бонусов');
        }

        await this.prisma.$transaction(async (tx) => {
            const senderWallet = await tx.wallet.findUnique({ where: { userId: senderUserId } });
            const recipientWallet = await tx.wallet.findUnique({ where: { userId: recipient.id } });
            if (!senderWallet || !recipientWallet) {
                throw new NotFoundException('Кошелёк не найден');
            }
            if (senderWallet.bonus < amount) {
                throw new BadRequestException('Недостаточно бонусов');
            }
            await tx.wallet.update({
                where: { userId: senderUserId },
                data: { bonus: { decrement: amount } },
            });
            await tx.wallet.update({
                where: { userId: recipient.id },
                data: { bonus: { increment: amount } },
            });
            const txAny = tx as any;
            await txAny.walletTransaction.create({
                data: {
                    walletId: senderWallet.id,
                    type: 'BONUS_TRANSFER_OUT',
                    direction: 'DEBIT',
                    balanceSource: 'BONUS',
                    amount,
                    actorUserId: senderUserId,
                    note: `Transfer to ${recipient.phone}`,
                },
            }).catch(() => null);
            await txAny.walletTransaction.create({
                data: {
                    walletId: recipientWallet.id,
                    type: 'BONUS_TRANSFER_IN',
                    direction: 'CREDIT',
                    balanceSource: 'BONUS',
                    amount,
                    actorUserId: senderUserId,
                    note: `Transfer from ${sender.phone}`,
                },
            }).catch(() => null);
        });

        return {
            success: true,
            amount,
            recipientPhone: recipient.phone,
            message: 'Перевод бонусов выполнен',
        };
    }

    async previewBonusRecipient(senderUserId: string, recipientPhoneRaw: string) {
        const phone = this.normalizePhone(recipientPhoneRaw);
        if (!phone) {
            return { found: false };
        }

        const recipient = await this.prisma.user.findUnique({
            where: { phone },
            select: {
                id: true,
                name: true,
                phone: true,
                wallet: { select: { id: true } },
            },
        });
        if (!recipient || !recipient.wallet) {
            return { found: false };
        }
        if (recipient.id === senderUserId) {
            return { found: false, isSelf: true };
        }

        return {
            found: true,
            name: recipient.name,
            phone: recipient.phone,
        };
    }

    private normalizePhone(raw: string): string {
        const digits = (raw || '').replace(/[^0-9+]/g, '');
        if (digits.startsWith('+7') && digits.length == 12) return digits;
        if (digits.startsWith('7') && digits.length == 11) return `+${digits}`;
        if (digits.startsWith('8') && digits.length == 11) return `+7${digits.substring(1)}`;
        return '';
    }

    private normalizeOnlinePaymentError(
        rawMessage: string,
        action: 'payment' | 'withdraw',
    ): string {
        const message = (rawMessage || '').trim();
        const lower = message.toLowerCase();
        const actionLabel =
            action === 'payment'
                ? 'онлайн-платёж'
                : 'онлайн-вывод';

        if (!message) {
            return `${actionLabel[0].toUpperCase()}${actionLabel.slice(1)} временно недоступен. Попробуйте позже.`;
        }

        if (
            lower.includes('merchant was blocked') ||
            lower.includes('merchant blocked') ||
            lower.includes('your merchant was blocked') ||
            lower.includes('contact with manager')
        ) {
            return 'Онлайн-пополнение временно недоступно: платёжный аккаунт заблокирован у провайдера. Нужно обратиться к менеджеру платёжного сервиса.';
        }

        if (
            lower === 'server error' ||
            lower.includes('failed to fetch') ||
            lower.includes('fetch failed') ||
            lower.includes('socket hang up') ||
            lower.includes('unexpected token') ||
            lower.includes('html')
        ) {
            return `${actionLabel[0].toUpperCase()}${actionLabel.slice(1)} временно недоступен. Попробуйте позже.`;
        }

        if (lower.includes('ссылка на онлайн-оплату не была возвращена')) {
            return 'Не удалось создать ссылку на онлайн-оплату. Попробуйте позже.';
        }

        return message;
    }

    private kassa24Headers(): Record<string, string> {
        if (!this.kassa24Login || !this.kassa24Password) {
            throw new ServiceUnavailableException(
                'Онлайн-пополнение временно недоступно: не настроены реквизиты Kassa24.',
            );
        }
        return {
            'Content-Type': 'application/json',
            Authorization: `Basic ${Buffer.from(`${this.kassa24Login}:${this.kassa24Password}`).toString('base64')}`,
        };
    }

    private kassa24Endpoint(path: string) {
        const base = this.kassa24BaseUrl.replace(/\/+$/, '');
        const suffix = path.replace(/^\/+/, '');
        return `${base}/${suffix}`;
    }

    private backendCallbackUrl(path: string) {
        const base = (
            process.env.BACKEND_PUBLIC_URL ||
            process.env.PUBLIC_API_URL ||
            'https://intercity-backend-176647550231.us-central1.run.app/api'
        ).replace(/\/+$/, '');
        return `${base}/${path.replace(/^\/+/, '')}`;
    }

    private extractExternalOrderId(body: Record<string, any>): string | null {
        const metadata = this.extractMetadata(body);
        const value =
            body.order_id ??
            body.orderId ??
            body.invoice_id ??
            body.invoiceId ??
            body.payment_id ??
            body.paymentId ??
            body.id ??
            metadata.order_id ??
            metadata.orderId ??
            metadata.invoice_id ??
            metadata.invoiceId ??
            metadata.payment_id ??
            metadata.paymentId;
        const text = value?.toString?.().trim();
        return text || null;
    }

    private extractLocalTopupId(body: Record<string, any>): string | null {
        const metadata = this.extractMetadata(body);
        const value =
            body.topupRequestId ??
            body.topup_request_id ??
            body.localTopupId ??
            body.local_topup_id ??
            body.reference ??
            body.reference_id ??
            metadata.topupRequestId ??
            metadata.topup_request_id ??
            metadata.localTopupId ??
            metadata.local_topup_id ??
            metadata.reference ??
            metadata.reference_id;
        const text = value?.toString?.().trim();
        return text || null;
    }

    private extractMetadata(body: Record<string, any>): Record<string, any> {
        const metadata = body.metadata;
        if (metadata && typeof metadata === 'object' && !Array.isArray(metadata)) {
            return metadata as Record<string, any>;
        }
        if (typeof metadata === 'string') {
            try {
                const parsed = JSON.parse(metadata);
                if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
                    return parsed as Record<string, any>;
                }
            } catch {
                return {};
            }
        }
        return {};
    }

    private isPaymentPaid(body: Record<string, any>): boolean {
        const status = (
            body.status ??
            body.payment_status ??
            body.paymentStatus ??
            body.state ??
            body.result
        )?.toString?.().trim().toUpperCase();
        if (!status) {
            return body.paid === true || body.success === true;
        }
        return [
            'PAID',
            'SUCCESS',
            'SUCCESSFUL',
            'APPROVED',
            'COMPLETED',
            'CONFIRMED',
            'PAYED',
            '1',
        ].includes(status);
    }

    private async recordWalletTransactionSafe(input: {
        walletId: string;
        type: string;
        direction: 'DEBIT' | 'CREDIT';
        balanceSource: 'MONEY' | 'BONUS';
        amount: number;
        note?: string;
        actorUserId?: string;
        orderId?: string;
        topupRequestId?: string;
        payoutRequestId?: string;
    }) {
        try {
            await (this.prisma as any).walletTransaction.create({
                data: {
                    walletId: input.walletId,
                    type: input.type,
                    direction: input.direction,
                    balanceSource: input.balanceSource,
                    amount: input.amount,
                    note: input.note ?? null,
                    actorUserId: input.actorUserId ?? null,
                    orderId: input.orderId ?? null,
                    topupRequestId: input.topupRequestId ?? null,
                    payoutRequestId: input.payoutRequestId ?? null,
                },
            });
        } catch (_) {
            // Keep wallet operations functional if migration not yet applied.
        }
    }

    private async createPayoutRequestCompat(db: { payoutRequest: any }, input: {
        walletId: string;
        amount: number;
        source: 'MONEY' | 'BONUS';
    }) {
        const includeSource = await this.supportsPayoutSourceColumn();
        return await db.payoutRequest.create({
            data: includeSource
                ? {
                    walletId: input.walletId,
                    amount: input.amount,
                    status: 'PENDING',
                    source: input.source,
                }
                : {
                    walletId: input.walletId,
                    amount: input.amount,
                    status: 'PENDING',
                },
        });
    }

    private async supportsPayoutSourceColumn(): Promise<boolean> {
        if (this.payoutSourceColumnSupported != null) {
            return this.payoutSourceColumnSupported;
        }

        try {
            await this.prisma.payoutRequest.findFirst({
                select: { source: true },
            });
            this.payoutSourceColumnSupported = true;
        } catch (error) {
            if (!this.isMissingPayoutSourceColumnError(error)) {
                throw error;
            }
            this.payoutSourceColumnSupported = false;
        }

        return this.payoutSourceColumnSupported;
    }

    private isMissingPayoutSourceColumnError(error: unknown): boolean {
        const message =
            error instanceof Error ? error.message : String(error ?? '');
        const lower = message.toLowerCase();
        return lower.includes('does not exist') && (
            lower.includes('payoutrequest.source') ||
            lower.includes('column `source`') ||
            lower.includes("column 'source'") ||
            lower.includes(' column source')
        );
    }

    private isPayoutStorageUnavailableError(error: unknown): boolean {
        const message =
            error instanceof Error ? error.message : String(error ?? '');
        if (this.isMissingPayoutSourceColumnError(error)) {
            return true;
        }

        return message.includes('PayoutRequest') && (
            message.includes('does not exist') ||
            message.includes('Unknown argument') ||
            message.includes('Unknown field')
        );
    }
}
