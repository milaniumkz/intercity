import { moneyField } from './currency';

export const dailyBonusSettingKey = (currency: string) => `driverDailyBonus${currency}`;
export function serviceDay(now = new Date()) {
    const day = new Date(now.getTime() + 5 * 3600000).toISOString().slice(0, 10);
    const start = new Date(Date.parse(`${day}T00:00:00Z`) - 5 * 3600000);
    return { day, start, end: new Date(start.getTime() + 86400000) };
}
export function parseDailyBonus(value: string) {
    const config = JSON.parse(value);
    if (typeof config.enabled !== 'boolean' || !Number.isInteger(config.targetOrders) || config.targetOrders < 1 || config.targetOrders > 1000 ||
        typeof config.rewardAmount !== 'number' || !Number.isFinite(config.rewardAmount) || config.rewardAmount <= 0 || config.rewardAmount > 1000000) {
        throw new Error('Укажите цель от 1 до 1000 заказов и положительную сумму бонуса до 1000000.');
    }
    return { enabled: config.enabled, targetOrders: config.targetOrders, rewardAmount: config.rewardAmount };
}
export async function driverDailyBonusProgress(db: any, driverId: string, userId: string, currency: string, now = new Date()) {
    const key = dailyBonusSettingKey(currency);
    const rows = await db.appSettings.findMany({ where: { key } });
    const row = rows.find((r: any) => r.key === key);
    if (!row) return null;
    let config;
    try { config = parseDailyBonus(row.value); } catch (_) { return null; }
    if (!config.enabled) return null;
    const {day, start, end} = serviceDay(now);
    const [city, intercity, credit] = await Promise.all([
        db.order.count({ where: { driverId, currency, status: 'COMPLETED', completedAt: { gte: start, lt: end } } }),
        db.intercityRequest.count({ where: { selectedDriverId: userId, currency, status: 'COMPLETED', completedAt: { gte: start, lt: end } } }),
        db.walletTransaction.findFirst({ where: { idempotencyKey: `daily-driver:${driverId}:${day}:${currency}` } }),
    ]);
    return { ...config, currency, day, completed: city + intercity, credited: !!credit, timeZone: 'UTC+5' };
}
export async function creditDriverDailyBonus(tx: any, driverId: string, userId: string, currency: string, now = new Date()) {
    await tx.$executeRaw`SELECT id FROM "DriverProfile" WHERE id = ${driverId} FOR UPDATE`;
    const progress = await driverDailyBonusProgress(tx, driverId, userId, currency, now);
    if (!progress || progress.credited || progress.completed < progress.targetOrders) return null;
    const wallet = await tx.wallet.upsert({ where: { userId }, create: { userId }, update: {} });
    const amount = progress.rewardAmount;
    await tx.wallet.update({ where: { id: wallet.id }, data: { [moneyField(currency)]: { increment: amount } } });
    await tx.walletTransaction.create({ data: { walletId: wallet.id, currency, type: 'DRIVER_DAILY_BONUS', direction: 'CREDIT', balanceSource: 'MONEY', amount,
        idempotencyKey: `daily-driver:${driverId}:${progress.day}:${currency}`, note: `Ежедневная акция: ${progress.targetOrders} заказов, ${progress.day}` } });
    return progress;
}
