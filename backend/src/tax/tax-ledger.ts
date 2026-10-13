import { Prisma } from '@prisma/client';
import { COMPONENTS, kazakhstanPeriod, money, POLICY_VERSION, socialIncrement } from './kz-social-calculator';

export const TAX_SETTINGS = ['kzTaxEnabled', 'kzTaxOperatorReference', 'kzTaxReferralContractReference',
    'referralMinPayoutKzt'];

// Same transaction lock as account erasure/dispatch. Acquire it before any user
// or wallet locks: completion, card settlement, debt collection and a referral
// payout must not take those rows in opposite orders.
export async function lockIncomeAccounting(tx: Prisma.TransactionClient) {
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(741302091)`;
}
export async function taxSettings(tx: Prisma.TransactionClient) {
    const rows = await tx.appSettings.findMany({ where: { key: { in: TAX_SETTINGS } } });
    const values = Object.fromEntries(rows.map(row => [row.key, row.value]));
    return { enabled: values.kzTaxEnabled === 'true' && !!values.kzTaxOperatorReference?.trim(),
        operatorReference: values.kzTaxOperatorReference ?? '',
        referralContractReference: values.kzTaxReferralContractReference ?? '',
        minPayout: money(values.referralMinPayoutKzt || 5000) };
}

export type IncomeEvent = { key: string; userId: string; sourceKind: 'CITY' | 'INTERCITY' | 'REFERRAL';
    sourceId: string; gross: number | Prisma.Decimal; currency: string; occurredAt: Date };

// Both tax and wallet mutations share the caller's transaction. A user row is the
// common lock for driver/referral income and profile verification, including months.
export async function recordTaxIncome(tx: Prisma.TransactionClient, input: IncomeEvent) {
    if ((await tx.appSettings.findUnique({ where: { key: 'kzTaxEnabled' } }))?.value !== 'true') return null;
    await lockIncomeAccounting(tx);
    await tx.$queryRaw`SELECT key FROM "AppSettings" WHERE key = 'kzTaxEnabled' FOR SHARE`;
    if ((await tx.appSettings.findUnique({ where: { key: 'kzTaxEnabled' } }))?.value !== 'true') return null;
    await tx.$executeRaw`SELECT id FROM "User" WHERE id = ${input.userId} FOR UPDATE`;
    const existing = await tx.taxIncomeEntry.findUnique({ where: { eventKey: input.key } });
    if (existing) return existing;
    const profile = await tx.taxProfile.findUnique({ where: { userId: input.userId } });
    // First stage is explicitly Kazakhstan. Russian or unclassified driver
    // profiles are never silently assigned a Kazakh tax rate.
    if (input.sourceKind !== 'REFERRAL' && profile?.countryCode !== 'KZ') return null;
    const period = kazakhstanPeriod(input.occurredAt);
    const gross = money(input.gross);
    if (gross.lte(0)) return null;
    return calculateEntry(tx, input, profile, period, gross);
}

export async function recordCashDriverIncome(tx: Prisma.TransactionClient, kind: 'CITY' | 'INTERCITY', ride: any,
    driverUserId: string, gross: number, occurredAt: Date) {
    if (ride.paymentMethod === 'CARD') return null;
    return recordTaxIncome(tx, { key: `driver-income:${kind}:${ride.id}`, userId: driverUserId,
        sourceKind: kind, sourceId: ride.id, gross, currency: ride.currency ?? 'KZT', occurredAt });
}

async function calculateEntry(tx: Prisma.TransactionClient, input: IncomeEvent, profile: any,
    period: string, gross: Prisma.Decimal, pendingId?: string) {
    if (profile?.iinHash) await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${`taxpayer:${profile.iinHash}:${period}`}))`;
    const config = await taxSettings(tx);
    const referral = input.sourceKind === 'REFERRAL';
    let reviewReason: string | null = !config.enabled ? 'OPERATOR_SETUP' : null;
    if (input.currency !== 'KZT') reviewReason = 'CURRENCY_REVIEW';
    if (!profile || profile.countryCode !== 'KZ' || profile.status !== 'VERIFIED') reviewReason = 'PROFILE_VERIFICATION';
    if (profile?.status === 'VERIFIED' && (!profile.effectiveFrom || profile.effectiveFrom > input.occurredAt)) reviewReason = 'STATUS_AT_INCOME_DATE';
    if (referral && !config.referralContractReference) reviewReason = 'REFERRAL_CONTRACT';
    if (profile?.kind === 'SELF_EMPLOYED' && !profile.activities.includes(referral ? '82990' : '49320')) reviewReason = 'ACTIVITY_VERIFICATION';
    // Annual parameters require an explicit, audited configuration. Do not apply
    // last year's MRP/MZP after January 1 or guess external monthly income.
    const year = period.slice(0, 4);
    const annual = await tx.appSettings.findUnique({ where: { key: `kzTaxPolicy${year}` } });
    let policy: any;
    try { policy = JSON.parse(annual?.value || '{}'); } catch { policy = {}; }
    const basis = await tx.taxPeriodBasis.findUnique({ where: { ownerKey_period: { ownerKey: input.userId, period } } });
    const identities = profile?.iinHash ? await tx.taxAccountingIdentity.findMany({ where: { iinHash: profile.iinHash }, select: { ownerKey: true } }) : [];
    const external = await tx.taxPeriodBasis.aggregate({ where: { period, ownerKey: { in: [input.userId, ...identities.map(i => i.ownerKey)] } }, _max: { externalGross: true } });
    const aggregate = await tx.taxIncomeEntry.aggregate({ where: { taxpayerKey: profile?.iinHash ?? 'NO_VERIFIED_IDENTITY', period, status: 'ACCOUNTED' }, _sum: { gross: true } });
    const previous = money(aggregate._sum.gross ?? 0).add(external._max.externalGross ?? 0);
    if (profile?.kind === 'SELF_EMPLOYED') {
        if (!(Number(policy.mrp) > 0 && Number(policy.mzp) > 0 && policy.reference)) reviewReason = 'ANNUAL_POLICY';
        else if (!basis) reviewReason = 'MONTHLY_BASIS';
        else if (previous.add(gross).gt(money(policy.mrp).mul(300))) reviewReason = 'REGIME_LIMIT';
    }
    const components = !reviewReason && profile?.kind === 'SELF_EMPLOYED'
        ? socialIncrement(previous, gross, policy.mzp, profile.exemptions) : socialIncrement(0, 0, 1);
    const wallet = await tx.wallet.upsert({ where: { userId: input.userId }, create: { userId: input.userId }, update: {} });
    await tx.$executeRaw`SELECT id FROM "Wallet" WHERE id = ${wallet.id} FOR UPDATE`;
    const currentWallet = await tx.wallet.findUniqueOrThrow({ where: { id: wallet.id } });
    // Cash in the driver's pocket isn't money held by the platform. Never use
    // promotional balances to pretend a social payment has been collected.
    const available = money(Math.max(0, currentWallet.money - currentWallet.lockedBonus));
    const collected = reviewReason ? money(0) : referral ? components.total : Prisma.Decimal.min(available, components.total);
    const data = { ownerKey: input.userId, taxpayerKey: profile?.iinHash ?? null, sourceKind: input.sourceKind, sourceId: input.sourceId,
        currency: input.currency, occurredAt: input.occurredAt, period,
        profileKind: profile?.kind ?? null, profileSnapshot: profile ? {
            profileId: profile.id, kind: profile.kind, activities: profile.activities,
            exemptions: profile.exemptions, verifiedAt: profile.verifiedAt?.toISOString(),
            policyVersion: POLICY_VERSION, annualPolicy: policy, operatorReference: config.operatorReference,
            externalGross: external._max.externalGross?.toString(),
        } : undefined,
        status: reviewReason ? 'REVIEW' : 'ACCOUNTED', reviewReason, gross,
        opv: components.OPV, opvr: components.OPVR, so: components.SO, osms: components.OSMS, withheld: collected };
    const entry = pendingId ? await tx.taxIncomeEntry.update({ where: { id: pendingId }, data })
        : await tx.taxIncomeEntry.create({ data: { ...data, eventKey: input.key } });
    // Actual driver income needs a protected accounting identity even while its
    // tax classification is reviewed. Unpaid referral entitlements do not.
    if (profile && (!reviewReason || !referral)) await tx.taxAccountingIdentity.upsert({ where: { ownerKey: input.userId }, update: {},
        create: { ownerKey: input.userId, iinEncrypted: profile.iinEncrypted, iinHash: profile.iinHash, iinLast4: profile.iinLast4, firstIncomeAt: input.occurredAt } });
    if (!reviewReason && referral) {
        const net = gross.sub(components.total);
        await tx.wallet.update({ where: { id: wallet.id }, data: { referralMoney: { increment: net } } });
        await tx.walletTransaction.create({ data: { walletId: wallet.id, type: 'REFERRAL_INCOME', balanceSource: 'REFERRAL',
            direction: 'CREDIT', currency: 'KZT', amount: net.toNumber(), actorUserId: input.userId,
            idempotencyKey: `tax-referral:${entry.id}`, note: `Реферальный доход: ${gross} ₸, социальные платежи: ${components.total} ₸` } });
    } else if (collected.gt(0)) {
        await tx.wallet.update({ where: { id: wallet.id }, data: { money: { decrement: collected.toNumber() } } });
        await tx.walletTransaction.create({ data: { walletId: wallet.id, type: 'SOCIAL_PAYMENT_WITHHELD', balanceSource: 'MONEY',
            direction: 'DEBIT', currency: 'KZT', amount: collected.toNumber(), actorUserId: input.userId,
            idempotencyKey: `tax-withheld:${entry.id}`, note: 'Удержание социальных платежей; перечисление учитывается отдельно' } });
    }
    return entry;
}

