import { moneyField } from '../common/currency';
import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { PushService } from '../notifications/push.service';

interface DriverScore {
    driverId: string;
    totalScore: number;
    distanceScore: number;
    ratingScore: number;
    activityScore: number;
    priorityScore: number;
    randomJitter: number;
}

@Injectable()
export class AutoDispatchService implements OnModuleInit, OnModuleDestroy {
    private timer?: ReturnType<typeof setInterval>;
    private processing = false;

    onModuleInit() {
        this.timer = setInterval(() => { void this.processQueue(); }, 3000);
        this.timer.unref();
        void this.processQueue();
    }

    onModuleDestroy() { if (this.timer) clearInterval(this.timer); }

    async processQueue() {
        if (this.processing) return;
        this.processing = true;
        try {
            const orders = await this.prisma.order.findMany({
                where: { status: { in: ['CREATED', 'SEARCHING_DRIVER'] }, driverId: null,
                    mode: { in: ['CITY', 'CARGO', 'DELIVERY'] },
                    AND: [
                        { OR: [{ requestType: null }, { requestType: { not: 'CITY_AUCTION' } }] },
                        { OR: [{ dispatchExpiresAt: null }, { dispatchExpiresAt: { lte: new Date() } }] },
                    ],
                    OR: [{ dispatchRetryAt: null }, { dispatchRetryAt: { lte: new Date() } }],
                },
                select: { id: true }, orderBy: { createdAt: 'asc' }, take: 200,
            });
            for (const order of orders) {
                try { await this.assignCityOrder(order.id); }
                catch (_) { this.logger.warn(`Dispatch retry deferred for order ${order.id}`); }
            }
        } catch (error) { this.logger.error('Dispatch queue processing failed'); }
        finally { this.processing = false; }
    }
    private readonly logger = new Logger(AutoDispatchService.name);

    constructor(
        private prisma: PrismaService,
        private realtimeService: RealtimeService,
        private pushService: PushService,
    ) { }

