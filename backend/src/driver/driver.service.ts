import { driverDailyBonusProgress, serviceDay } from '../common/driver-daily-bonus';
import { applyDriverActivity, driverOfferActivityKey } from '../common/driver-activity';
import { driverPerformance, DRIVER_ACTIVITY_RULES } from '../common/driver-performance';
import { AutoDispatchService } from '../orders/auto-dispatch.service';
import { currencyForCountry, moneyField } from '../common/currency';
import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { promises as fs } from 'fs';
import { extname, join } from 'path';
import { PrismaService } from '../prisma.service';
import { CreateDriverProfileDto, UpdateLocationDto, SetOnlineDto, DriverDocsUploadUrlDto, CompleteDriverDocsDto, DriverIntercityRouteDto } from './dto/driver.dto';
import { v4 as uuidv4 } from 'uuid';
import { GeoService } from '../geo/geo.service';
import { RealtimeService } from '../realtime/realtime.service';
import { clientUserSelect } from '../common/public-user-select';
import { PushService } from '../notifications/push.service';

@Injectable()
export class DriverService {
    constructor(
        private prisma: PrismaService,
        private geoService: GeoService,
        private realtimeService: RealtimeService,
        private pushService: PushService,
        private autoDispatchService: AutoDispatchService,
    ) { }

    async createProfile(userId: string, dto: CreateDriverProfileDto) {
        await this.prisma.user.update({
            where: { id: userId },
            data: { role: 'DRIVER' },
        });

        const existingProfile = await this.prisma.driverProfile.findUnique({
            where: { userId },
        });

        if (existingProfile) {
            return this.prisma.driverProfile.update({
                where: { userId },
                data: {
                    carModel: dto.carModel,
                    carNumber: dto.carNumber,
                    status: 'PENDING',
                    rejectionReason: null,
                    ...this.driverAcceptModesData(dto),
                },
            });
        }

        const profile = await this.prisma.driverProfile.create({
            data: {
                userId,
                carModel: dto.carModel,
                carNumber: dto.carNumber,
                status: 'PENDING',
                rejectionReason: null,
                ...this.driverAcceptModesData(dto),
            },
        });

        // Create related records
        await this.prisma.driverOnline.create({
            data: { driverId: profile.id, isOnline: false },
        });
        await this.prisma.driverRating.create({
            data: { driverId: profile.id, ratingAvg: 5.0, ratingCount: 0 },
        });
        await this.prisma.driverPriorityFlags.create({
            data: { driverId: profile.id, hasCheckers: false, hasBranding: false },
        });
        await this.prisma.driverServiceStats.create({
            data: { driverId: profile.id },
        });
        await this.prisma.driverPartnerFuelBonus.create({
            data: { driverId: profile.id },
        });

        return profile;
    }

    private driverAcceptModesData(dto: CreateDriverProfileDto) {
        const data: Record<string, boolean> = {};
        for (const key of [
            'acceptCityFixed',
            'acceptCityAuction',
            'acceptIntercity',
            'acceptDelivery',
            'acceptCargo',
        ] as const) {
            if (typeof dto[key] === 'boolean') data[key] = dto[key]!;
        }
        return data;
    }

    private normalizeRouteCity(value: string) {
        return value.trim().replace(/\s+/g, ' ');
    }

    private routeKey(value: string) {
        return this.normalizeRouteCity(value).toLocaleLowerCase('ru-RU');
    }

    async getIntercityRoutes(driverUserId: string) {
        const profile = await this.prisma.driverProfile.findUnique({
            where: { userId: driverUserId },
            select: { id: true },
        });
        if (!profile) throw new NotFoundException('Driver profile not found');
        return this.prisma.driverIntercityRoute.findMany({
            where: { driverId: profile.id, isActive: true },
            orderBy: { createdAt: 'desc' },
        });
    }