// Entitlements awaiting status/operator setup are released exactly once. Driver
// income keeps its original settlement month; referral income arises on release.
export async function releasePendingIncome(tx: Prisma.TransactionClient, userId: string, now = new Date()) {
    await lockIncomeAccounting(tx);
    await tx.$executeRaw`SELECT id FROM "User" WHERE id = ${userId} FOR UPDATE`;
    const profile = await tx.taxProfile.findUnique({ where: { userId } });
    const pending = await tx.taxIncomeEntry.findMany({ where: { ownerKey: userId, status: 'REVIEW', currency: 'KZT' }, orderBy: [{ occurredAt: 'asc' }, { id: 'asc' }], take: 100 });
    let released = 0;
    for (const entry of pending) {
        const date = entry.sourceKind === 'REFERRAL' ? now : entry.occurredAt;
        const result = await calculateEntry(tx, { key: entry.eventKey, userId, sourceKind: entry.sourceKind as IncomeEvent['sourceKind'],
            sourceId: entry.sourceId, gross: entry.gross, currency: entry.currency, occurredAt: date }, profile,
            kazakhstanPeriod(date), entry.gross, entry.id);
        if (result.status === 'ACCOUNTED') released++;
    }
    return { released, remaining: await tx.taxIncomeEntry.count({ where: { ownerKey: userId, status: 'REVIEW' } }) };
}

export function totalLiability(row: { opv: Prisma.Decimal; opvr: Prisma.Decimal; so: Prisma.Decimal; osms: Prisma.Decimal }) {
    return COMPONENTS.reduce((sum, key) => sum.add(row[key.toLowerCase()]), money(0));
}
