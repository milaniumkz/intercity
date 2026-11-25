import { BadRequestException, ForbiddenException, Injectable, Logger, NotFoundException, OnModuleDestroy, OnModuleInit, Optional, ServiceUnavailableException } from '@nestjs/common';
import { createCipheriv, createDecipheriv, createHash, randomBytes, randomUUID } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { PushService } from '../notifications/push.service';
import { RealtimeService } from '../realtime/realtime.service';
import { recordTaxIncome } from '../tax/tax-ledger';
import { VtbSandboxApiError, VtbSandboxGateway } from './vtb-sandbox-gateway';

const PROVIDER = 'VTB_SANDBOX';
const ACTIVE = ['PENDING', 'PROCESSING', 'CHECKING', 'ACTION_REQUIRED', 'PAID', 'REFUND_PENDING'];
const RATE = 7;
function amountMinor(value: number) {
    const minor = Math.round(value * 100);
    if (!Number.isFinite(value) || minor < 100 || minor > 10000000 || Math.abs(value * 100 - minor) > 0.00001) throw new BadRequestException('Стоимость ВТБ: от 1 до 100 000 ₽, до двух знаков после запятой');
    return minor;
}
export function vtbTripBankState(data: any, orderNumber: string, bankMinor: number) {
    if (!data || data.orderNumber !== orderNumber || String(data.currency) !== '398' || data.amount !== bankMinor ||
        ('errorCode' in data && String(data.errorCode) !== '0') || ('success' in data && data.success !== true)) return 'UNVERIFIED';
    if (Number(data.orderStatus) === 2 && String(data.actionCode) === '0') return 'PAID';
    if (Number(data.orderStatus) === 4 && Number(data.paymentAmountInfo?.refundedAmount) === bankMinor) return 'REFUNDED';
    if (Number(data.orderStatus) === 3) return 'REVERSED';
    if (Number(data.orderStatus) === 6 && Number(data.paymentAmountInfo?.depositedAmount || 0) === 0) return 'FAILED';
    if (Number(data.orderStatus) === 0 && Number(data.paymentAmountInfo?.approvedAmount) === 0 && Number(data.paymentAmountInfo?.depositedAmount) === 0 &&
        [4,5,20,100,101,111,116,120,121,123,125,203,204,208,212,71015].includes(Number(data.actionCode))) return 'DECLINED';
    if ([0, 1, 5].includes(Number(data.orderStatus))) return 'PENDING';
    return 'UNVERIFIED';
}
@Injectable()
export class VtbTripPaymentsService implements OnModuleInit, OnModuleDestroy {
    readonly gateway = new VtbSandboxGateway({
        userName: process.env.VTB_SANDBOX_USER_NAME || '',
        password: process.env.VTB_SANDBOX_PASSWORD || Buffer.from(process.env.VTB_SANDBOX_PASSWORD_B64 || '', 'base64').toString('utf8'),
    });
    private timer?: NodeJS.Timeout;
    private busy = false;
    private bindingCapability?: { at: number; enabled: boolean };
    private async canBind(userId: string, force = false) {
        if (!this.enabled) return false;
        if (!force && this.bindingCapability && Date.now() - this.bindingCapability.at < 300000) return this.bindingCapability.enabled;
        let enabled = false;
        try { const data = await this.gateway.bindings(userId); enabled = Array.isArray(data.bindings); } catch {}
        this.bindingCapability = { at: Date.now(), enabled }; return enabled;
    }
    private readonly logger = new Logger(VtbTripPaymentsService.name);
    constructor(private readonly prisma: PrismaService, private readonly realtime: RealtimeService, @Optional() private readonly push?: PushService) {}
    private get autoPaymentsEnabled() { return process.env.VTB_SANDBOX_AUTO_PAYMENTS_ENABLED === 'true'; }
    get enabled() { return process.env.VTB_SANDBOX_ENABLED === 'true' && this.gateway.configured; }
    onModuleInit() { this.timer = setInterval(() => void this.tick().catch(() => this.logger.warn('VTB trip reconciliation will retry')), 3000); this.timer.unref(); }
    onModuleDestroy() { if (this.timer) clearInterval(this.timer); }
    async isRussian(userId: string) {
        const user = await this.prisma.user.findUnique({ where: { id: userId }, select: { city: { select: { countryCode: true } } } });
        return user?.city?.countryCode?.toUpperCase() === 'RU';
    }
    private async requireActor(userId: string) {
        if (!await this.isRussian(userId)) throw new ForbiddenException('ВТБ доступен для российского профиля');
        if (!this.enabled) throw new ServiceUnavailableException('ВТБ пока недоступен');
    }
    private key() {
        const secret = process.env.KASSA24_TOKEN_ENCRYPTION_KEY || process.env.JWT_SECRET || '';
        if (secret.length < 32) throw new ServiceUnavailableException('Сохранение карты пока недоступно');
        return createHash('sha256').update('intercity:saved-payment-card:v1:' + secret).digest();
    }
    private encrypt(value: string) {
        const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', this.key(), iv);
        return Buffer.concat([iv, cipher.update(value, 'utf8'), cipher.final(), cipher.getAuthTag()]).toString('base64');
    }
    private decrypt(value: string) {
        const data = Buffer.from(value, 'base64'), cipher = createDecipheriv('aes-256-gcm', this.key(), data.subarray(0, 12));
        cipher.setAuthTag(data.subarray(-16)); return Buffer.concat([cipher.update(data.subarray(12, -16)), cipher.final()]).toString('utf8');
    }
    private api(path: string) {
        const url = new URL(process.env.PUBLIC_API_URL || process.env.BACKEND_PUBLIC_URL || 'https://api.intercity.89-207-255-27.sslip.io');
        if (url.protocol !== 'https:') throw new ServiceUnavailableException('Адрес ВТБ не настроен');
        return url.origin + '/api/payments/vtb/trips/' + path;
    }
    async cards(userId: string, sync = false) {
        if (sync) { await this.requireActor(userId); await this.syncCards(userId); }
        const canBind = await this.canBind(userId);
        const cards = await this.prisma.savedPaymentCard.findMany({ where: { userId, provider: PROVIDER, active: true }, orderBy: { createdAt: 'desc' } });
        const binding = await this.prisma.cardBinding.findFirst({ where: { userId, provider: PROVIDER }, orderBy: { createdAt: 'desc' } });
        return { provider: PROVIDER, configured: this.enabled, currencies: ['RUB'], paymentMode: 'TEST',
            bindingAmount: 1, bindingCurrency: 'KZT', automaticDebitAvailable: this.autoPaymentsEnabled, cardBindingAvailable: canBind,
            message: !canBind ? 'ВТБ · тестовый контур. Банк ещё не включил сохранение карт для InterCity. Пока вводите карту на странице ВТБ при оплате поездки.' : 'ВТБ · тестовый контур. Привязка: 1 ₸ с автоматическим возвратом. Выберите «Сохранить карту» в форме банка. При поездке банк может запросить CVC или 3-D Secure.',
            cards: cards.map(c => ({ id: c.id, last4: c.last4, isDefault: c.isDefault })),
            binding: binding ? { id: binding.id, status: binding.status, url: binding.status === 'PENDING' ? binding.paymentUrl : null, message: binding.lastError } : null };
    }
    async syncCards(userId: string) {
        let data: any;
        try { data = await this.gateway.bindings(userId); }
        catch (error) {
            if (error instanceof VtbSandboxApiError && error.code === '5' && !await this.prisma.savedPaymentCard.count({ where: { userId, provider: PROVIDER } })) return;
            throw error;
        }
        if (!Array.isArray(data.bindings)) throw new BadRequestException('ВТБ не подтвердил список карт');
        await this.prisma.$transaction(async tx => {
            await tx.$executeRawUnsafe('SELECT id FROM "User" WHERE id=$1 FOR UPDATE', userId);
            const actor = await tx.user.findUnique({ where: { id: userId } });
            if (!actor) throw new NotFoundException('Аккаунт удалён');
            let hasDefault = !!await tx.savedPaymentCard.findFirst({ where: { userId, provider: PROVIDER, active: true, isDefault: true } });
            for (const binding of data.bindings) {
                if (typeof binding.bindingId !== 'string' || !binding.bindingId || binding.bindingId.length > 255 ||
                    (binding.clientId && binding.clientId !== userId) || binding.active === false) continue;
                const last4 = String(binding.displayLabel || binding.maskedPan || '').replace(/\D/g, '').slice(-4);
                if (last4.length !== 4) continue;
                const tokenHash = createHash('sha256').update(PROVIDER + ':' + (process.env.VTB_SANDBOX_USER_NAME || '') + ':' + binding.bindingId).digest('hex');
                const old = await tx.savedPaymentCard.findUnique({ where: { tokenHash } });
                if (old && (old.userId !== userId || !old.active)) continue;
                const card = await tx.savedPaymentCard.upsert({ where: { tokenHash }, update: { last4 }, create: {
                    userId, provider: PROVIDER, phone: actor.phone, tokenEncrypted: this.encrypt(binding.bindingId), tokenHash, last4,
                    acquiringId: 0, demo: true, isDefault: !hasDefault,
                } });
                hasDefault = hasDefault || card.isDefault;
            }
        });
    }
    async select(userId: string, id: string) {
        await this.requireActor(userId);
        await this.prisma.$transaction(async tx => {
            await tx.$executeRawUnsafe('SELECT id FROM "User" WHERE id=$1 FOR UPDATE', userId);
            const card = await tx.savedPaymentCard.findFirst({ where: { id, userId, provider: PROVIDER, active: true } });
            if (!card) throw new NotFoundException('Карта не найдена');
            await tx.savedPaymentCard.updateMany({ where: { userId, provider: PROVIDER }, data: { isDefault: false } });
            await tx.savedPaymentCard.update({ where: { id }, data: { isDefault: true } });
        });
        return this.cards(userId);
    }
    async remove(userId: string, id: string) {
        const card = await this.prisma.savedPaymentCard.findFirst({ where: { id, userId, provider: PROVIDER, active: true } });
        if (!card) throw new NotFoundException('Карта не найдена');
        if (await this.prisma.tripCardPayment.count({ where: { cardId: id, status: { in: ACTIVE } } })) throw new BadRequestException('Дождитесь завершения оплаты поездки');
        await this.gateway.unbind(this.decrypt(card.tokenEncrypted));
        await this.prisma.$transaction(async tx => {
            await tx.$executeRawUnsafe('SELECT id FROM "User" WHERE id=$1 FOR UPDATE', userId);
            await tx.savedPaymentCard.update({ where: { id }, data: { active: false, isDefault: false } });
            const next = await tx.savedPaymentCard.findFirst({ where: { userId, provider: PROVIDER, active: true, isDefault: false } });
            if (next) await tx.savedPaymentCard.update({ where: { id: next.id }, data: { isDefault: true } });
        });
        return this.cards(userId);
    }
    async bind(userId: string) {
        await this.requireActor(userId); this.key();
        if (!await this.canBind(userId, true)) throw new BadRequestException('ВТБ ещё не разрешил сохранение карт для InterCity. Привязка и списание 1 ₸ не запускались');
        const binding = await this.prisma.$transaction(async tx => {
            await tx.$executeRawUnsafe('SELECT id FROM "User" WHERE id=$1 FOR UPDATE', userId);
            const pending = await tx.cardBinding.findFirst({ where: { userId, provider: PROVIDER, status: { in: ['CREATED','PENDING','CHECKING','REFUND_PENDING'] } } });
            if (pending) return pending;
            const actor = await tx.user.findUniqueOrThrow({ where: { id: userId } });
            return tx.cardBinding.create({ data: { userId, phone: actor.phone, acquiringId: 0, demo: true, provider: PROVIDER, status: 'CREATED' } });
        });
        await this.processBinding(binding.id);
        const current = await this.prisma.cardBinding.findUniqueOrThrow({ where: { id: binding.id } });
        return { bindingId: current.id, url: current.status === 'PENDING' ? current.paymentUrl : null, provider: PROVIDER, amount: 1, currency: 'KZT', status: current.status,
            message: 'Отметьте «Сохранить карту», оплатите 1 ₸. После подтверждения ВТБ сумма автоматически возвращается.' };
    }
    async cardForOrder(userId: string) {
        await this.requireActor(userId);
        return (await this.prisma.savedPaymentCard.findFirst({ where: { userId, provider: PROVIDER, active: true, isDefault: true } }))?.id || null;
    }
    async prepare(tx: any, kind: string, trip: any, driverUserId?: string) {
        if (trip.currency !== 'RUB' || trip.paymentMethod !== 'CARD') return;
        if (!this.enabled) throw new ServiceUnavailableException('ВТБ пока недоступен');
        const minor = amountMinor(trip.price);
        const payment = await tx.tripCardPayment.upsert({ where: { id: kind + ':' + trip.id }, update: {}, create: {
            id: kind + ':' + trip.id, provider: PROVIDER, kind, tripId: trip.id, passengerId: trip.passengerId,
            driverUserId: driverUserId || null, cardId: trip.paymentCardId || null, amount: minor / 100, currency: 'RUB',
            bankOrderNumber: randomUUID(), bankAmountMinor: minor * RATE, conversionRate: RATE, attempts: 1,
        } });
        if (payment.provider !== PROVIDER || amountMinor(payment.amount) !== minor) throw new BadRequestException('Стоимость оплачиваемой поездки изменилась');
    }
    async assertPaid(tx: any, kind: string, trip: any, driverUserId: string) {
        if (trip.currency !== 'RUB' || trip.paymentMethod !== 'CARD') return;
        await tx.$executeRawUnsafe('SELECT id FROM "TripCardPayment" WHERE id=$1 FOR UPDATE', kind + ':' + trip.id);
        const p = await tx.tripCardPayment.findUnique({ where: { id: kind + ':' + trip.id } });
        if (!p || p.provider !== PROVIDER || !['PAID','SETTLED'].includes(p.status) || amountMinor(p.amount) !== amountMinor(trip.price)) throw new BadRequestException('Пассажир ещё не подтвердил оплату ВТБ. Начать поездку можно после оплаты');
        await tx.tripCardPayment.update({ where: { id: p.id }, data: { driverUserId } });
    }
    async settle(tx: any, kind: string, trip: any, driverUserId: string) {
        if (trip.currency !== 'RUB' || trip.paymentMethod !== 'CARD') return;
        await this.assertPaid(tx, kind, trip, driverUserId);
        const id = kind + ':' + trip.id;
        const p = await tx.tripCardPayment.findUniqueOrThrow({ where: { id } });
        if (p.earningsCredited || p.status === 'SETTLED') return;
        const wallet = await tx.wallet.upsert({ where: { userId: driverUserId }, create: { userId: driverUserId }, update: {} });
        await tx.wallet.update({ where: { id: wallet.id }, data: { moneyRub: { increment: p.amount } } });
        await tx.walletTransaction.create({ data: {
            id: p.bankOrderNumber, walletId: wallet.id, currency: 'RUB', type: 'CARD_RIDE_EARNINGS', direction: 'CREDIT',
            balanceSource: 'MONEY', amount: p.amount, idempotencyKey: 'card-earnings:' + id,
            orderId: kind === 'CITY' ? trip.id : null, intercityRequestId: kind === 'INTERCITY' ? trip.id : null,
            note: 'Оплата поездки ВТБ · тестовый контур',
        } });
        await tx.tripCardPayment.update({ where: { id }, data: { status: 'SETTLED', earningsCredited: true, driverUserId } });
        await recordTaxIncome(tx, { key: 'driver-income:' + kind + ':' + trip.id, userId: driverUserId, sourceKind: kind === 'CITY' ? 'CITY' : 'INTERCITY',
            sourceId: trip.id, gross: p.amount, currency: 'RUB', occurredAt: trip.completedAt || new Date() });
    }
    async checkout(userId: string, kind: string, tripId: string) {
        if (!['CITY','INTERCITY'].includes(kind)) throw new BadRequestException('Некорректный тип поездки');
        const trip: any = kind === 'CITY' ? await this.prisma.order.findUnique({ where: { id: tripId } }) : await this.prisma.intercityRequest.findUnique({ where: { id: tripId } });
        if (!trip || trip.passengerId !== userId) throw new NotFoundException('Поездка не найдена');
        const p = await this.prisma.tripCardPayment.findUnique({ where: { id: kind + ':' + tripId } });
        if (!p || p.provider !== PROVIDER) throw new BadRequestException(kind === 'CITY' && trip.requestType !== 'CITY_AUCTION' ? 'Оплата начнётся после принятия заказа водителем' : 'Оплата будет доступна после выбора предложения и согласования цены');
        await this.processPayment(p.id);
        const latest = await this.prisma.tripCardPayment.findUniqueOrThrow({ where: { id: p.id } });
        return this.publicPayment(latest);
    }
    private publicPayment(p: any) {
        return { provider: PROVIDER, status: p.status, attempts: p.attempts, attemptLimit: 3, amount: p.amount, currency: 'RUB', bankAmount: p.bankAmountMinor / 100,
            bankCurrency: 'KZT', conversionRate: p.conversionRate, paymentMode: 'TEST', paymentUrl: p.status === 'ACTION_REQUIRED' ? p.paymentUrl : null,
            paidAt: p.paidAt, lastError: p.lastError, earningsCredited: p.earningsCredited };
    }
    async returnTarget(kind: string, tripId: string) {
        const url = new URL(process.env.PUBLIC_WEB_URL || process.env.FRONTEND_URL || 'https://intercity.89-207-255-27.sslip.io');
        if (url.protocol !== 'https:') throw new ServiceUnavailableException('Адрес возврата не настроен');
        url.hash = kind === 'BIND' ? '/profile/payments' : (kind === 'INTERCITY' ? '/market/request/' : '/order/searching/') + encodeURIComponent(tripId);
        return url.toString();
    }
    async tick() {
        if (!this.enabled || this.busy) return; this.busy = true;
        try {
            const bindings = await this.prisma.cardBinding.findMany({ where: { provider: PROVIDER, status: { in: ['CREATED','PENDING','CHECKING','REFUND_PENDING'] } }, take: 5, orderBy: { updatedAt: 'asc' } });
            for (const b of bindings) await this.processBinding(b.id).catch(() => undefined);
            const payments = await this.prisma.tripCardPayment.findMany({ where: { provider: PROVIDER, status: { in: ACTIVE }, nextCheckAt: { lte: new Date() } }, take: 5, orderBy: { nextCheckAt: 'asc' } });
            for (const p of payments) await this.processPayment(p.id).catch(() => undefined);
            const watched = await this.prisma.cardPaymentAttempt.findMany({where:{watchBank:true,nextCheckAt:{lte:new Date()}},take:10,orderBy:{nextCheckAt:'asc'}});
            for (const attempt of watched) await this.processAttemptWatch(attempt.id).catch(() => undefined);
        } finally { this.busy = false; }
    }