    async addIntercityRoute(driverUserId: string, dto: DriverIntercityRouteDto) {
        const profile = await this.prisma.driverProfile.findUnique({
            where: { userId: driverUserId },
            select: { id: true },
        });
        if (!profile) throw new NotFoundException('Driver profile not found');
        const fromCity = this.normalizeRouteCity(dto.fromCity);
        const toCity = this.normalizeRouteCity(dto.toCity);
        if (fromCity.length < 2 || toCity.length < 2) {
            throw new BadRequestException('Укажите город отправления и город назначения');
        }
        if (this.routeKey(fromCity) === this.routeKey(toCity)) {
            throw new BadRequestException('Города маршрута должны отличаться');
        }
        const seatsAvailable = Number.isFinite(Number(dto.seatsAvailable))
            ? Math.max(1, Math.min(8, Math.trunc(Number(dto.seatsAvailable))))
            : 4;
        return this.prisma.driverIntercityRoute.upsert({
            where: {
                driverId_fromCity_toCity: {
                    driverId: profile.id,
                    fromCity,
                    toCity,
                },
            },
            create: { driverId: profile.id, fromCity, toCity, seatsTotal: seatsAvailable, seatsAvailable, isActive: true },
            update: { seatsTotal: seatsAvailable, seatsAvailable, isActive: true },
        });
    }

    async deleteIntercityRoute(driverUserId: string, routeId: string) {
        const profile = await this.prisma.driverProfile.findUnique({
            where: { userId: driverUserId },
            select: { id: true },
        });
        if (!profile) throw new NotFoundException('Driver profile not found');
        const route = await this.prisma.driverIntercityRoute.findFirst({
            where: { id: routeId, driverId: profile.id },
        });
        if (!route) throw new NotFoundException('Route application not found');
        return this.prisma.driverIntercityRoute.update({
            where: { id: routeId },
            data: { isActive: false },
        });
    }

    async updateLocation(driverUserId: string, dto: UpdateLocationDto) {
        const profile = await this.prisma.driverProfile.findUnique({
            where: { userId: driverUserId },
            include: { online: true },
        });

        if (!profile) {
            throw new NotFoundException('Driver profile not found');
        }
        let cityId = dto.cityId || null;
        if (!cityId) {
            const reverse = await this.geoService.reverseGeocode(dto.lat, dto.lng);
            cityId = reverse.cityId;
        }

        if (profile.online?.isOnline) {
            await this.ensureDriverCanStayOnline(driverUserId, profile.id, cityId ?? undefined);
        }
        const updated = await this.prisma.driverOnline.update({
            where: { driverId: profile.id },
            data: {
                lastLat: dto.lat,
                lastLng: dto.lng,
                lastLocationAt: new Date(),
                cityId,
            },
        });
        this.realtimeService.publish({
            type: 'driver.location.updated',
            entity: 'driver',
            entityId: profile.id,
            at: new Date().toISOString(),
            payload: {
                lat: dto.lat,
                lng: dto.lng,
                cityId: cityId ?? null,
            },
        });
        return updated;
    }

    async setOnline(driverUserId: string, dto: SetOnlineDto) {
        const profile = await this.prisma.driverProfile.findUnique({
            where: { userId: driverUserId },
            include: {
                online: true,
                user: true,
            },
        });

        if (!profile) {
            throw new NotFoundException('Driver profile not found');
        }

        if (profile.status !== 'ACTIVE' && profile.status !== 'APPROVED') {
            throw new BadRequestException('Driver profile not approved');
        }
        if (dto.isOnline) {
            const stats = await this.ensureDriverActivityState(profile.id);
            if (stats.activityScore <= 0 || (stats.activityBlockedUntil && stats.activityBlockedUntil > new Date())) throw new BadRequestException('Driver temporarily blocked due to low activity');
            await this.ensureDriverCanStayOnline(driverUserId, profile.id, dto.cityId);
        }

        const resolvedCityId = dto.cityId ?? profile.online?.cityId ?? profile.user?.cityId ?? null;
        const updated = await this.prisma.driverOnline.update({
            where: { driverId: profile.id },
            data: {
                isOnline: dto.isOnline,
                cityId: resolvedCityId,
            },
        });
        this.realtimeService.publish({
            type: 'driver.online.changed',
            entity: 'driver',
            entityId: profile.id,
            at: new Date().toISOString(),
            payload: {
                isOnline: dto.isOnline,
                cityId: resolvedCityId,
            },
        });
        return updated;
    }