    async assignCityOrder(orderId: string) {
        const settings = await this.getSettings();
        const offer = await this.prisma.$transaction(async (tx) => {
            // One dispatcher across every API worker. Acceptance/rejection use conditional writes.
            await tx.$executeRaw`SELECT pg_advisory_xact_lock(741302091)`;
            const order = await tx.order.findUnique({ where: { id: orderId } });
            if (!order || !['CITY', 'CARGO', 'DELIVERY'].includes(order.mode) ||
                order.requestType === 'CITY_AUCTION' || !order.cityId || order.driverId ||
                !['CREATED', 'SEARCHING_DRIVER'].includes(order.status)) return null;
            const now = new Date();
            if (order.dispatchRetryAt && order.dispatchRetryAt > now) return null;
            if (order.dispatchDriverId && order.dispatchExpiresAt && order.dispatchExpiresAt > now) {
                const online = await tx.driverOnline.findUnique({ where: { driverId: order.dispatchDriverId } });
                if (online?.isOnline && online.cityId === order.cityId) return null;
            }
            const queued = await tx.order.updateMany({
                where: { id: orderId, status: { in: ['CREATED', 'SEARCHING_DRIVER'] }, driverId: null },
                data: { status: 'SEARCHING_DRIVER', dispatchDriverId: null, dispatchExpiresAt: null },
            });
            if (!queued.count) return null;
            // Expired reservations must not prevent another order using an available driver.
            await tx.order.updateMany({
                where: { status: 'SEARCHING_DRIVER', dispatchExpiresAt: { lte: now } },
                data: { dispatchDriverId: null, dispatchExpiresAt: null },
            });
            const drivers = await this.findEligibleDrivers(order.cityId, order.fromLat, order.fromLng,
                settings.searchRadiusKm, settings.minDriverLocationFreshSec,
                order.currency === 'RUB' ? settings.driverMinOnlineBalanceRub : settings.driverMinOnlineBalance,
                order.currency, tx);
            const compatible = drivers.filter((d) => order.mode === 'CARGO' ? d.driver.acceptCargo :
                order.mode === 'DELIVERY' ? d.driver.acceptDelivery : d.driver.acceptCityFixed);
            const tried = new Set(order.dispatchTriedDriverIds);
            const remaining = compatible.filter(d => !tried.has(d.driverId));
            if (!remaining.length) {
                await tx.order.updateMany({
                    where: { id: orderId, status: 'SEARCHING_DRIVER', driverId: null },
                    data: { dispatchRetryAt: new Date(now.getTime() + 30000),
                        ...(compatible.length ? { dispatchTriedDriverIds: [] } : {}) },
                });
                return null;
            }
            const scored = await Promise.all(remaining.map(async driver => ({driver,
                score: await this.computeScore(driver, order.fromLat, order.fromLng)})));
            scored.sort((a, b) => b.score.totalScore - a.score.totalScore);
            const best = scored[0];
            const expiresAt = new Date(now.getTime() + settings.dispatchTimeoutSec * 1000);
            const changed = await tx.order.updateMany({
                where: { id: orderId, status: 'SEARCHING_DRIVER', driverId: null, dispatchDriverId: null },
                data: { dispatchDriverId: best.driver.driverId, dispatchExpiresAt: expiresAt,
                    dispatchRetryAt: null, dispatchTriedDriverIds: { push: best.driver.driverId },
                    assignedScore: best.score.totalScore, assignedReasonJson: JSON.stringify(best.score) },
            });
            return changed.count ? {driverId: best.driver.driverId, userId: best.driver.driver.userId, expiresAt} : null;
        }, { maxWait: 10000, timeout: 15000 });
        if (!offer) return;
        await this.recordRideEventSafe({orderId, fromStatus: 'SEARCHING_DRIVER', toStatus: 'SEARCHING_DRIVER',
            source: 'AUTO_DISPATCH', reason: 'Driver offered order',
            payload: {driverId: offer.driverId, expiresAt: offer.expiresAt.toISOString()}});
        this.realtimeService.publish({type: 'order.dispatch.offered', entity: 'order', entityId: orderId,
            at: new Date().toISOString(), payload: { driverId: offer.driverId, expiresAt: offer.expiresAt }});
        await this.pushService.sendToUser(offer.userId, {title: 'Новый заказ', body: 'Примите заказ или откажитесь до окончания времени ответа.',
            data: {type: 'order_offer', orderId, expiresAt: offer.expiresAt.toISOString()}}).catch(() => false);
    }

