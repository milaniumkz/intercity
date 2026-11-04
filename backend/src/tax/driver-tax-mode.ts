export const DRIVER_TAX_PAUSED_KEY = 'driverTaxIntegrationPaused';
export async function driverTaxIntegrationPaused(db: any): Promise<boolean> {
    return (await db.appSettings.findUnique({ where: { key: DRIVER_TAX_PAUSED_KEY } }))?.value === 'true';
}
export async function driverTaxChecksEnabled(db: any): Promise<boolean> {
    return (await db.appSettings.findUnique({ where: { key: 'kzTaxEnabled' } }))?.value === 'true' && !await driverTaxIntegrationPaused(db);
}

export async function offlineUnverifiedTaxDrivers(tx: any) {
        return tx.driverOnline.updateMany({ where: { isOnline: true, AND: [
            { OR: [{ city: { countryCode: 'KZ' } }, { cityId: null, driver: { user: { city: { countryCode: 'KZ' } } } }] },
            { driver: { user: { OR: [ { taxProfile: null }, { taxProfile: { is: { AND: [{ kind: { not: 'INDIVIDUAL' } }, { OR: [
                { status: { not: 'VERIFIED' } }, { countryCode: { not: 'KZ' } }, { NOT: { activities: { has: '49320' } } },
            ] }] } } } ] } } },
        ] }, data: { isOnline: false } });
}