    async processAttemptWatch(id: string) {
        const claimed = await this.prisma.cardPaymentAttempt.updateMany({where:{id,watchBank:true,OR:[{leaseUntil:null},{leaseUntil:{lte:new Date()}}]},data:{leaseUntil:new Date(Date.now()+120000)}});
        if (!claimed.count) return;
        try {
            const attempt = await this.prisma.cardPaymentAttempt.findUniqueOrThrow({where:{id}});
            const parent = await this.prisma.tripCardPayment.findUnique({where:{id:attempt.paymentId}});
            if (parent && parent.provider !== PROVIDER) throw new Error('Unexpected watched provider');
            const minor = attempt.bankAmountMinor ?? parent?.bankAmountMinor;
            if (!attempt.providerId || !attempt.merchantOrderNumber || !Number.isSafeInteger(minor) || !minor || minor < 1) throw new Error('Unresolved bank attempt');
            let bank = await this.gateway.status(attempt.providerId);
            let state = vtbTripBankState(bank,attempt.merchantOrderNumber,minor);
            if (state === 'PAID') {
                // A rejected hosted form can remain payable. Never credit this old attempt.
                await this.gateway.refund(attempt.providerId,minor,attempt.merchantOrderNumber);
                bank = await this.gateway.status(attempt.providerId);
                state = vtbTripBankState(bank,attempt.merchantOrderNumber,minor);
            }
            if (['FAILED','REFUNDED','REVERSED'].includes(state)) {
                await this.prisma.$transaction(async tx=>{
                    await tx.cardPaymentAttempt.update({where:{id},data:{watchBank:false,status:state === 'FAILED'?'FAILED':'REFUNDED'}});
                    if (state !== 'FAILED' && parent && parent.bankOrderNumber === attempt.merchantOrderNumber) {
                        await tx.tripCardPayment.updateMany({where:{id:parent.id,status:{in:['CASH','CANCELLED','REFUND_PENDING']}},data:{
                            ...(parent.status === 'CASH'?{}:{status:'REFUNDED'}),refundedAt:new Date(),
                            lastError:parent.status === 'CASH'?'Позднее списание по старой форме ВТБ возвращено. Поездка оплачивается наличными.':null,
                        }});
                    }
                });
            }
        } catch { this.logger.warn('VTB old-attempt reconciliation will retry'); }
        finally { await this.prisma.cardPaymentAttempt.update({where:{id},data:{leaseUntil:null,nextCheckAt:new Date(Date.now()+30000)}}); }
    }

