import { BadRequestException } from '@nestjs/common';
export type RideCurrency = 'KZT' | 'RUB';

export function currencyForCountry(countryCode?: string | null): RideCurrency {
    return countryCode?.toUpperCase() === 'RU' ? 'RUB' : 'KZT';
}

export function countryCodeFromRegion(region?: string | null): 'RU' | 'KZ' {
    return /росси|russia|\bRU\b/i.test(region || '') ? 'RU' : 'KZ';
}

export function walletCurrency(value?: string): RideCurrency {
    if (value == null) return 'KZT';
    if (value !== 'KZT' && value !== 'RUB') throw new BadRequestException('Unsupported wallet currency');
    return value;
}
export function moneyField(currency?: string): 'money' | 'moneyRub' { return currency === 'RUB' ? 'moneyRub' : 'money'; }
export function bonusField(currency?: string): 'bonus' | 'bonusRub' { return currency === 'RUB' ? 'bonusRub' : 'bonus'; }

export function lockedBonusField(currency?: string): 'lockedBonus' | 'lockedBonusRub' { return currency === 'RUB' ? 'lockedBonusRub' : 'lockedBonus'; }
export function withdrawableMoney(wallet: any, currency?: string) { return Math.max(0, wallet[moneyField(currency)] - wallet[lockedBonusField(currency)]); }
// Caller holds the wallet row lock: commissions consume promotional funds first.
export async function consumeLockedBonus(tx: any, walletId: string, currency: string, amount: number) {
    const wallet = await tx.wallet.findUnique({ where: { id: walletId } });
    const used = Math.min(Math.max(0, wallet?.[lockedBonusField(currency)] ?? 0), amount);
    if (used > 0) await tx.wallet.update({ where: { id: walletId }, data: { [lockedBonusField(currency)]: { decrement: used } } });
}
