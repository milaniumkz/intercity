/** Baseline country rates used for a newly discovered city with no tariffs. */
export const CITY_TARIFF_DEFAULTS: Record<string, {basePrice:number; pricePerKm:number; pricePerMin:number; minPrice:number}> = {
    KZ: {basePrice:400,pricePerKm:90,pricePerMin:15,minPrice:700},
    RU: {basePrice:90,pricePerKm:18,pricePerMin:4,minPrice:150},
};