    async processBinding(id: string) {
        const claim = await this.prisma.cardBinding.updateMany({ where: { id, provider: PROVIDER, status: { in: ['CREATED','PENDING','CHECKING','REFUND_PENDING'] }, OR: [{ leaseUntil: null }, { leaseUntil: { lte: new Date() } }] }, data: { leaseUntil: new Date(Date.now() + 120000) } });
        if (!claim.count) return;
        try {
            let b = await this.prisma.cardBinding.findUniqueOrThrow({ where: { id } });
            if (!b.providerId) {
                const r = await this.gateway.register({ orderNumber: id, amountMinor: 100, clientId: b.userId, acceptDuplicate: true,
                    returnUrl: this.api('return?kind=BIND&tripId=' + id), callbackUrl: this.api('callback') });
                b = await this.prisma.cardBinding.update({ where: { id }, data: { providerId: r.orderId, paymentUrl: r.paymentUrl, status: 'CHECKING' } });
            }
            const status = await this.gateway.status(b.providerId!);
            const state = vtbTripBankState(status, id, 100);
            if (state === 'PAID') {
                await this.prisma.cardBinding.update({ where: { id }, data: { status: 'REFUND_PENDING' } });
                await this.gateway.refund(b.providerId!, 100, id);
                const after = await this.gateway.status(b.providerId!);
                if (vtbTripBankState(after, id, 100) !== 'REFUNDED') throw new Error('Refund awaiting confirmation');
                await this.syncCards(b.userId);
                const hasCard = !!await this.prisma.savedPaymentCard.findFirst({ where: { userId: b.userId, provider: PROVIDER, active: true } });
                await this.prisma.cardBinding.update({ where: { id }, data: { status: hasCard ? 'SYNCED' : 'NOT_SAVED',
                    lastError: hasCard ? null : '1 ₸ возвращён. Карта не сохранена: при добавлении отметьте «Сохранить карту» в форме ВТБ.' } });
            } else if (state === 'REFUNDED') {
                await this.syncCards(b.userId);
                const hasCard = !!await this.prisma.savedPaymentCard.findFirst({ where: { userId: b.userId, provider: PROVIDER, active: true } });
                await this.prisma.cardBinding.update({ where: { id }, data: { status: hasCard ? 'SYNCED' : 'NOT_SAVED', lastError: hasCard ? null : '1 ₸ возвращён; сохранение карты не подтверждено банком' } });
            } else if (['FAILED','REVERSED'].includes(state)) await this.prisma.cardBinding.update({ where: { id }, data: { status: 'CANCELLED', lastError: 'Привязка карты отменена' } });
            else if (state === 'PENDING') await this.prisma.cardBinding.update({where:{id},data:{status:'PENDING',lastError:null}});
            else if (state === 'UNVERIFIED') throw new Error('Unverified bank response');
        } catch {
            await this.prisma.cardBinding.updateMany({ where: { id, status: { notIn: ['SYNCED','NOT_SAVED','CANCELLED'] } }, data: { lastError: 'Проверяем привязку и возврат 1 ₸. Повторно платить не нужно.' } });
        } finally { await this.prisma.cardBinding.update({ where: { id }, data: { leaseUntil: null } }); }
    }