    private async findEligibleDrivers(
        cityId: string,
        lat: number,
        lng: number,
        searchRadiusKm: number,
        minFreshSec: number,
        minDriverBalance: number,
        currency = 'KZT',
        db: any = this.prisma,
    ) {
        const minLocationTime = new Date(Date.now() - minFreshSec * 1000);

        const onlineDrivers = await db.driverOnline.findMany({
            where: {
                isOnline: true, cityId,
                driver: { status: { in: ['ACTIVE', 'APPROVED'] } },
            },
            include: {
                city: true,
                driver: {
                    include: {
                        rating: true,
                        priorityFlags: true,
                        serviceStats: true,
                        fuelBonus: true,
                        user: {
                            include: { wallet: true },
                        },
                    },
                },
            },
        });

        // Filter drivers without active orders
        const eligibleDrivers = [];

        for (const onlineDriver of onlineDrivers) {
            const reservation = await db.order.findFirst({ where: { dispatchDriverId: onlineDriver.driverId, status: 'SEARCHING_DRIVER', dispatchExpiresAt: { gt: new Date() } } });
            if (reservation) continue;
            const activeIntercity = await db.intercityRequest.findFirst({ where: { selectedDriverId: onlineDriver.driver.userId, status: { in: ['ACCEPTED', 'DRIVER_ASSIGNED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'IN_PROGRESS'] } } });
            if (activeIntercity) continue;
            const hasActiveOrder = await db.order.findFirst({
                where: {
                    driverId: onlineDriver.driverId,
                    status: {
                        in: ['SEARCHING_DRIVER', 'DRIVER_ASSIGNED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'IN_PROGRESS'],
                    },
                },
            });

            if (!hasActiveOrder) {
                // Check if driver has approved profile
                if (onlineDriver.driver.status === 'ACTIVE' || onlineDriver.driver.status === 'APPROVED') {
                    if (onlineDriver.cityId !== cityId) continue;
                    const balance = onlineDriver.driver.user?.wallet?.[moneyField(currency)] ?? 0;
                    if (minDriverBalance > 0 && balance < minDriverBalance) {
                        await db.driverOnline.update({
                            where: { driverId: onlineDriver.driverId },
                            data: { isOnline: false },
                        }).catch(() => null);
                        this.realtimeService.publish({
                            type: 'driver.online.changed',
                            entity: 'driver',
                            entityId: onlineDriver.driverId,
                            at: new Date().toISOString(),
                            payload: {
                                isOnline: false,
                                reason: 'LOW_BALANCE',
                                balance,
                                minBalance: minDriverBalance,
                            },
                        });
                        continue;
                    }
                    const serviceStats = onlineDriver.driver.serviceStats;
                    if (serviceStats?.activityBlockedUntil && new Date(serviceStats.activityBlockedUntil) > new Date()) {
                        continue;
                    }
                    let activityScore = serviceStats?.activityScore ?? 100;
                    if (
                        activityScore <= 0 &&
                        serviceStats?.activityBlockedUntil &&
                        new Date(serviceStats.activityBlockedUntil) <= new Date()
                    ) {
                        const restored = await db.driverServiceStats.update({
                            where: { driverId: onlineDriver.driverId },
                            data: { activityScore: 30, activityBlockedUntil: null },
                        });
                        activityScore = restored.activityScore;
                        (onlineDriver.driver as any).serviceStats = restored;
                    }
                    if (activityScore <= 0) {
                        continue;
                    }
                    // Calculate distance
                    const hasFreshLocation =
                        onlineDriver.lastLat != null &&
                        onlineDriver.lastLng != null &&
                        onlineDriver.lastLocationAt != null &&
                        onlineDriver.lastLocationAt >= minLocationTime;
                    const effectiveLat = hasFreshLocation
                        ? onlineDriver.lastLat!
                        : onlineDriver.city?.lat;
                    const effectiveLng = hasFreshLocation
                        ? onlineDriver.lastLng!
                        : onlineDriver.city?.lng;
                    if (effectiveLat == null || effectiveLng == null) {
                        continue;
                    }
                    const distance = this.haversine(lat, lng, effectiveLat, effectiveLng);

                    if (!hasFreshLocation || distance <= searchRadiusKm) {
                        eligibleDrivers.push({
                            ...onlineDriver,
                            distanceFromPassenger: distance,
                            locationFallback: !hasFreshLocation,
                        });
                    }
                }
            }
        }

        return eligibleDrivers;
    }

    async computeScore(driver: any, passengerLat: number, passengerLng: number): Promise<DriverScore> {
        const distanceKm =
            typeof driver.distanceFromPassenger === 'number'
                ? driver.distanceFromPassenger
                : this.haversine(passengerLat, passengerLng, driver.lastLat!, driver.lastLng!);

        // Distance score: max(0, 50 - distanceKm*10)
        const distanceScore = Math.max(0, 50 - distanceKm * 10);

        // Rating score: ratingAvg * 5
        const ratingAvg = driver.driver.rating?.ratingAvg || 5.0;
        const ratingScore = ratingAvg * 5;

        // Activity score: direct weight (0..100+)
        const activity = Math.max(0, driver.driver.serviceStats?.activityScore ?? 100);
        const activityScore = activity * 0.5;

        // Priority score calculation
        const priorityPoints = this.calculatePriorityPoints(driver.driver);
        const priorityScore = priorityPoints;

        // Random jitter: 0-1
        const randomJitter = Math.random();

        const totalScore = distanceScore + ratingScore + activityScore + priorityScore + randomJitter;

        return {
            driverId: driver.driverId,
            totalScore,
            distanceScore,
            ratingScore,
            activityScore,
            priorityScore,
            randomJitter,
        };
    }

    private calculatePriorityPoints(driver: any): number {
        let points = 0;

        // шашка = +5
        if (driver.priorityFlags?.hasCheckers) {
            points += 5;
        }

        // обклейка = +10
        if (driver.priorityFlags?.hasBranding) {
            points += 10;
        }

        // рейтинг >4.9 = +10
        if (driver.rating?.ratingAvg && driver.rating.ratingAvg > 4.9) {
            points += 10;
        }

        // каждый день в сервисе = +2
        if (driver.serviceStats?.serviceStartAt) {
            const daysInService = Math.floor(
                (Date.now() - new Date(driver.serviceStats.serviceStartAt).getTime()) / (1000 * 60 * 60 * 24)
            );
            points += daysInService * 2;
        }

        // партнерская заправка = +2 (если bonusActiveUntil > now)
        if (driver.fuelBonus?.bonusActiveUntil) {
            if (new Date(driver.fuelBonus.bonusActiveUntil) > new Date()) {
                points += 2;
            }
        }

        return points;
    }

    haversine(lat1: number, lng1: number, lat2: number, lng2: number): number {
        const R = 6371;
        const dLat = this.toRad(lat2 - lat1);
        const dLng = this.toRad(lng2 - lng1);
        const a =
            Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(this.toRad(lat1)) * Math.cos(this.toRad(lat2)) *
            Math.sin(dLng / 2) * Math.sin(dLng / 2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    }

    private toRad(deg: number): number {
        return deg * (Math.PI / 180);
    }

    private async getSettings() {
        const settings = await this.prisma.appSettings.findMany();
        const settingsMap: any = {};
        for (const s of settings) {
            settingsMap[s.key] = s.value;
        }
        return {
            searchRadiusKm: parseFloat(settingsMap['searchRadiusKm'] || '5'),
            dispatchTimeoutSec: Math.min(120, Math.max(10, parseInt(settingsMap['driverOfferAcceptSec'] || settingsMap['dispatchTimeoutSec'] || '20') || 20)),
            minDriverLocationFreshSec: parseInt(settingsMap['minDriverLocationFreshSec'] || '60'),
            referralPercent: parseFloat(settingsMap['referralPercent'] || '10'),
            cityAutoAssignEnabled: (settingsMap['cityAutoAssignEnabled'] || 'false').toLowerCase() === 'true',
            driverMinOnlineBalance: this.parsePositiveNumber(settingsMap['driverMinOnlineBalance'], 100),
            driverMinOnlineBalanceRub: this.parsePositiveNumber(settingsMap['driverMinOnlineBalanceRub'], 100),
        };
    }

    private parsePositiveNumber(value: string | undefined | null, fallback: number): number {
        const parsed = parseFloat(value || '');
        return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
    }

    private async recordRideEventSafe(input: {
        orderId: string;
        fromStatus?: string | null;
        toStatus: string;
        actorUserId?: string | null;
        actorRole?: string | null;
        source?: string | null;
        reason?: string | null;
        payload?: Record<string, unknown>;
    }) {
        try {
            await (this.prisma as any).rideEvent.create({
                data: {
                    orderId: input.orderId,
                    fromStatus: input.fromStatus ?? null,
                    toStatus: input.toStatus,
                    actorUserId: input.actorUserId ?? null,
                    actorRole: input.actorRole ?? null,
                    source: input.source ?? null,
                    reason: input.reason ?? null,
                    payload: input.payload ?? undefined,
                },
            });
        } catch (_) {
            // Ignore until ride_events migration is applied.
        }
    }
}