    async getMyProfile(driverUserId: string) {
        const profile = await this.prisma.driverProfile.findUnique({
            where: { userId: driverUserId },
            include: {
                online: {
                    include: { city: true },
                },
                rating: true,
                priorityFlags: true,
                serviceStats: true,
                fuelBonus: true,
            },
        });
        if (!profile) return profile;

        const startOfDay = serviceDay().start;
        const [completedCityTrips, completedIntercityTrips, todayCityTrips, todayIntercityTrips] = await Promise.all([
            this.prisma.order.count({
                where: { driverId: profile.id, status: 'COMPLETED' },
            }),
            this.prisma.intercityRequest.count({
                where: { selectedDriverId: driverUserId, status: 'COMPLETED' },
            }),
            this.prisma.order.count({
                where: {
                    driverId: profile.id,
                    status: 'COMPLETED',
                    OR: [
                        { completedAt: { gte: startOfDay } },
                        { updatedAt: { gte: startOfDay } },
                    ],
                },
            }),
            this.prisma.intercityRequest.count({
                where: {
                    selectedDriverId: driverUserId,
                    status: 'COMPLETED',
                    updatedAt: { gte: startOfDay },
                },
            }),
        ]);
        return {
            ...profile,
            performance: driverPerformance(profile),
            completedTrips: completedCityTrips + completedIntercityTrips,
            todayCompletedOrders: todayCityTrips + todayIntercityTrips,
            dailyBonus: await driverDailyBonusProgress(this.prisma, profile.id, driverUserId,
                profile.online?.city?.countryCode === 'RU' ? 'RUB' : 'KZT'),
        };
    }

    async getRuntimeSettings() {
        const settings = await this.prisma.appSettings.findMany({
            where: {
                key: {
                    in: ['driverAutoAcceptEnabled', 'driverAutoAcceptRadiusKm', 'searchRadiusKm', 'driverMinOnlineBalance'],
                },
            },
        });
        const byKey = new Map(settings.map((item) => [item.key, item.value]));
        const fallbackRadius = parseFloat(byKey.get('searchRadiusKm') || '5');
        const radius = parseFloat(byKey.get('driverAutoAcceptRadiusKm') || `${fallbackRadius || 5}`);
        const enabledRaw = (byKey.get('driverAutoAcceptEnabled') || 'true').toLowerCase();
        return {
            autoAcceptEnabled: enabledRaw !== 'false' && enabledRaw !== '0' && enabledRaw !== 'off',
            autoAcceptRadiusKm: Number.isFinite(radius) && radius > 0 ? radius : 5,
            driverMinOnlineBalance: this.parsePositiveNumber(byKey.get('driverMinOnlineBalance'), 100),
        };
    }

