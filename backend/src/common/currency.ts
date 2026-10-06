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