    private async failedPayment(payment: any, openBankForm: boolean) {
        const fallback = await this.prisma.$transaction(async tx => {
            await tx.$executeRawUnsafe(payment.kind === 'CITY' ? 'SELECT id FROM "Order" WHERE id=$1 FOR UPDATE' : 'SELECT id FROM "IntercityRequest" WHERE id=$1 FOR UPDATE', payment.tripId);
            const trip: any = payment.kind === 'CITY' ? await tx.order.findUnique({where:{id:payment.tripId}}) : await tx.intercityRequest.findUnique({where:{id:payment.tripId}});
            await tx.$executeRawUnsafe('SELECT id FROM "TripCardPayment" WHERE id=$1 FOR UPDATE',payment.id);
            const current = await tx.tripCardPayment.findUniqueOrThrow({where:{id:payment.id}});
            if (current.bankOrderNumber !== payment.bankOrderNumber || current.earningsCredited || ['PAID','SETTLED','CASH','REFUNDED'].includes(current.status)) return false;
            await tx.cardPaymentAttempt.upsert({where:{id:payment.id+':'+current.attempts},update:{status:'FAILED',providerId:current.bankOrderId,watchBank:openBankForm,paymentUrl:current.paymentUrl,bankAmountMinor:current.bankAmountMinor,nextCheckAt:new Date()},
                create:{id:payment.id+':'+current.attempts,paymentId:payment.id,number:current.attempts,merchantOrderNumber:current.bankOrderNumber,providerId:current.bankOrderId,status:'FAILED',watchBank:openBankForm,paymentUrl:current.paymentUrl,bankAmountMinor:current.bankAmountMinor}});
            if (!trip || trip.status === 'CANCELLED') {
                await tx.tripCardPayment.update({where:{id:payment.id},data:{status:'CANCELLED',lastError:null}});return false;
            }
            if (['IN_PROGRESS','COMPLETED'].includes(trip.status)) throw new Error('Cannot change payment of an active paid trip');
            if (current.attempts < 3) {
                await tx.tripCardPayment.update({where:{id:payment.id},data:{status:'PENDING',attempts:current.attempts+1,
                    bankOrderNumber:randomUUID(),bankOrderId:null,paymentUrl:null,chargeAttemptedAt:null,
                    nextCheckAt:new Date(),lastError:'Банк отклонил попытку '+current.attempts+' из 3. Подготовлена следующая попытка оплаты.'}});
                return false;
            }
            await tx.tripCardPayment.update({where:{id:payment.id},data:{status:'CASH',paymentUrl:null,lastError:'Три попытки оплаты отклонены ВТБ. Способ оплаты изменён на наличные.'}});
            if (payment.kind === 'CITY') await tx.order.update({where:{id:payment.tripId},data:{paymentMethod:'CASH',paymentCardId:null}});
            else await tx.intercityRequest.update({where:{id:payment.tripId},data:{paymentMethod:'CASH',paymentCardId:null}});
            return true;
        });
        if (!fallback) return;
        const profile = payment.driverUserId ? await this.prisma.driverProfile.findUnique({where:{userId:payment.driverUserId},select:{id:true}}) : null;
        const payload = {tripId:payment.tripId,kind:payment.kind,paymentStatus:'CASH',paymentMethod:'CASH',driverId:profile?.id,driverUserId:payment.driverUserId};
        this.realtime.publish({type:'order.payment.changed',entity:'order',entityId:payment.tripId,at:new Date().toISOString(),payload});
        if (profile) this.realtime.publish({type:'driver.payment.changed',entity:'driver',entityId:profile.id,at:new Date().toISOString(),payload});
        if (this.push) await Promise.allSettled([payment.passengerId,payment.driverUserId].filter(Boolean).map(userId=>this.push!.sendToUser(userId,{
            title:'Способ оплаты изменён',body:userId === payment.driverUserId ? 'Три попытки оплаты ВТБ отклонены. Заказ переведён на наличные. Получите оплату от пассажира наличными.' : 'Три попытки оплаты ВТБ отклонены. Заказ переведён на наличные. Оплатите поездку водителю наличными.',
            data:{type:'PAYMENT_CASH_FALLBACK',orderId:payment.tripId,kind:payment.kind},
        })));
    }

