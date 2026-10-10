import { driverPriority, DRIVER_ACTIVITY_RULES } from '../common/driver-performance';
import { applyDriverActivity, driverOfferActivityKey } from '../common/driver-activity';
import { moneyField } from '../common/currency';
import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { PushService } from '../notifications/push.service';

export interface DriverScore {
    driverId: string;
    totalScore: number;
    distanceScore: number;
    ratingScore: number;
    activityScore: number;
    priorityScore: number;
    randomJitter: number;
}

export function compareDriverScores(a: DriverScore, b: DriverScore) {
    return b.priorityScore - a.priorityScore || b.activityScore - a.activityScore ||
        b.ratingScore - a.ratingScore || b.distanceScore - a.distanceScore || a.driverId.localeCompare(b.driverId);
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
            const stale = await this.prisma.orderOffer.findMany({where: {status: 'PENDING', expiresAt: {lte: new Date()}}, select: {id: true, orderId: true, driverId: true}});
            for (const item of stale) {
                const expired = await this.prisma.orderOffer.updateMany({where: {id: item.id, status: 'PENDING', expiresAt: {lte: new Date()}}, data: {status: 'EXPIRED'}});
                if (expired.count) this.realtimeService.publish({type: 'order.offer.expired', entity: 'order', entityId: item.orderId, at: new Date().toISOString(), payload: {orderId: item.orderId, offerId: item.id, driverId: item.driverId}});
            }
            await this.expireAuctionInvitations();
            const orders = await this.prisma.order.findMany({
                where: { status: { in: ['CREATED', 'SEARCHING_DRIVER'] }, driverId: null,
                    mode: { in: ['CITY', 'CARGO', 'DELIVERY'] },
                    AND: [
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
        const draft = await this.prisma.order.findUnique({where: {id: orderId}});
        if (draft?.requestType === 'CITY_AUCTION') return this.broadcastAuctionOrder(orderId, settings);
        const timeouts: Array<{driverId: string; activityScore: number}> = [];
        const offer = await this.prisma.$transaction(async (tx) => {
            // One dispatcher across every API worker. Acceptance/rejection use conditional writes.
            await tx.$executeRaw`SELECT pg_advisory_xact_lock(741302091)`;
            const order = await tx.order.findUnique({ where: { id: orderId } });
            if (!order || !['CITY', 'CARGO', 'DELIVERY'].includes(order.mode) ||
                !order.cityId || order.driverId ||
                !['CREATED', 'SEARCHING_DRIVER'].includes(order.status)) return null;
            const now = new Date();
            if (order.dispatchRetryAt && order.dispatchRetryAt > now) return null;
            if (order.dispatchDriverId && order.dispatchExpiresAt && order.dispatchExpiresAt > now) {
                const online = await tx.driverOnline.findUnique({ where: { driverId: order.dispatchDriverId } });
                if (online?.isOnline && online.cityId === order.cityId) return null;
            }
            const queued = await tx.order.updateMany({
                where: { id: orderId, status: { in: ['CREATED', 'SEARCHING_DRIVER'] }, driverId: null,
                    dispatchDriverId: order.dispatchDriverId, dispatchExpiresAt: order.dispatchExpiresAt },
                data: { status: 'SEARCHING_DRIVER', dispatchDriverId: null, dispatchExpiresAt: null },
            });
            if (!queued.count) return null;
            if (order.dispatchDriverId && order.dispatchExpiresAt && order.dispatchExpiresAt <= now) {
                const stats = await applyDriverActivity(tx, order.dispatchDriverId,
                    driverOfferActivityKey(order, order.dispatchDriverId), -DRIVER_ACTIVITY_RULES.rejectPenalty, now);
                await tx.driverOnline.updateMany({ where: { driverId: order.dispatchDriverId }, data: { isOnline: false } });
                timeouts.push({ driverId: order.dispatchDriverId, activityScore: stats.activityScore });
            }
            const drivers = await this.findEligibleDrivers(order.cityId, order.fromLat, order.fromLng,
                settings.searchRadiusKm, settings.minDriverLocationFreshSec,
                order.currency === 'RUB' ? settings.driverMinOnlineBalanceRub : settings.driverMinOnlineBalance,
                order.currency, tx);
            const compatible = drivers.filter((d) => order.mode === 'CARGO' ? d.driver.acceptCargo :
                order.mode === 'DELIVERY' ? d.driver.acceptDelivery : order.requestType === 'CITY_AUCTION' ? d.driver.acceptCityAuction : d.driver.acceptCityFixed);
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
            scored.sort((a, b) => compareDriverScores(a.score, b.score));
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
        for (const timeout of timeouts) {
            this.realtimeService.publish({type: 'driver.online.changed', entity: 'driver', entityId: timeout.driverId,
                at: new Date().toISOString(), payload: { isOnline: false, reason: 'OFFER_TIMEOUT', activityScore: timeout.activityScore }});
        }
        if (!offer) return;
        await this.recordRideEventSafe({orderId, fromStatus: 'SEARCHING_DRIVER', toStatus: 'SEARCHING_DRIVER',
            source: 'AUTO_DISPATCH', reason: 'Driver offered order',
            payload: {driverId: offer.driverId, expiresAt: offer.expiresAt.toISOString()}});
        this.realtimeService.publish({type: 'order.dispatch.offered', entity: 'order', entityId: orderId,
            at: new Date().toISOString(), payload: { driverId: offer.driverId, expiresAt: offer.expiresAt }});
        await this.pushService.sendToUser(offer.userId, {title: 'Новый заказ', body: 'Примите заказ или откажитесь до окончания времени ответа.',
            data: {type: 'driver_offer', route: '/driver/home', orderId, expiresAt: offer.expiresAt.toISOString()}}).catch(() => false);
    }

    private async expireAuctionInvitations() {
        const expired = await this.prisma.$transaction(async tx => {
            await tx.$executeRaw`SELECT pg_advisory_xact_lock(741302091)`;
            const now = new Date();
            const invites = await tx.orderAuctionInvitation.findMany({where: {status: 'PENDING', expiresAt: {lte: now}}, include: {order: true}});
            const changes: Array<{driverId: string; activityScore: number}> = [];
            for (const invitation of invites) {
                const live = invitation.order.status === 'SEARCHING_DRIVER' && !invitation.order.driverId;
                const changed = await tx.orderAuctionInvitation.updateMany({where: {id: invitation.id, status: 'PENDING'}, data: {status: live ? 'EXPIRED' : 'CANCELLED'}});
                if (changed.count && live) {
                    const stats = await applyDriverActivity(tx, invitation.driverId, `auction-invite:${invitation.id}`, -DRIVER_ACTIVITY_RULES.rejectPenalty, now);
                    await tx.driverOnline.updateMany({where: {driverId: invitation.driverId}, data: {isOnline: false}});
                    changes.push({driverId: invitation.driverId, activityScore: stats.activityScore});
                }
            }
            return changes;
        });
        for (const change of expired) this.realtimeService.publish({type: 'driver.online.changed', entity: 'driver', entityId: change.driverId, at: new Date().toISOString(), payload: {...change, isOnline: false, reason: 'OFFER_TIMEOUT'}});
    }

    private async broadcastAuctionOrder(orderId: string, settings: any) {
        const invites = await this.prisma.$transaction(async tx => {
            await tx.$executeRaw`SELECT pg_advisory_xact_lock(741302091)`;
            const order = await tx.order.findUnique({where: {id: orderId}});
            if (!order || !order.cityId || order.driverId || order.status !== 'SEARCHING_DRIVER') return [];
            const drivers = await this.findEligibleDrivers(order.cityId, order.fromLat, order.fromLng,
                settings.searchRadiusKm, settings.minDriverLocationFreshSec,
                order.currency === 'RUB' ? settings.driverMinOnlineBalanceRub : settings.driverMinOnlineBalance, order.currency, tx);
            const result: Array<{driverId: string; userId: string; expiresAt: Date}> = [];
            for (const driver of drivers.filter(item => item.driver.acceptCityAuction && item.driver.userId !== order.passengerId && !item.locationFallback && item.distanceFromPassenger <= settings.searchRadiusKm)) {
                const existing = await tx.orderAuctionInvitation.findUnique({where: {orderId_driverId: {orderId, driverId: driver.driverId}}});
                if (existing) continue;
                const expiresAt = new Date(Date.now() + 30_000);
                await tx.orderAuctionInvitation.create({data: {orderId, driverId: driver.driverId, expiresAt}});
                result.push({driverId: driver.driverId, userId: driver.driver.userId, expiresAt});
            }
            return result;
        }, {maxWait: 10000, timeout: 15000});
        await Promise.all(invites.map(async invite => {
            this.realtimeService.publish({type: 'order.dispatch.offered', entity: 'order', entityId: orderId, at: new Date().toISOString(), payload: {driverId: invite.driverId, expiresAt: invite.expiresAt}});
            await this.pushService.sendToUser(invite.userId, {title: 'Новый заказ такси', body: 'Согласитесь с ценой пассажира или предложите свою.', data: {type: 'driver_offer', route: '/driver/home', orderId, expiresAt: invite.expiresAt.toISOString()}}).catch(() => false);
        }));
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
            const incomingAuction = await db.orderAuctionInvitation.findFirst({where: {driverId: onlineDriver.driverId, status: 'PENDING', order: {status: 'SEARCHING_DRIVER'}}});
            if (incomingAuction) continue;
            const pendingPrice = await db.orderOffer.findFirst({where: {driverId: onlineDriver.driverId, status: 'PENDING', expiresAt: {gt: new Date()}, order: {status: 'SEARCHING_DRIVER'}}});
            if (pendingPrice) continue;
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
                            data: { activityScore: DRIVER_ACTIVITY_RULES.restoredScore, activityBlockedUntil: null },
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
        const ratingAvg = driver.driver.rating?.ratingCount > 0
            ? Math.max(0, Math.min(5, Number(driver.driver.rating.ratingAvg) || 0)) : 0;
        const ratingScore = ratingAvg * 5;

        // Activity score: direct weight (0..100+)
        const activity = Math.max(0, driver.driver.serviceStats?.activityScore ?? 100);
        const activityScore = activity * 0.5;

        // Priority score calculation
        const priorityPoints = driverPriority(driver.driver).total;
        const priorityScore = priorityPoints;

        // Random jitter: 0-1
        const randomJitter = 0;

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