    async getNearbyOrders(driverUserId: string) {
        const profile = await this.prisma.driverProfile.findUnique({
            where: { userId: driverUserId },
            include: {
                online: { include: { city: true } },
                rating: true,
                serviceStats: true,
            },
        });

        if (!profile || !profile.online?.isOnline) {
            throw new BadRequestException('Driver is not online');
        }
        await this.ensureDriverCanStayOnline(driverUserId, profile.id);

        const stats = await this.ensureDriverActivityState(profile.id);
        if (stats.activityBlockedUntil && stats.activityBlockedUntil > new Date()) {
            throw new BadRequestException('Driver temporarily blocked due to low activity');
        }
        if (stats.activityScore <= 0) {
            throw new BadRequestException('Driver activity is zero');
        }

        const waitingAuctionOffer = await (this.prisma as any).orderOffer.findFirst({
            where: {
                driverId: profile.id,
                status: 'PENDING',
                updatedAt: { gte: new Date(Date.now() - 60_000) },
                order: {
                    requestType: 'CITY_AUCTION',
                    status: 'SEARCHING_DRIVER',
                },
            },
            select: { id: true },
        });
        if (waitingAuctionOffer) {
            return [];
        }

        const settings = await this.prisma.appSettings.findMany();
        const searchRadiusKm = parseFloat(settings.find(s => s.key === 'searchRadiusKm')?.value || '5');

        const offerAcceptSec = await this.getOfferAcceptWindowSec();
        const nowMs = Date.now();
        const orderModeFilters: any[] = [];
        const cityRequestTypes: string[] = [];
        if (profile.acceptCityFixed) cityRequestTypes.push('CITY_FIXED');
        if (profile.acceptCityAuction) cityRequestTypes.push('CITY_AUCTION');
        if (cityRequestTypes.length > 0) {
            orderModeFilters.push({ mode: 'CITY', requestType: { in: cityRequestTypes } });
        }
        if (profile.acceptCargo) orderModeFilters.push({ mode: 'CARGO' });
        if (profile.acceptDelivery) orderModeFilters.push({ mode: 'DELIVERY' });

        const cityWhere: any = {
            status: 'SEARCHING_DRIVER',
            OR: orderModeFilters,
            AND: [{ OR: [
                { requestType: 'CITY_AUCTION' },
                { dispatchDriverId: profile.id, dispatchExpiresAt: { gt: new Date() } },
            ] }],
        };

        const rejectedOrderEvents = await (this.prisma as any).rideEvent.findMany({
            where: {
                actorUserId: driverUserId,
                actorRole: 'DRIVER',
                reason: 'Driver rejected order',
            },
            select: { orderId: true },
        });
        const rejectedOrderIds = Array.from(new Set(
            rejectedOrderEvents
                .map((event: { orderId?: string | null }) => event.orderId)
                .filter((orderId: string | null | undefined): orderId is string => Boolean(orderId)),
        ));
        if (rejectedOrderIds.length > 0) {
            cityWhere.AND.push({ OR: [
                { requestType: null }, { requestType: { not: 'CITY_AUCTION' } },
                { id: { notIn: rejectedOrderIds } },
            ] });
        }

        const orders = orderModeFilters.length === 0 ? [] : await this.prisma.order.findMany({
            where: cityWhere,
            include: {
                passenger: { select: clientUserSelect },
            },
        });

        const driverLat = profile.online.lastLat ?? profile.online.city?.lat ?? null;
        const driverLng = profile.online.lastLng ?? profile.online.city?.lng ?? null;
        if (driverLat == null || driverLng == null) {
            return [];
        }

        const ratingAvg = profile.rating?.ratingAvg || 5.0;
        const activityScore = stats.activityScore || 0;
        const withDistance = orders.map((order) => {
            const offerExpiresAt = order.dispatchExpiresAt ?? new Date(nowMs + offerAcceptSec * 1000);
            const offerExpiresInSec = Math.max(0, Math.ceil((offerExpiresAt.getTime() - nowMs) / 1000));
            const hasCoords = order.fromLat != null && order.fromLng != null;
            const distanceKm = hasCoords
                ? this.haversine(driverLat, driverLng, order.fromLat, order.fromLng)
                : 0;
            const rankScore = (ratingAvg * 10) + activityScore - (distanceKm * 5);
            return {
                ...order,
                hasUnconfirmedLocation: !hasCoords || (order as any).hasUnconfirmedLocation === true,
                distanceKm,
                rankScore,
                driverActivityScore: activityScore,
                driverRatingAvg: ratingAvg,
                offerExpiresAt,
                offerExpiresInSec,
            };
        });

        const nearbyOrders = withDistance
            .filter((order) => order.requestType !== 'CITY_AUCTION' || order.hasUnconfirmedLocation || order.distanceKm <= searchRadiusKm)
            .sort((a, b) => b.rankScore - a.rankScore);

        const intercityRequests = profile.acceptIntercity
            ? await this.getNearbyIntercityRequestsForDriver(profile.id, driverLat, driverLng, searchRadiusKm, offerAcceptSec, nowMs)
            : [];

        return [...nearbyOrders, ...intercityRequests]
            .sort((a: any, b: any) => (b.rankScore ?? 0) - (a.rankScore ?? 0));
    }