    async processPayment(id: string) {
        const claim = await this.prisma.tripCardPayment.updateMany({ where: { id, provider: PROVIDER, status: { in: ACTIVE }, OR: [{ leaseUntil: null }, { leaseUntil: { lte: new Date() } }] }, data: { leaseUntil: new Date(Date.now() + 120000) } });
        if (!claim.count) return;
        let retryDelay = 5000;
        try {
            let p = await this.prisma.tripCardPayment.findUniqueOrThrow({ where: { id } });
            await this.prisma.cardPaymentAttempt.upsert({where:{id:p.id+':'+p.attempts},update:{providerId:p.bankOrderId||undefined,paymentUrl:p.paymentUrl||undefined,bankAmountMinor:p.bankAmountMinor},create:{id:p.id+':'+p.attempts,paymentId:p.id,number:p.attempts,merchantOrderNumber:p.bankOrderNumber,providerId:p.bankOrderId,paymentUrl:p.paymentUrl,bankAmountMinor:p.bankAmountMinor,status:'PROCESSING'}});
            let trip: any = p.kind === 'CITY' ? await this.prisma.order.findUnique({ where: { id: p.tripId } }) : await this.prisma.intercityRequest.findUnique({ where: { id: p.tripId } });
            if (!trip) throw new Error('Trip not found');
            if (!p.bankOrderId) {
                if (trip.status === 'CANCELLED') {
                    // A previous register request may have reached the bank before a timeout.
                    try {
                        const found = await this.gateway.statusByOrderNumber(p.bankOrderNumber!);
                        const bankId = found.attributes?.find((a: any) => a.name === 'mdOrder')?.value;
                        if (!bankId || !/^[a-f0-9-]{36}$/i.test(bankId)) throw new Error('Unresolved bank registration');
                        p = await this.prisma.tripCardPayment.update({where:{id},data:{bankOrderId:bankId,status:'REFUND_PENDING'}});
                    } catch (error) {
                        if (error instanceof VtbSandboxApiError && error.code === '6') {
                            await this.prisma.tripCardPayment.update({where:{id},data:{status:'CANCELLED',lastError:null}});return;
                        }
                        throw error;
                    }
                }
                if (!p.bankOrderId) {
                const card = p.cardId ? await this.prisma.savedPaymentCard.findFirst({ where: { id: p.cardId, userId: p.passengerId, provider: PROVIDER, active: true } }) : null;
                const r = await this.gateway.register({ orderNumber: p.bankOrderNumber!, amountMinor: p.bankAmountMinor!, clientId: p.passengerId,
                    bindingId: card ? this.decrypt(card.tokenEncrypted) : undefined, acceptDuplicate: true,
                    returnUrl: this.api('return?kind=' + p.kind + '&tripId=' + p.tripId), callbackUrl: this.api('callback') });
                p = await this.prisma.tripCardPayment.update({ where: { id }, data: { bankOrderId: r.orderId, paymentUrl: r.paymentUrl, status: 'CHECKING' } });
                }
            }
            if (p.status === 'PAID' && trip.status !== 'CANCELLED') return;
            await this.prisma.cardPaymentAttempt.update({where:{id:p.id+':'+p.attempts},data:{providerId:p.bankOrderId,paymentUrl:p.paymentUrl}});
            let bank = await this.gateway.status(p.bankOrderId!);
            let state = vtbTripBankState(bank, p.bankOrderNumber!, p.bankAmountMinor!);
            if (trip.status !== 'CANCELLED' && state === 'PENDING' && p.cardId && !p.chargeAttemptedAt && this.autoPaymentsEnabled) {
                const card = await this.prisma.savedPaymentCard.findFirst({ where: { id: p.cardId, userId: p.passengerId, provider: PROVIDER, active: true } });
                if (card) {
                    await this.prisma.tripCardPayment.update({ where: { id }, data: { chargeAttemptedAt: new Date() } });
                    // Only one automatic attempt; any ambiguous result keeps this SAME bank order.
                    await this.gateway.payBinding(p.bankOrderId!, this.decrypt(card.tokenEncrypted)).catch(() => undefined);
                    bank = await this.gateway.status(p.bankOrderId!);
                    state = vtbTripBankState(bank, p.bankOrderNumber!, p.bankAmountMinor!);
                }
            }
            trip = p.kind === 'CITY' ? await this.prisma.order.findUnique({ where: { id: p.tripId } }) : await this.prisma.intercityRequest.findUnique({ where: { id: p.tripId } });
            if (['FAILED','DECLINED'].includes(state) && trip?.status !== 'CANCELLED') { await this.failedPayment(p, state === 'DECLINED'); return; }
            if (trip?.status === 'CANCELLED') {
                if (state === 'PAID') {
                    await this.prisma.tripCardPayment.update({ where: { id }, data: { status: 'REFUND_PENDING', paidAt: p.paidAt || new Date() } });
                    await this.gateway.refund(p.bankOrderId!, p.bankAmountMinor!, p.bankOrderNumber!);
                } else if (['PENDING','DECLINED'].includes(state)) {
                    if (Number(bank.orderStatus) === 1) await this.gateway.reverse(p.bankOrderId!);
                    else if (!p.bankCancellationUnsupported) {
                        try { await this.gateway.decline(p.bankOrderId!, p.bankOrderNumber!); }
                        catch (error) {
                            if (!(error instanceof VtbSandboxApiError) || error.code !== '8') throw error;
                            p = await this.prisma.tripCardPayment.update({where:{id},data:{bankCancellationUnsupported:true,status:'REFUND_PENDING'}});
                        }
                    }
                }
                bank = await this.gateway.status(p.bankOrderId!);
                state = vtbTripBankState(bank, p.bankOrderNumber!, p.bankAmountMinor!);
                if (['PENDING','DECLINED'].includes(state) && p.bankCancellationUnsupported) {
                    retryDelay = 30000;
                    await this.prisma.tripCardPayment.update({where:{id},data:{status:'REFUND_PENDING',lastError:'Заказ отменён. Если банк подтвердит списание по старой форме, сумма автоматически вернётся.'}});
                    return;
                }
                if (!['REFUNDED','REVERSED','FAILED'].includes(state)) throw new Error('Cancellation awaits bank');
                await this.prisma.cardPaymentAttempt.update({where:{id:p.id+':'+p.attempts},data:{status:['REFUNDED','REVERSED'].includes(state)?'REFUNDED':'CANCELLED'}});
                await this.prisma.tripCardPayment.update({ where: { id }, data: { status: ['REFUNDED','REVERSED'].includes(state) ? 'REFUNDED' : 'CANCELLED', refundedAt: ['REFUNDED','REVERSED'].includes(state) ? new Date() : null, lastError: null } });
            } else {
                await this.prisma.$transaction(async tx => {
                    await tx.$executeRawUnsafe(p.kind === 'CITY' ? 'SELECT id FROM "Order" WHERE id=$1 FOR UPDATE' : 'SELECT id FROM "IntercityRequest" WHERE id=$1 FOR UPDATE', p.tripId);
                    const current = p.kind === 'CITY' ? await tx.order.findUnique({ where: { id: p.tripId } }) : await tx.intercityRequest.findUnique({ where: { id: p.tripId } });
                    const latest = await tx.tripCardPayment.findUniqueOrThrow({ where: { id } });
                    if (latest.bankOrderNumber !== p.bankOrderNumber || latest.earningsCredited || latest.status === 'SETTLED') return;
                    await tx.cardPaymentAttempt.update({where:{id:p.id+':'+p.attempts},data:{status:state === 'PAID' ? 'PAID' : state === 'PENDING' ? 'PROCESSING' : state === 'UNVERIFIED' ? 'CHECKING' : state,providerId:p.bankOrderId}});
                    const status = current?.status === 'CANCELLED' ? 'REFUND_PENDING' : state === 'PAID' ? 'PAID' : state === 'PENDING' ? 'ACTION_REQUIRED' : state === 'REFUNDED' ? 'REFUNDED' : state === 'REVERSED' ? 'CANCELLED' : state === 'FAILED' ? 'FAILED' : 'CHECKING';
                    await tx.tripCardPayment.update({ where: { id }, data: { status, ...(state === 'PAID' ? { paidAt: latest.paidAt || new Date() } : {}), lastError: state === 'UNVERIFIED' ? 'Банк не подтвердил сумму или валюту платежа' : null } });
                });
                if (state === 'PAID') await this.syncCards(p.passengerId).catch(() => undefined);
            }
            this.realtime.publish({ type: 'order.payment.changed', entity: 'order', entityId: p.tripId, at: new Date().toISOString(), payload: { tripId: p.tripId, kind: p.kind, paymentMethod: 'CARD', paymentStatus: state } });
        } catch {
            await this.prisma.tripCardPayment.updateMany({ where: { id, earningsCredited: false, status: { in: ACTIVE } }, data: { lastError: 'Проверяем оплату ВТБ. Повторное списание не запускается.' } });
        } finally { await this.prisma.tripCardPayment.update({ where: { id }, data: { leaseUntil: null, nextCheckAt: new Date(Date.now() + retryDelay) } }); }
    }
}
