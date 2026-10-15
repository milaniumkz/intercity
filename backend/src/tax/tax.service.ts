import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes } from 'crypto';
import { PrismaService } from '../prisma.service';
import { DeclareTaxProfileDto, MonthlyBasisDto, RemittanceDto, TaxSettingsDto, VerifyTaxProfileDto } from './tax.dto';
import { kazakhstanPeriod, money } from './kz-social-calculator';
import { lockIncomeAccounting, releasePendingIncome, taxSettings, totalLiability } from './tax-ledger';

export const TAX_CONSENT_VERSION = 'KZ-platform-income-2026-v1';
export function validIin(iin: string) {
    if (!/^\d{12}$/.test(iin) || /^0{12}$/.test(iin)) return false;
    const digits = [...iin].map(Number);
    const sum = (weights: number[]) => weights.reduce((n, w, i) => n + w * digits[i], 0) % 11;
    const first = sum([1,2,3,4,5,6,7,8,9,10,11]);
    return (first === 10 ? sum([3,4,5,6,7,8,9,10,11,1,2]) : first) === digits[11];
}
@Injectable()
export class TaxService {
    constructor(private readonly prisma: PrismaService) {}
    private publicProfile(profile: any) {
        if (!profile) return null;
        const { iinEncrypted, iinHash, ...safe } = profile;
        return { ...safe, effectiveFromDate: profile.effectiveFrom ? new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Almaty' }).format(profile.effectiveFrom) : null };
    }
    private encryptIin(iin: string) {
        const secret = process.env.TAX_ID_ENCRYPTION_KEY || process.env.JWT_SECRET || '';
        if (secret.length < 32) throw new BadRequestException('Защищённая регистрация налогового профиля пока недоступна');
        const key = createHash('sha256').update(`intercity:tax-identity:v1:${secret}`).digest();
        const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', key, iv);
        return Buffer.concat([iv, cipher.update(iin, 'utf8'), cipher.final(), cipher.getAuthTag()]).toString('base64');
    }
    private decryptIin(encrypted: string) {
        const secret = process.env.TAX_ID_ENCRYPTION_KEY || process.env.JWT_SECRET || '';
        if (secret.length < 32) throw new BadRequestException('Ключ защищённого учёта недоступен');
        const key = createHash('sha256').update(`intercity:tax-identity:v1:${secret}`).digest();
        const data = Buffer.from(encrypted, 'base64');
        const cipher = createDecipheriv('aes-256-gcm', key, data.subarray(0,12));
        cipher.setAuthTag(data.subarray(-16));
        return Buffer.concat([cipher.update(data.subarray(12,-16)), cipher.final()]).toString('utf8');
    }
    async summary(userId: string) {
        return this.prisma.$transaction(async tx => {
            const profile = await tx.taxProfile.findUnique({ where: { userId } });
            const driver = await tx.driverProfile.findUnique({ where: { userId }, select: { id: true } });
            const wallet = await tx.wallet.findUnique({ where: { userId } });
            const config = await taxSettings(tx);
            const income = await tx.taxIncomeEntry.findMany({ where: { ownerKey: userId }, orderBy: { occurredAt: 'desc' }, take: 100 });
            const pending = await tx.taxIncomeEntry.aggregate({ where: { ownerKey: userId, sourceKind: 'REFERRAL', status: 'REVIEW', currency: 'KZT' }, _sum: { gross: true } });
            return { profile: this.publicProfile(profile), isDriver: !!driver, enabled: config.enabled, consentVersion: TAX_CONSENT_VERSION,
                referralBalance: wallet?.referralMoney ?? money(0), minPayout: config.minPayout,
                pendingReferral: pending._sum.gross ?? money(0), income,
                period: kazakhstanPeriod(new Date()) };
        });
    }
    async declare(userId: string, dto: DeclareTaxProfileDto) {
        if (!dto.consent || !validIin(dto.iin) || !dto.activities.length) throw new BadRequestException('Проверьте ИИН, вид деятельности и согласие');
        const encrypted = this.encryptIin(dto.iin);
        const secret = process.env.TAX_ID_ENCRYPTION_KEY || process.env.JWT_SECRET || '';
        const iinHash = createHmac('sha256', secret).update(`intercity:taxpayer:v1:${dto.iin}`).digest('hex');
        return this.prisma.$transaction(async tx => {
            await lockIncomeAccounting(tx);
            await tx.$executeRaw`SELECT id FROM "User" WHERE id=${userId} FOR UPDATE`;
            const driver = await tx.driverProfile.findUnique({ where: { userId }, select: { id: true } });
            if (driver && (await tx.order.findFirst({ where: { driverId: driver.id, status: { in: ['DRIVER_ASSIGNED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS'] } } }) ||
                await tx.intercityRequest.findFirst({ where: { selectedDriverId: userId, status: { in: ['ACCEPTED','DRIVER_ASSIGNED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS'] } } }))) throw new BadRequestException('Измените налоговый статус после завершения текущей поездки');
            const current = await tx.taxProfile.findUnique({ where: { userId } });
            const accountingIdentity = await tx.taxAccountingIdentity.findUnique({ where: { ownerKey: userId } });
            if (accountingIdentity && this.decryptIin(accountingIdentity.iinEncrypted) !== dto.iin) throw new BadRequestException('Смена ИИН после учёта дохода требует проверки администратора');
            if (current && current.kind !== dto.kind && await tx.taxIncomeEntry.count({ where: { ownerKey: userId, period: kazakhstanPeriod(new Date()), status: 'ACCOUNTED' } })) throw new BadRequestException('Смена режима в учтённом месяце требует бухгалтерской сверки');
            // Historical entries retain verified snapshots. A changed declaration
            // requires verification again and cannot rewrite past liabilities.
            const duplicate = await tx.taxProfile.findUnique({ where: { iinHash } });
            if (duplicate && duplicate.userId !== userId) throw new BadRequestException('ИИН уже связан с налоговым профилем');
            const data = { kind: dto.kind, countryCode: dto.countryCode, status: 'PENDING', iinEncrypted: encrypted, iinHash,
                iinLast4: dto.iin.slice(-4), activities: [...new Set(dto.activities)], exemptions: current?.iinHash === iinHash ? current.exemptions : [], birthDate: current?.iinHash === iinHash ? current.birthDate : null, consentVersion: TAX_CONSENT_VERSION,
                consentAt: new Date(), verifiedAt: null, verifiedBy: null, verificationReference: null };
            const profile = await tx.taxProfile.upsert({ where: { userId }, create: { userId, ...data }, update: data });
            if ((await taxSettings(tx)).enabled) await this.offlineUnverifiedKazakhstanDrivers(tx);
            return this.publicProfile(profile);
        });
    }
    async verify(userId: string, dto: VerifyTaxProfileDto, adminId: string) {
        if (!dto.quickApproval && (!dto.reference || dto.reference.trim().length < 5)) throw new BadRequestException('Укажите документ проверки статуса и льгот');
        return this.prisma.$transaction(async tx => {
            await lockIncomeAccounting(tx);
            await tx.$executeRaw`SELECT id FROM "User" WHERE id=${userId} FOR UPDATE`;
            const profile = await tx.taxProfile.findUnique({ where: { userId } });
            if (!profile) throw new NotFoundException('Налоговый профиль не найден');
            // Manual administrator approval, not a government verification. No
            // backdating or invented external-income declarations are performed.
            if (dto.quickApproval) {
                dto = { ...dto, reference: 'Ручное решение администратора по заявленному профилю',
                    exemptions: profile.exemptions,
                    effectiveFrom: profile.effectiveFrom?.toISOString() || new Date().toISOString() };
                if (!profile.birthDate && profile.kind === 'SELF_EMPLOYED' && dto.status === 'VERIFIED') {
                    const iin = this.decryptIin(profile.iinEncrypted);
                    const century = { '1': 1800, '2': 1800, '3': 1900, '4': 1900, '5': 2000, '6': 2000 }[iin[6]];
                    const year = century + Number(iin.slice(0,2));
                    const date = `${year}-${iin.slice(2,4)}-${iin.slice(4,6)}`;
                    const parsed = new Date(date);
                    if (!century || !Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0,10) !== date || parsed > new Date()) {
                        throw new BadRequestException('Не удалось определить дату рождения по ИИН. Проверьте данные налогового профиля');
                    }
                    dto.birthDate = date;
                }
            }
            const birthDate = dto.birthDate ? new Date(dto.birthDate) : profile.birthDate;
            const effectiveFrom = dto.effectiveFrom ? this.kazakhstanDate(dto.effectiveFrom) : profile.effectiveFrom;
            if (dto.status === 'VERIFIED' && (!effectiveFrom || !Number.isFinite(effectiveFrom.getTime()) || effectiveFrom > new Date())) throw new BadRequestException('Укажите подтверждённую дату начала налогового режима');
            if (dto.status === 'VERIFIED' && profile.kind === 'SELF_EMPLOYED' && (!birthDate || !Number.isFinite(birthDate.getTime()) || birthDate > new Date())) throw new BadRequestException('Подтвердите дату рождения для расчёта ОПВР');
            const exemptions = [...new Set([...(dto.exemptions || profile.exemptions), ...(birthDate && birthDate < new Date('1975-01-01T00:00:00Z') ? ['OPVR'] : [])])];
            if (dto.status === 'VERIFIED' && JSON.stringify([...exemptions].sort()) !== JSON.stringify([...profile.exemptions].sort()) &&
                await tx.taxIncomeEntry.count({ where: { ownerKey: userId, period: kazakhstanPeriod(new Date()), status: 'ACCOUNTED' } })) throw new BadRequestException('Льготы месяца уже использованы. Изменение требует бухгалтерской сверки');
            const updated = await tx.taxProfile.update({ where: { userId }, data: { status: dto.status,
                exemptions, birthDate, effectiveFrom, verifiedBy: adminId, verifiedAt: new Date(), verificationReference: dto.reference.trim() } });
            if ((await taxSettings(tx)).enabled) await this.offlineUnverifiedKazakhstanDrivers(tx);
            return this.publicProfile(updated);
        });
    }
    async monthlyBasis(userId: string, dto: MonthlyBasisDto, adminId: string) {
        if (dto.reference.trim().length < 5) throw new BadRequestException('Укажите подтверждение внешнего дохода, включая нулевой');
        return this.prisma.$transaction(async tx => {
            await tx.$executeRaw`SELECT id FROM "User" WHERE id=${userId} FOR UPDATE`;
            if (await tx.taxIncomeEntry.count({ where: { ownerKey: userId, period: dto.period, status: 'ACCOUNTED' } })) {
                throw new BadRequestException('База месяца уже использована. Исправление требует отдельной сверки, а не пересчёта прошлых удержаний');
            }
            return tx.taxPeriodBasis.upsert({ where: { ownerKey_period: { ownerKey: userId, period: dto.period } },
                create: { ownerKey: userId, ...dto, externalGross: money(dto.externalGross), recordedBy: adminId },
                update: { externalGross: money(dto.externalGross), reference: dto.reference, recordedBy: adminId } });
        });
    }
    release(userId: string) { return this.prisma.$transaction(tx => releasePendingIncome(tx, userId), { timeout: 30000 }); }
    async collectDebt(userId: string) {
        return this.prisma.$transaction(async tx => {
            await lockIncomeAccounting(tx);
            await tx.$executeRaw`SELECT id FROM "User" WHERE id=${userId} FOR UPDATE`;
            const wallet = await tx.wallet.findUnique({ where: { userId } });
            if (!wallet) throw new NotFoundException('Кошелёк не найден');
            await tx.$executeRaw`SELECT id FROM "Wallet" WHERE id=${wallet.id} FOR UPDATE`;
            const current = await tx.wallet.findUniqueOrThrow({ where: { id: wallet.id } });
            let available = money(Math.max(0, current.money - current.lockedBonus)), collected = money(0);
            for (const entry of await tx.taxIncomeEntry.findMany({ where: { ownerKey: userId, currency: 'KZT', status: 'ACCOUNTED' }, orderBy: { occurredAt: 'asc' } })) {
                const debt = totalLiability(entry).sub(entry.withheld);
                const debit = money(Math.max(0, Math.min(debt.toNumber(), available.toNumber())));
                if (debit.lte(0)) continue;
                const next = entry.withheld.add(debit);
                await tx.taxIncomeEntry.update({ where: { id: entry.id }, data: { withheld: next } });
                await tx.walletTransaction.create({ data: { walletId: wallet.id, type: 'SOCIAL_PAYMENT_DEBT_COLLECTED',
                    direction: 'DEBIT', balanceSource: 'MONEY', currency: 'KZT', amount: debit.toNumber(), actorUserId: userId,
                    idempotencyKey: `tax-debt:${entry.id}:${next}`, note: `Социальные платежи за ${entry.period}, учёт ${entry.id}` } });
                available = available.sub(debit); collected = collected.add(debit);
            }
            if (collected.gt(0)) await tx.wallet.update({ where: { id: wallet.id }, data: { money: { decrement: collected.toNumber() } } });
            return { collected };
        });
    }
    async protectedIdentity(userId: string) {
        const identity = await this.prisma.taxProfile.findUnique({ where: { userId } }) ?? await this.prisma.taxAccountingIdentity.findUnique({ where: { ownerKey: userId } });
        if (!identity) throw new NotFoundException('ИИН не найден');
        return { iin: this.decryptIin(identity.iinEncrypted) };
    }
    async registry(period: string, kind?: string) {
        if (!/^20\d{2}-(0[1-9]|1[0-2])$/.test(period)) throw new BadRequestException('Укажите месяц YYYY-MM');
        if (kind && !['SELF_EMPLOYED', 'IE'].includes(kind)) throw new BadRequestException('Некорректный статус');
        const [profiles, entries, payments] = await Promise.all([
            this.prisma.taxProfile.findMany({ where: { countryCode: 'KZ', ...(kind ? { kind } : {}) }, include: { user: { select: { name: true, phone: true } } } }),
            this.prisma.taxIncomeEntry.findMany({ where: { period, ...(kind ? { profileKind: kind } : {}) }, orderBy: { occurredAt: 'desc' } }),
            this.prisma.taxRemittance.findMany({ where: { period } }),
        ]);
        const owners = new Set([...profiles.map(p => p.userId), ...entries.map(e => e.ownerKey)]);
        const rows = [...owners].map(ownerKey => {
            const profile = profiles.find(p => p.userId === ownerKey);
            const income = entries.filter(e => e.ownerKey === ownerKey), accounted = income.filter(e => e.status === 'ACCOUNTED');
            const sum = (field: string) => accounted.reduce((n, e) => n.add(e[field]), money(0));
            const liability = accounted.reduce((n, e) => n.add(totalLiability(e)), money(0));
            const paid = payments.filter(p => p.ownerKey === ownerKey).reduce((n, p) => n.add(p.amount), money(0));
            return { ownerKey, profile: this.publicProfile(profile), trips: accounted.filter(e => e.sourceKind !== 'REFERRAL').length,
                gross: sum('gross'), referralGross: accounted.filter(e => e.sourceKind === 'REFERRAL').reduce((n,e) => n.add(e.gross), money(0)),
                opv: sum('opv'), opvr: sum('opvr'), so: sum('so'), osms: sum('osms'), liability, withheld: sum('withheld'),
                debt: liability.sub(sum('withheld')), paid, payable: liability.sub(paid), reviewCount: income.filter(e => e.status === 'REVIEW').length };
        });
        return { period, rows, entries, payments };
    }
    async exportRegistry(period: string, kind?: string) {
        const registry = await this.registry(period, kind);
        const cells = (values: unknown[]) => values.map(value => {
            let text = String(value ?? '');
            if (/^[=+\-@]/.test(text)) text = `'${text}`;
            return `"${text.replace(/"/g, '""')}"`;
        }).join(';');
        const lines = [cells(['Месяц', 'Владелец учётной записи', 'ИИН', 'Статус', 'Поездки', 'Доход', 'Реферальный доход', 'ОПВ', 'ОПВР', 'СО', 'ОСМС', 'Удержано', 'Долг', 'Перечислено', 'К перечислению'])];
        for (const row of registry.rows) {
            let iin = '';
            if (row.gross.gt(0)) iin = (await this.protectedIdentity(row.ownerKey)).iin;
            lines.push(cells([period, row.ownerKey, iin, row.profile?.kind, row.trips, row.gross, row.referralGross,
                row.opv, row.opvr, row.so, row.osms, row.withheld, row.debt, row.paid, row.payable]));
        }
        return { csv: lines.join('\n'), period, notice: 'Учётный реестр, не подтверждение сдачи отчёта в КГД' };
    }
    async remittance(dto: RemittanceDto, adminId: string) {
        const paidAt = this.kazakhstanDate(dto.paidAt);
        if (!Number.isFinite(paidAt.getTime()) || paidAt > new Date() || dto.reference.trim().length < 5 || dto.note.trim().length < 5) throw new BadRequestException('Укажите дату, банковский документ и пояснение фактического платежа');
        return this.prisma.$transaction(async tx => {
            // Serializes payment confirmations, also for erased financial owners.
            await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${`tax-remittance:${dto.ownerKey}:${dto.period}`}))`;
            if (await tx.taxRemittance.findUnique({ where: { reference: dto.reference.trim() } })) throw new BadRequestException('Платёжный документ уже учтён');
            const field = dto.component.toLowerCase();
            const income = await tx.taxIncomeEntry.findMany({ where: { ownerKey: dto.ownerKey, period: dto.period, status: 'ACCOUNTED' } });
            const liability = income.reduce((n,e) => n.add(e[field]), money(0));
            const payments = await tx.taxRemittance.aggregate({ where: { ownerKey: dto.ownerKey, period: dto.period, component: dto.component }, _sum: { amount: true } });
            if (money(dto.amount).gt(liability.sub(payments._sum.amount ?? 0))) throw new BadRequestException('Сумма превышает непогашенное обязательство');
            return tx.taxRemittance.create({ data: { ...dto, reference: dto.reference.trim(), paidAt, amount: money(dto.amount), recordedBy: adminId } });
        });
    }
    private kazakhstanDate(value: string) {
        return new Date(/^\d{4}-\d{2}-\d{2}$/.test(value) ? `${value}T00:00:00+05:00` : value);
    }
    async configure(dto: TaxSettingsDto) {
        // Internal accounting is independent of government connectivity. References
        // describe documents only; enabling never records a government payment.
        if (dto.enabled && dto.policyReference.trim().length < 5) throw new BadRequestException('Укажите источник годовых параметров расчёта');
        const settings = { kzTaxEnabled: String(dto.enabled), kzTaxOperatorReference: dto.operatorReference.trim(),
            kzTaxReferralContractReference: dto.referralContractReference.trim(), referralMinPayoutKzt: money(dto.minPayout).toString(),
            [`kzTaxPolicy${dto.year}`]: JSON.stringify({ mrp: dto.mrp, mzp: dto.mzp, reference: dto.policyReference.trim() }) };
        await this.prisma.$transaction(async tx => {
            await lockIncomeAccounting(tx);
            await tx.$queryRaw`SELECT key FROM "AppSettings" WHERE key = 'kzTaxEnabled' FOR UPDATE`;
            const enabled = await tx.appSettings.findUnique({ where: { key: 'kzTaxEnabled' } });
            if (enabled?.value === 'true' && !dto.enabled && await tx.taxIncomeEntry.count()) throw new BadRequestException('Есть налоговые и денежные события. Отключение требует сверки обязательств и остановки приёма новых доходов; возврат к старым бонусам не допускается');
            // Changing parameters after postings would change cumulative deltas.
            const previous = await tx.appSettings.findUnique({ where: { key: `kzTaxPolicy${dto.year}` } });
            if (previous && previous.value !== settings[`kzTaxPolicy${dto.year}`] && await tx.taxIncomeEntry.count({ where: { period: { startsWith: `${dto.year}-` }, status: 'ACCOUNTED' } })) throw new BadRequestException('Годовая политика уже использована. Нужна бухгалтерская корректировка');
            for (const [key,value] of Object.entries(settings)) await tx.appSettings.upsert({ where: { key }, create: { key,value }, update: { value } });
            if (dto.enabled) await this.offlineUnverifiedKazakhstanDrivers(tx);
        });
        return { ...dto, enabled: dto.enabled };
    }
    private offlineUnverifiedKazakhstanDrivers(tx: any) {
        return tx.driverOnline.updateMany({ where: { isOnline: true, AND: [
            { OR: [{ city: { countryCode: 'KZ' } }, { cityId: null, driver: { user: { city: { countryCode: 'KZ' } } } }] },
            { driver: { user: { OR: [ { taxProfile: null }, { taxProfile: { is: { OR: [
                { status: { not: 'VERIFIED' } }, { countryCode: { not: 'KZ' } }, { NOT: { activities: { has: '49320' } } },
            ] } } } ] } } },
        ] }, data: { isOnline: false } });
    }
    async configuration() {
        const year = new Date().getUTCFullYear().toString();
        const rows = await this.prisma.appSettings.findMany({ where: { key: { in: ['kzTaxEnabled', 'kzTaxOperatorReference', 'kzTaxReferralContractReference', 'referralMinPayoutKzt', `kzTaxPolicy${year}`] } } });
        const values = Object.fromEntries(rows.map(r => [r.key,r.value]));
        let annual = {};
        try { annual = JSON.parse(values[`kzTaxPolicy${year}`] || '{}'); } catch {}
        return { enabled: values.kzTaxEnabled === 'true', operatorReference: values.kzTaxOperatorReference || '',
            referralContractReference: values.kzTaxReferralContractReference || '', minPayout: values.referralMinPayoutKzt || '5000', year, ...annual };
    }
}
