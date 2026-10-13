import { Prisma } from '@prisma/client';

export const COMPONENTS = ['OPV', 'OPVR', 'SO', 'OSMS'] as const;
export type Component = typeof COMPONENTS[number];
export const POLICY_VERSION = 'KZ-2026-718-102.1-v1';
export function money(value: Prisma.Decimal.Value) {
    return new Prisma.Decimal(value).toDecimalPlaces(2, Prisma.Decimal.ROUND_HALF_UP);
}
export function kazakhstanPeriod(date: Date) {
    return new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Almaty', year: 'numeric', month: '2-digit' }).format(date);
}

// Difference of rounded cumulative liabilities avoids per-ride rounding drift.
// Exemptions and external income must be verified; a client checkbox never changes a rate.
export function socialIncrement(previous: Prisma.Decimal.Value, gross: Prisma.Decimal.Value,
    mzp: Prisma.Decimal.Value, exemptions: readonly string[] = []) {
    const before = money(previous), after = before.add(money(gross));
    if (before.isNegative() || money(gross).isNegative() || money(mzp).lte(0)) throw new Error('Invalid social payment base');
    const result = {} as Record<Component, Prisma.Decimal>;
    for (const component of COMPONENTS) {
        const cap = component === 'SO' ? money(mzp).mul(7) : null;
        const liability = (base: Prisma.Decimal) => exemptions.includes(component) ? money(0)
            : money((cap ? Prisma.Decimal.min(base, cap) : base).mul('0.01'));
        result[component] = liability(after).sub(liability(before));
    }
    return { ...result, total: COMPONENTS.reduce((sum, name) => sum.add(result[name]), money(0)) };
}