    async getActiveIntercity(driverUserId: string) {
        const acceptedRequests = await this.prisma.intercityRequest.findMany({
            where: {
                selectedDriverId: driverUserId,
                status: { in: ['ACCEPTED', 'DRIVER_ASSIGNED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'IN_PROGRESS'] },
            },
            include: {
                offers: {
                    where: { status: 'ACCEPTED' },
                    take: 1,
                },
            },
            orderBy: { acceptedAt: 'desc' },
            take: 10,
        });

        const passengerIds = Array.from(new Set(
            acceptedRequests
                .map((request) => request.passengerId?.toString() ?? '')
                .filter((id) => id.length > 0),
        ));
        const passengers = passengerIds.length === 0 ? [] : await this.prisma.user.findMany({
            where: { id: { in: passengerIds } },
            select: clientUserSelect,
        });
        const passengersById = new Map(passengers.map((passenger) => [passenger.id, passenger]));

        return acceptedRequests.map((request: any) => {
            const offer = Array.isArray(request.offers) ? request.offers[0] : null;
            const seats = Number(offer?.seats ?? request.seats ?? 1);
            return {
                id: request.id,
                sourceType: 'INTERCITY_REQUEST',
                mode: 'INTERCITY',
                requestType: request.requestType ?? 'INTERCITY',
                status: request.status,
                fromAddress: request.fromManualAddress ?? request.fromAddressLabel ?? request.fromCity,
                toAddress: request.toManualAddress ?? request.toAddressLabel ?? request.toCity,
                fromCity: request.fromCity,
                toCity: request.toCity,
                fromLat: request.fromLat,
                fromLng: request.fromLng,
                toLat: request.toLat,
                toLng: request.toLng,
                paymentMethod: request.paymentMethod,
                date: request.date,
                seats,
                price: offer?.price ?? request.price ?? null,
                currency: request.currency,
                passenger: passengersById.get(request.passengerId) ?? null,
                acceptedAt: request.acceptedAt,
            };
        });
    }

    private async getNearbyIntercityRequestsForDriver(
        driverId: string,
        driverLat: number,
        driverLng: number,
        searchRadiusKm: number,
        offerAcceptSec: number,
        nowMs: number,
    ) {
        const routeApplications = await this.prisma.driverIntercityRoute.findMany({
            where: { driverId, isActive: true },
            select: { fromCity: true, toCity: true, seatsAvailable: true },
        });
        if (routeApplications.length === 0) return [];
        const allowedRoutes = new Map(
            routeApplications.map((route) => [
                `${this.routeKey(route.fromCity)}→${this.routeKey(route.toCity)}`,
                route,
            ]),
        );

        const requests = await this.prisma.intercityRequest.findMany({
            where: {
                status: 'OPEN',
                requestType: { in: ['INTERCITY', 'DELIVERY_INTERCITY', 'DELIVERY_RF'] },
                offers: { none: { driverId, status: { in: ['PENDING', 'ACCEPTED'] } } },
            },
            take: 50,
            orderBy: { createdAt: 'desc' },
        });
        return requests
            .filter((request: any) => {
                const route = allowedRoutes.get(`${this.routeKey(request.fromCity)}→${this.routeKey(request.toCity)}`);
                if (!route) return false;
                const seatsNeeded = Math.max(1, Math.trunc(Number(request.seats ?? 1)));
                return route.seatsAvailable >= seatsNeeded;
            })
            .map((request: any) => {
                const route = allowedRoutes.get(`${this.routeKey(request.fromCity)}→${this.routeKey(request.toCity)}`);
                const hasCoords = request.fromLat != null && request.fromLng != null;
                const distanceKm = hasCoords
                    ? this.haversine(driverLat, driverLng, request.fromLat, request.fromLng)
                    : 0;
                const offerExpiresAt = new Date(nowMs + offerAcceptSec * 1000);
                const offerExpiresInSec = offerAcceptSec;
                return {
                    id: request.id,
                    sourceType: 'INTERCITY_REQUEST',
                    mode: 'INTERCITY',
                    requestType: request.requestType ?? 'INTERCITY',
                    status: 'SEARCHING_DRIVER',
                    fromLat: request.fromLat,
                    fromLng: request.fromLng,
                    toLat: request.toLat,
                    toLng: request.toLng,
                    fromAddress: request.fromManualAddress ?? request.fromAddressLabel ?? request.fromCity,
                    toAddress: request.toManualAddress ?? request.toAddressLabel ?? request.toCity,
                    hasUnconfirmedLocation: !hasCoords || request.hasUnconfirmedLocation === true,
                    paymentMethod: request.paymentMethod,
                    comment: request.comment,
                    price: null,
                    currency: request.currency,
                    seats: request.seats ?? 1,
                    driverRouteSeatsAvailable: route?.seatsAvailable ?? null,
                    distanceKm,
                    rankScore: 100 - distanceKm,
                    offerExpiresAt,
                    offerExpiresInSec,
                };
            })
            .filter((request: any) => request.hasUnconfirmedLocation || request.distanceKm <= Math.max(searchRadiusKm, 50));
    }

    async acceptOrder(driverUserId: string, orderId: string) {
        const profile = await this.prisma.driverProfile.findUnique({
            where: { userId: driverUserId },
            include: { serviceStats: true },
        });

        if (!profile) {
            throw new NotFoundException('Driver profile not found');
        }
        await this.ensureDriverCanStayOnline(driverUserId, profile.id);

        const stats = await this.ensureDriverActivityState(profile.id);
        if (stats.activityBlockedUntil && stats.activityBlockedUntil > new Date()) {
            throw new BadRequestException('Driver temporarily blocked due to low activity');
        }
        if (stats.activityScore <= 0) {
            throw new BadRequestException('Driver activity is zero');
        }

        const order = await this.prisma.order.findUnique({
            where: { id: orderId },
        });

        if (!order || order.status !== 'SEARCHING_DRIVER') {
            throw new BadRequestException('Order not available');
        }
        if ((order.requestType || '').toUpperCase() === 'CITY_AUCTION') {
            throw new BadRequestException('Для аукциона отправьте своё предложение цены');
        }

        const result = await this.prisma.$transaction(async (tx) => {
        const accepted = await tx.order.updateMany({
            where: { id: orderId, status: 'SEARCHING_DRIVER', driverId: null,
                dispatchDriverId: profile.id, dispatchExpiresAt: { gt: new Date() } },
            data: { driverId: profile.id, status: 'DRIVER_EN_ROUTE',
                dispatchDriverId: null, dispatchExpiresAt: null, dispatchRetryAt: null },
        });
        if (accepted.count !== 1) throw new BadRequestException('Время ответа истекло или заказ предложен другому водителю');
        const activity = await applyDriverActivity(tx, profile.id, `accept:city:${orderId}:${profile.id}`, DRIVER_ACTIVITY_RULES.acceptReward);
        return { order: await tx.order.findUnique({ where: { id: orderId } }), activity };

        });
        const updated = result.order;
        this.realtimeService.publish({ type: 'driver.activity.updated', entity: 'driver', entityId: profile.id, at: new Date().toISOString(), payload: { activityScore: result.activity.activityScore } });
        await this.recordRideEventSafe({
            orderId: order.id,
            fromStatus: order.status,
            toStatus: 'DRIVER_EN_ROUTE',
            actorUserId: driverUserId,
            actorRole: 'DRIVER',
            source: 'DRIVER_APP',
            reason: 'Driver accepted order',
        });
        this.realtimeService.publish({
            type: 'order.status.changed',
            entity: 'order',
            entityId: order.id,
            at: new Date().toISOString(),
            payload: {
                fromStatus: order.status,
                toStatus: 'DRIVER_EN_ROUTE',
                driverUserId: driverUserId,
            },
        });
        await this.pushService.sendOrderStatusToPassenger(order.id, 'DRIVER_EN_ROUTE');
        return updated;
    }

    async rejectOrder(driverUserId: string, orderId: string) {
        const profile = await this.prisma.driverProfile.findUnique({
            where: { userId: driverUserId },
        });

        if (!profile) {
            throw new NotFoundException('Driver profile not found');
        }

        const order = await this.prisma.order.findUnique({ where: { id: orderId } });
        if (!order || order.status !== 'SEARCHING_DRIVER') {
            throw new BadRequestException('Order not available');
        }

        const updatedStats = await this.prisma.$transaction(async (tx) => {
            if (order.requestType !== 'CITY_AUCTION') {
                const declined = await tx.order.updateMany({
                    where: { id: orderId, status: 'SEARCHING_DRIVER', driverId: null,
                        dispatchDriverId: profile.id, dispatchExpiresAt: { gt: new Date() } },
                    data: { dispatchDriverId: null, dispatchExpiresAt: null, dispatchRetryAt: null },
                });
                if (declined.count !== 1) throw new BadRequestException('Время ответа истекло или заказ предложен другому водителю');
            }
            const stats = await applyDriverActivity(tx, profile.id, driverOfferActivityKey(order, profile.id), -DRIVER_ACTIVITY_RULES.rejectPenalty);
            if (stats.activityScore <= 0) await tx.driverOnline.updateMany({where:{driverId:profile.id},data:{isOnline:false}});
            return stats;
        });
        this.realtimeService.publish({ type: 'driver.activity.updated', entity: 'driver', entityId: profile.id, at: new Date().toISOString(), payload: { activityScore: updatedStats.activityScore } });
        if (updatedStats.activityScore <= 0) this.realtimeService.publish({type:'driver.online.changed',entity:'driver',entityId:profile.id,at:new Date().toISOString(),payload:{isOnline:false,reason:'ACTIVITY_BLOCKED'}});
        await this.recordRideEventSafe({
            orderId: order.id,
            fromStatus: order.status,
            toStatus: order.status,
            actorUserId: driverUserId,
            actorRole: 'DRIVER',
            source: 'DRIVER_APP',
            reason: 'Driver rejected order',
            payload: {
                activityScore: updatedStats.activityScore,
                blockedUntil: updatedStats.activityBlockedUntil?.toISOString?.() ?? null,
            },
        });
        this.realtimeService.publish({
            type: 'order.offer.rejected',
            entity: 'order',
            entityId: order.id,
            at: new Date().toISOString(),
            payload: {
                driverUserId,
                activityScore: updatedStats.activityScore,
                blockedUntil: updatedStats.activityBlockedUntil?.toISOString?.() ?? null,
            },
        });
        if (order.requestType !== 'CITY_AUCTION') await this.autoDispatchService.assignCityOrder(orderId);
        return {
            ok: true,
            orderId,
            activityScore: updatedStats.activityScore,
            blockedUntil: updatedStats.activityBlockedUntil,
        };
    }

    async getUploadUrl(driverUserId: string, dto: DriverDocsUploadUrlDto) {
        const profile = await this.prisma.driverProfile.findUnique({
            where: { userId: driverUserId },
        });

        if (!profile) {
            throw new NotFoundException('Driver profile not found');
        }

        const docType = dto.docType || 'document';
        const safeFileName = dto.fileName
            ? dto.fileName.replace(/[^a-zA-Z0-9._-]/g, '_')
            : `${docType}_${uuidv4()}`;
        const fileName = `${profile.id}/${safeFileName}`;
        const bucket = process.env.GCS_BUCKET;

        if (bucket) {
            // GCS upload URL
            return {
                uploadUrl: `https://storage.googleapis.com/${bucket}/${fileName}`,
                fileName,
            };
        } else {
            // Local storage
            return {
                uploadUrl: `/uploads/${fileName}`,
                fileName,
            };
        }
    }

    async uploadDoc(driverUserId: string, docTypeRaw: string | undefined, file: any) {
        const profile = await this.prisma.driverProfile.findUnique({
            where: { userId: driverUserId },
        });

        if (!profile) {
            throw new NotFoundException('Driver profile not found');
        }
        if (!file?.buffer?.length) {
            throw new BadRequestException('Document file is required');
        }

        const docType = docTypeRaw || 'passport';
        const updateField = this.driverDocUrlField(docType);
        const originalName = String(file.originalname || `${docType}.jpg`);
        const safeExt = extname(originalName).replace(/[^a-zA-Z0-9.]/g, '') || '.jpg';
        const safeDocType = docType.replace(/[^a-zA-Z0-9_-]/g, '_');
        const relativeName = `${profile.id}/${safeDocType}_${uuidv4()}${safeExt}`;
        const uploadRoot = process.env.UPLOAD_DIR || join(process.cwd(), 'uploads');
        const targetPath = join(uploadRoot, relativeName);

        await fs.mkdir(join(uploadRoot, profile.id), { recursive: true });
        await fs.writeFile(targetPath, file.buffer);

        const url = `/uploads/${relativeName}`;
        await this.prisma.driverProfile.update({
            where: { userId: driverUserId },
            data: {
                [updateField]: url,
                status: 'PENDING',
                rejectionReason: null,
            },
        });

        return { ok: true, docType, url };
    }

    private driverDocUrlField(docType: string) {
        switch (docType) {
            case 'selfie':
                return 'selfieUrl';
            case 'techPassportFront':
                return 'techPassportFrontUrl';
            case 'techPassportBack':
            case 'osago':
                return 'techPassportBackUrl';
            case 'driverLicense':
                return 'driverLicenseUrl';
            case 'passport':
            default:
                return 'passportUrl';
        }
    }

    async completeDocs(driverUserId: string, dto: CompleteDriverDocsDto) {
        const profile = await this.prisma.driverProfile.findUnique({
            where: { userId: driverUserId },
        });

        if (!profile) {
            throw new NotFoundException('Driver profile not found');
        }

        return this.prisma.driverProfile.update({
            where: { userId: driverUserId },
            data: {
                selfieUrl: dto.selfieUrl ?? profile.selfieUrl,
                techPassportFrontUrl: dto.techPassportFrontUrl ?? profile.techPassportFrontUrl,
                techPassportBackUrl: dto.techPassportBackUrl ?? profile.techPassportBackUrl,
                driverLicenseUrl: dto.driverLicenseUrl ?? profile.driverLicenseUrl,
                passportUrl: dto.passportUrl ?? profile.passportUrl,
                status: 'PENDING',
                rejectionReason: null,
            },
        });
    }

    private haversine(lat1: number, lng1: number, lat2: number, lng2: number): number {
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

    private parsePositiveNumber(value: string | undefined | null, fallback: number): number {
        const parsed = parseFloat(value || '');
        return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
    }

    private async getDriverMinOnlineBalance(currency = 'KZT'): Promise<number> {
        const setting = await this.prisma.appSettings.findUnique({
            where: { key: currency === 'RUB' ? 'driverMinOnlineBalanceRub' : 'driverMinOnlineBalance' },
        });
        return this.parsePositiveNumber(setting?.value, 100);
    }

    private async ensureDriverCanStayOnline(driverUserId: string, driverId: string, selectedCityId?: string) {
        const online = await this.prisma.driverOnline.findUnique({ where: { driverId }, include: { city: true } });
        const user = await this.prisma.user.findUnique({ where: { id: driverUserId }, select: { cityId: true } });
        const cityId = selectedCityId ?? online?.cityId ?? user?.cityId;
        const city = cityId ? await this.prisma.city.findUnique({ where: { id: cityId } }) : null;
        const currency = currencyForCountry(city?.countryCode);
        const symbol = currency === 'RUB' ? '₽' : '₸';
        const minBalance = await this.getDriverMinOnlineBalance(currency);
        if (minBalance <= 0) return;

        const wallet = await this.prisma.wallet.findUnique({
            where: { userId: driverUserId },
            select: { money: true, moneyRub: true },
        });
        const balance = wallet?.[moneyField(currency)] ?? 0;
        if (balance >= minBalance) return;

        await this.prisma.driverOnline.update({
            where: { driverId },
            data: { isOnline: false },
        }).catch(() => null);
        this.realtimeService.publish({
            type: 'driver.online.changed',
            entity: 'driver',
            entityId: driverId,
            at: new Date().toISOString(),
            payload: {
                isOnline: false,
                reason: 'LOW_BALANCE',
                balance,
                minBalance,
            },
        });
        throw new BadRequestException(
            `Для выхода на линию нужен баланс не меньше ${minBalance} ${symbol}. Сейчас доступно ${balance} ${symbol}. Пополните баланс.`,
        );
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

    private async ensureDriverActivityState(driverId: string) {
        const stats = await this.prisma.driverServiceStats.findUnique({
            where: { driverId },
        });
        if (!stats) {
            return this.prisma.driverServiceStats.create({
                data: { driverId, activityScore: DRIVER_ACTIVITY_RULES.initialScore },
            });
        }

        if (
            stats.activityScore <= 0 &&
            stats.activityBlockedUntil &&
            stats.activityBlockedUntil <= new Date()
        ) {
            return this.prisma.driverServiceStats.update({
                where: { driverId },
                data: {
                    activityScore: DRIVER_ACTIVITY_RULES.restoredScore,
                    activityBlockedUntil: null,
                },
            });
        }

        return stats;
    }

    private async getOfferAcceptWindowSec(): Promise<number> {
        const setting = await this.prisma.appSettings.findUnique({
            where: { key: 'driverOfferAcceptSec' },
        });
        const sec = parseInt(setting?.value || '30', 10);
        if (!Number.isFinite(sec) || sec <= 0) return 30;
        return sec;
    }
}
