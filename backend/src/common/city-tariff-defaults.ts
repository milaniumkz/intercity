import { parseRouteTopPolicy, ROUTE_TOP_POLICY_KEY, routeTopPrice } from './driver-route-top';
/** Baseline country rates used for a newly discovered city with no tariffs. */
export const CITY_TARIFF_DEFAULTS: Record<string, {basePrice:number; pricePerKm:number; pricePerMin:number; minPrice:number}> = {
    KZ: {basePrice:400,pricePerKm:90,pricePerMin:15,minPrice:500},
    RU: {basePrice:90,pricePerKm:18,pricePerMin:4,minPrice:71.43},
};

export async function cityTariffDefaults(db: any, country: string) {
    const defaults = { ...CITY_TARIFF_DEFAULTS[country] };
    if (country === 'RU') {
        const policy = parseRouteTopPolicy((await db.appSettings.findUnique({where:{key:ROUTE_TOP_POLICY_KEY}}))?.value);
        defaults.minPrice = routeTopPrice({...policy,priceKzt:500}, 'RUB');
    }
    return defaults;
}
