import { DRIVER_ACTIVITY_RULES } from './driver-performance';

// Run inside the order transaction; serialize changes for a driver and deduplicate each offer/action.
export async function applyDriverActivity(tx: any, driverId: string, key: string, delta: number, now = new Date()) {
    await tx.$executeRaw`SELECT id FROM "DriverProfile" WHERE id = ${driverId} FOR UPDATE`;
    const previous = await tx.driverActivityEvent.findUnique({ where: { key } });
    let stats = await tx.driverServiceStats.upsert({ where: { driverId }, update: {}, create: { driverId, activityScore: DRIVER_ACTIVITY_RULES.initialScore } });
    if (previous) return stats;
    if (stats.activityBlockedUntil && stats.activityBlockedUntil <= now) {
        stats = { ...stats, activityScore: DRIVER_ACTIVITY_RULES.restoredScore, activityBlockedUntil: null };
    }
    const score = Math.max(0, Math.min(DRIVER_ACTIVITY_RULES.initialScore, stats.activityScore + delta));
    const blockedUntil = score === 0 ? new Date(now.getTime() + DRIVER_ACTIVITY_RULES.blockHours * 3600000) : stats.activityBlockedUntil;
    await tx.driverActivityEvent.create({ data: { key, driverId, delta: score - stats.activityScore, score } });
    return tx.driverServiceStats.update({ where: { driverId }, data: { activityScore: score, activityBlockedUntil: blockedUntil } });
}

export function driverOfferActivityKey(order: any, driverId: string) {
    return `offer:${order.id}:${driverId}:${order.dispatchExpiresAt?.toISOString() ?? 'auction'}`;
}
