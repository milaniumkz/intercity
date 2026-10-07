import { moneyField } from '../common/currency';
import { Injectable, Logger } from '@nestjs/common';
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
export class AutoDispatchService {
    private readonly logger = new Logger(AutoDispatchService.name);

    constructor(
        private prisma: PrismaService,
        private realtimeService: RealtimeService,
        private pushService: PushService,
    ) { }

    async assignCityOrder(orderId: string) {
        const order = await this.prisma.order.findUnique({
            where: { id: orderId },
            include: { city: true },
        });

        if (!order || !['CITY', 'CARGO', 'DELIVERY'].includes(order.mode) || !['CREATED', 'SEARCHING_DRIVER'].includes(order.status) || order.driverId) {
            return;
        }

        if (!order.cityId) {
            this.logger.log(`Order ${orderId} has no cityId, cannot auto-dispatch`);
            return;
        }

        // Update order status to SEARCHING_DRIVER
        const queued = await this.prisma.order.updateMany({
            where: { id: orderId, status: { in: ['CREATED', 'SEARCHING_DRIVER'] }, driverId: null },
            data: { status: 'SEARCHING_DRIVER' },
        });
        if (queued.count !== 1) return;
        await this.recordRideEventSafe({
            orderId,
            fromStatus: order.status,
            toStatus: 'SEARCHING_DRIVER',
            source: 'AUTO_DISPATCH',
            reason: 'Order entered dispatch queue',
        });
        this.realtimeService.publish({
            type: 'order.status.changed',
            entity: 'order',
            entityId: orderId,
            at: new Date().toISOString(),
            payload: { fromStatus: order.status, toStatus: 'SEARCHING_DRIVER' },
        });

        // Get app settings
        const settings = await this.getSettings();
        if (!settings.cityAutoAssignEnabled) {
            this.logger.log(`Auto-assign disabled. Order ${orderId} left in SEARCHING_DRIVER`);
            return;
        }
        const searchRadiusKm = settings.searchRadiusKm || 5;
        const minFreshSec = settings.minDriverLocationFreshSec || 60;

        // Find eligible drivers
        const drivers = await this.findEligibleDrivers(
            order.cityId,
            order.fromLat,
            order.fromLng,
            searchRadiusKm,
            minFreshSec,
            order.currency === 'RUB' ? settings.driverMinOnlineBalanceRub : settings.driverMinOnlineBalance,
            order.currency,
        );

        if (drivers.length === 0) {
            this.logger.log(`No eligible drivers found for order ${orderId}`);
            return;
        }

        // Compute scores and find best driver
        const scoredDrivers = await Promise.all(
            drivers.map(async (driver) => {
                const score = await this.computeScore(driver, order.fromLat, order.fromLng);
                return { driver, score };
            })
        );

        // Sort by total score descending
        scoredDrivers.sort((a, b) => b.score.totalScore - a.score.totalScore);

        // Select best driver
        const bestDriver = scoredDrivers[0];

        // Assign driver to order
        const assigned = await this.prisma.order.updateMany({
            where: { id: orderId, status: 'SEARCHING_DRIVER', driverId: null },
            data: {
                driverId: bestDriver.driver.driverId,
                status: 'DRIVER_ASSIGNED',
                assignedScore: bestDriver.score.totalScore,
                assignedReasonJson: JSON.stringify(bestDriver.score),
            },
        });
        if (assigned.count !== 1) return;
        await this.recordRideEventSafe({
            orderId,
            fromStatus: 'SEARCHING_DRIVER',
            toStatus: 'DRIVER_ASSIGNED',
            actorUserId: bestDriver.driver.driver?.userId ?? null,
            actorRole: 'DRIVER',
            source: 'AUTO_DISPATCH',
            reason: 'Best score driver selected',
            payload: bestDriver.score as unknown as Record<string, unknown>,
        });
        this.realtimeService.publish({
            type: 'order.status.changed',
            entity: 'order',
            entityId: orderId,
            at: new Date().toISOString(),
            payload: {
                fromStatus: 'SEARCHING_DRIVER',
                toStatus: 'DRIVER_ASSIGNED',
                driverId: bestDriver.driver.driverId,
            },
        });
        await this.pushService.sendOrderStatusToPassenger(orderId, 'DRIVER_ASSIGNED');

        this.logger.log(`Assigned driver ${bestDriver.driver.driverId} to order ${orderId} with score ${bestDriver.score.totalScore}`);
    }

    private async findEligibleDrivers(
        cityId: string,
        lat: number,
        lng: number,
        searchRadiusKm: number,
        minFreshSec: number,
        minDriverBalance: number,
        currency = 'KZT',
    ) {
        const minLocationTime = new Date(Date.now() - minFreshSec * 1000);

        const onlineDrivers = await this.prisma.driverOnline.findMany({
            where: {
                isOnline: true,
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
            const hasActiveOrder = await this.prisma.order.findFirst({
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
                        await this.prisma.driverOnline.update({
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
                        const restored = await this.prisma.driverServiceStats.update({
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
            dispatchTimeoutSec: parseInt(settingsMap['dispatchTimeoutSec'] || '20'),
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
