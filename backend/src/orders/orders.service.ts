import { Injectable, NotFoundException, BadRequestException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { GeoService } from '../geo/geo.service';
import { AutoDispatchService } from './auto-dispatch.service';
import { CreateOrderDto, PreviewOrderDto } from './dto/orders.dto';
import { RealtimeService } from '../realtime/realtime.service';
import { clientUserSelect } from '../common/public-user-select';
import { PushService } from '../notifications/push.service';

@Injectable()
export class OrdersService {
    private static readonly FIXED_CITY_VEHICLE_CLASSES = [
        'ECONOMY',
        'OPTIMAL',
        'COMFORT',
        'BUSINESS',
    ] as const;

    constructor(
        private prisma: PrismaService,
        private geoService: GeoService,
        private autoDispatchService: AutoDispatchService,
        private realtimeService: RealtimeService,
        private pushService: PushService,
    ) { }

    private normalizeRequestType(raw?: string | null, mode?: string | null) {
        const normalized = (raw || '').trim().toUpperCase();
        if (normalized) return normalized;
        if ((mode || '').toUpperCase() === 'CITY') return 'CITY_FIXED';
        return null;
    }

    private inferMode(requestType?: string | null, mode?: string | null) {
        const normalizedMode = (mode || '').trim().toUpperCase();
        if (['CITY', 'INTERCITY', 'CARGO', 'DELIVERY'].includes(normalizedMode)) {
            return normalizedMode as 'CITY' | 'INTERCITY' | 'CARGO' | 'DELIVERY';
        }

        switch ((requestType || '').trim().toUpperCase()) {
            case 'CITY_FIXED':
            case 'CITY_AUCTION':
                return 'CITY';
            case 'INTERCITY':
                return 'INTERCITY';
            case 'DELIVERY_CITY':
            case 'DELIVERY_INTERCITY':
            case 'DELIVERY_RF':
                return 'DELIVERY';
            default:
                return 'CITY';
        }
    }

    private normalizePaymentMethod(raw?: string | null) {
        const normalized = (raw || '').trim().toUpperCase();
        if (['CASH', 'CARD_TRANSFER', 'BONUSES'].includes(normalized)) {
            return normalized;
        }
        return 'CASH';
    }

    private normalizeVehicleClass(raw?: string | null) {
        const normalized = (raw || '').trim().toUpperCase();
        if (
            OrdersService.FIXED_CITY_VEHICLE_CLASSES.includes(
                normalized as (typeof OrdersService.FIXED_CITY_VEHICLE_CLASSES)[number],
            )
        ) {
            return normalized;
        }
        return 'ECONOMY';
    }

    private normalizePhoneDigits(value?: string | null) {
        let digits = (value || '').replace(/\D/g, '');
        if (digits.length === 11 && digits.startsWith('8')) {
            digits = `7${digits.slice(1)}`;
        }
        return digits;
    }

    private isKazakhstanPhone(value?: string | null) {
        const digits = this.normalizePhoneDigits(value);
        return digits.startsWith('76') || digits.startsWith('77');
    }

    private async resolveCityTariff(cityId: string | null) {
        const where = cityId ? { cityId, isActive: true } : { isActive: true };
        const cityTariffs = await this.prisma.tariffCity.findMany({
            where,
            orderBy: { basePrice: 'asc' },
        });
        const fallbackTariffs = cityId && cityTariffs.length == 0
            ? await this.prisma.tariffCity.findMany({
                where: { isActive: true },
                orderBy: { basePrice: 'asc' },
            })
            : cityTariffs;
        const tariffs = fallbackTariffs;
        if (tariffs.length === 0) {
            return { tariff: null as any, multiplier: 1 };
        }

        return {
            tariff: tariffs[0],
            multiplier: 1,
        };
    }

    async previewOrder(dto: PreviewOrderDto) {
        const preview = await this.previewOrderDtoToOrder(dto);
        return {
            distance: preview.distance,
            duration: preview.duration,
            price: preview.price,
            tariff: preview.tariff,
        };
    }

    async createOrder(userId: string, dto: CreateOrderDto) {
        const requestType = this.normalizeRequestType(dto.requestType, dto.mode);
        const mode = this.inferMode(requestType, dto.mode);
        if (requestType && !['CITY_FIXED', 'CITY_AUCTION'].includes(requestType)) {
            throw new BadRequestException('This endpoint only supports city orders');
        }

        const paymentMethod = this.normalizePaymentMethod(dto.paymentMethod);
        const isCityAuction = requestType === 'CITY_AUCTION';
        if (mode === 'CITY' && !isCityAuction && !dto.vehicleClass) {
            throw new BadRequestException('Vehicle class is required for fixed city order');
        }
        const vehicleClass = mode === 'CITY' && !isCityAuction
            ? this.normalizeVehicleClass(dto.vehicleClass)
            : null;
        const useBonus = paymentMethod === 'BONUSES' ? true : dto.useBonus === true;
        if (mode === 'DELIVERY' && paymentMethod === 'BONUSES') {
            throw new BadRequestException('Bonuses are not available for delivery');
        }

        const preview = isCityAuction
            ? await this.cityAuctionDraftToOrder(dto)
            : await this.previewOrderDtoToOrder(dto);
        if (!isCityAuction && (!Number.isFinite(preview.price) || preview.price <= 0)) {
            throw new BadRequestException('Unable to calculate order price');
        }
        const settings = await this.prisma.appSettings.findMany({
            where: { key: { in: ['orderCommissionPercent'] } },
        });
        const commissionPercent = parseFloat(
            settings.find((s) => s.key === 'orderCommissionPercent')?.value || '10'
        );

        let bonusUsedAmount = 0;
        if (useBonus) {
            const wallet = await this.prisma.wallet.findUnique({ where: { userId } });
            if (!wallet || wallet.bonus < preview.price) {
                throw new BadRequestException('Insufficient bonus balance');
            }
            bonusUsedAmount = preview.price;
        }

        const order = await this.prisma.$transaction(async (tx) => {
            let userWalletId: string | null = null;
            if (bonusUsedAmount > 0) {
                const wallet = await tx.wallet.findUnique({
                    where: { userId },
                    select: { id: true },
                });
                userWalletId = wallet?.id ?? null;
                await tx.wallet.update({
                    where: { userId },
                    data: { bonus: { decrement: bonusUsedAmount } },
                });
            }

            const createdOrder = await tx.order.create({
                data: {
                    passengerId: userId,
                    fromLat: dto.fromLat,
                    fromLng: dto.fromLng,
                    fromAddress: dto.fromAddress,
                    fromManualAddress: null,
                    fromAddressSource: 'GEOCODED',
                    toLat: dto.toLat,
                    toLng: dto.toLng,
                    toAddress: dto.toAddress,
                    toManualAddress: null,
                    toAddressSource: 'GEOCODED',
                    mode,
                    requestType: requestType ?? 'CITY_FIXED',
                    price: isCityAuction ? 0 : preview.price,
                    priceSource: isCityAuction ? 'DRIVER_OFFER' : 'SYSTEM',
                    paymentMethod,
                    vehicleClass,
                    comment: dto.comment?.trim() || null,
                    hasUnconfirmedLocation: false,
                    distanceKm: preview.distance,
                    durationMin: preview.duration,
                    doorToDoor: dto.doorToDoor || false,
                    doorToDoorFee: dto.doorToDoor ? (preview.tariff?.doorToDoorFee || 0) : 0,
                    status: isCityAuction ? 'SEARCHING_DRIVER' : 'CREATED',
                    cityId: preview.cityId,
                    bonusUsedAmount,
                    paidWithBonus: bonusUsedAmount > 0,
                    commissionAmount: !isCityAuction && preview.price > 0 ? (preview.price * commissionPercent) / 100 : 0,
                },
            });
            if (bonusUsedAmount > 0 && userWalletId) {
                await (tx as any).walletTransaction.create({
                    data: {
                        walletId: userWalletId,
                        type: 'ORDER_BONUS_USED',
                        direction: 'DEBIT',
                        balanceSource: 'BONUS',
                        amount: bonusUsedAmount,
                        orderId: createdOrder.id,
                        actorUserId: userId,
                        note: 'Bonus used for order payment',
                    },
                }).catch(() => null);
            }
            return createdOrder;
        });

        // Auto-dispatch for CITY-like modes
        if ((mode === 'CITY' || mode === 'CARGO' || mode === 'DELIVERY') && !isCityAuction) {
            await this.autoDispatchService.assignCityOrder(order.id);
        }

        this.realtimeService.publish({
            type: 'order.created',
            entity: 'order',
            entityId: order.id,
            at: new Date().toISOString(),
            payload: {
                status: order.status,
                mode: order.mode,
                requestType: requestType ?? 'CITY_FIXED',
                passengerId: order.passengerId,
            },
        });

        return order;
    }

    private async cityAuctionDraftToOrder(dto: CreateOrderDto) {
        const geoResult = await this.geoService.reverseGeocode(dto.fromLat, dto.fromLng);
        const distance = this.haversine(dto.fromLat, dto.fromLng, dto.toLat, dto.toLng);
        return {
            distance,
            duration: null,
            price: 0,
            tariff: null,
            cityId: geoResult?.cityId ?? null,
        };
    }

    private async previewOrderDtoToOrder(dto: PreviewOrderDto) {
        const requestType = this.normalizeRequestType(dto.requestType, dto.mode);
        const mode = this.inferMode(requestType, dto.mode);
        if (requestType && requestType !== 'CITY_FIXED') {
            throw new BadRequestException('Price preview is only available for fixed-price city orders');
        }
        const route = await this.geoService.getRoute(dto.fromLat, dto.fromLng, dto.toLat, dto.toLng);

        let price = 0;
        let tariff: any = null;
        let cityId = null;

        const geoResult = await this.geoService.reverseGeocode(dto.fromLat, dto.fromLng);
        cityId = geoResult?.cityId;

        if (mode === 'CITY') {
            const resolved = await this.resolveCityTariff(cityId);
            tariff = resolved.tariff;
            if (tariff) {
                const multiplier = resolved.multiplier || 1;
                price = Math.max(
                    tariff.minPrice * multiplier,
                    (tariff.basePrice + (route.distance * tariff.pricePerKm) + (route.duration * tariff.pricePerMin)) * multiplier
                );
            }
        } else if (mode === 'CARGO') {
            tariff = await this.prisma.tariffCargo.findFirst({
                where: { isActive: true },
                orderBy: { basePrice: 'asc' },
            });
            if (tariff) {
                price = Math.max(
                    tariff.minPrice,
                    tariff.basePrice + route.distance * tariff.pricePerKm
                );
            }
        } else if (mode === 'DELIVERY') {
            tariff = await this.prisma.tariffDelivery.findFirst({
                where: { isActive: true },
                orderBy: { basePrice: 'asc' },
            });
            if (tariff) {
                let deliveryPrice = Math.max(
                    tariff.minPrice,
                    tariff.basePrice + route.distance * tariff.pricePerKm
                );
                if (dto.doorToDoor) {
                    deliveryPrice += tariff.doorToDoorFee;
                }
                price = deliveryPrice;
            }
        }

        return { distance: route.distance, duration: route.duration, price: this.roundRidePrice(price), tariff, cityId };
    }

    private roundRidePrice(price: number) {
        if (!Number.isFinite(price) || price <= 0) return 0;
        const step = 50;
        return Math.ceil(price / step) * step;
    }

    async getMyOrders(userId: string) {
        return this.prisma.order.findMany({
            where: { passengerId: userId },
            orderBy: { createdAt: 'desc' },
            include: {
                driver: {
                    include: {
                        user: { select: clientUserSelect },
                        rating: true,
                        online: true,
                    },
                },
                offers: {
                    orderBy: { createdAt: 'desc' },
                    include: {
                        driver: {
                            include: {
                                user: { select: clientUserSelect },
                                rating: true,
                            },
                        },
                    },
                },
            },
        });
    }

    async getOrder(orderId: string, actor?: { userId: string; role?: string }) {
        const order = await this.prisma.order.findUnique({
            where: { id: orderId },
            include: {
                passenger: { select: clientUserSelect },
                driver: {
                    include: {
                        user: { select: clientUserSelect },
                        rating: true,
                        online: true,
                    },
                },
                offers: {
                    orderBy: { createdAt: 'desc' },
                    include: {
                        driver: {
                            include: {
                                user: { select: clientUserSelect },
                                rating: true,
                            },
                        },
                    },
                },
            },
        });
        if (!order) throw new NotFoundException('Order not found');
        const actorRole = (actor?.role || '').toUpperCase();
        const isAdmin = actorRole === 'ADMIN';
        const isPassengerOwner = actor?.userId && order.passengerId === actor.userId;
        const isAssignedDriver = actor?.userId && order.driver?.userId === actor.userId;
        const isOfferDriver = actorRole === 'DRIVER' && actor?.userId && (order.offers || []).some(
            (offer: any) => offer.driver?.userId === actor.userId
        );
        if (!isAdmin && !isPassengerOwner && !isAssignedDriver && !isOfferDriver) {
            throw new ForbiddenException('Access denied to this order');
        }
        return order;
    }

    async getOrderChat(orderId: string, actor: { userId: string; role?: string }) {
        await this.requireOrderParticipant(orderId, actor);
        return (this.prisma as any).orderChatMessage.findMany({
            where: { orderId },
            orderBy: { createdAt: 'asc' },
            take: 200,
            include: {
                sender: {
                    select: {
                        publicId: true,
                        name: true,
                        role: true,
                    },
                },
            },
        });
    }

    async sendOrderChatMessage(
        orderId: string,
        actor: { userId: string; role?: string },
        text: string,
    ) {
        const order = await this.requireOrderParticipant(orderId, actor);
        if (!this.isChatWritableStatus(order.status)) {
            throw new BadRequestException('Чат закрыт для этого заказа');
        }
        const normalized = (text || '').trim();
        if (!normalized) {
            throw new BadRequestException('Введите сообщение');
        }
        if (normalized.length > 1000) {
            throw new BadRequestException('Сообщение слишком длинное');
        }
        return (this.prisma as any).orderChatMessage.create({
            data: {
                orderId,
                senderId: actor.userId,
                text: normalized,
            },
            include: {
                sender: {
                    select: {
                        publicId: true,
                        name: true,
                        role: true,
                    },
                },
            },
        });
    }

    async createOrderOffer(
        orderId: string,
        driverUserId: string,
        input: { price: number; comment?: string | null },
    ) {
        const profile = await this.prisma.driverProfile.findUnique({
            where: { userId: driverUserId },
            include: { user: { select: clientUserSelect }, rating: true },
        });
        if (!profile) throw new NotFoundException('Профиль водителя не найден');
        if (!Number.isFinite(input.price) || input.price <= 0) {
            throw new BadRequestException('Укажите цену предложения');
        }
        const offerPrice = this.roundRidePrice(input.price);

        const order = await this.prisma.order.findUnique({ where: { id: orderId } });
        if (!order || order.requestType !== 'CITY_AUCTION' || order.status !== 'SEARCHING_DRIVER') {
            throw new BadRequestException('Аукционная заявка недоступна');
        }

        const offer = await (this.prisma as any).orderOffer.upsert({
            where: {
                orderId_driverId: {
                    orderId,
                    driverId: profile.id,
                },
            },
            update: {
                price: offerPrice,
                comment: input.comment?.trim() || null,
                status: 'PENDING',
            },
            create: {
                orderId,
                driverId: profile.id,
                price: offerPrice,
                comment: input.comment?.trim() || null,
                status: 'PENDING',
            },
            include: {
                driver: {
                    include: {
                        user: { select: clientUserSelect },
                        rating: true,
                    },
                },
            },
        });

        this.realtimeService.publish({
            type: 'order.offer.created',
            entity: 'order',
            entityId: orderId,
            at: new Date().toISOString(),
            payload: { orderId, offerId: offer.id, driverId: profile.id },
        });
        return offer;
    }

    async acceptOrderOffer(offerId: string, passengerUserId: string) {
        const offer = await (this.prisma as any).orderOffer.findUnique({
            where: { id: offerId },
            include: { order: true, driver: true },
        });
        if (!offer || offer.order.passengerId !== passengerUserId) {
            throw new NotFoundException('Предложение не найдено');
        }
        if (offer.order.status !== 'SEARCHING_DRIVER' || offer.status !== 'PENDING') {
            throw new BadRequestException('Предложение уже недоступно');
        }
        const settings = await this.prisma.appSettings.findMany({
            where: { key: { in: ['orderCommissionPercent'] } },
        });
        const commissionPercent = parseFloat(
            settings.find((s) => s.key === 'orderCommissionPercent')?.value || '10'
        );
        const commissionAmount = offer.price > 0 ? (offer.price * commissionPercent) / 100 : 0;

        const updated = await this.prisma.$transaction(async (tx) => {
            await (tx as any).orderOffer.update({
                where: { id: offerId },
                data: { status: 'ACCEPTED' },
            });
            await (tx as any).orderOffer.updateMany({
                where: { orderId: offer.orderId, id: { not: offerId }, status: 'PENDING' },
                data: { status: 'REJECTED' },
            });
            return tx.order.update({
                where: { id: offer.orderId },
                data: {
                    driverId: offer.driverId,
                    selectedOfferId: offerId,
                    price: offer.price,
                    priceSource: 'DRIVER_OFFER',
                    commissionAmount,
                    status: 'DRIVER_EN_ROUTE',
                },
                include: {
                    driver: {
                        include: {
                            user: { select: clientUserSelect },
                            rating: true,
                            online: true,
                        },
                    },
                    offers: {
                        include: {
                            driver: {
                                include: {
                                    user: { select: clientUserSelect },
                                    rating: true,
                                },
                            },
                        },
                    },
                },
            });
        });

        await this.recordRideEventSafe({
            orderId: offer.orderId,
            fromStatus: offer.order.status,
            toStatus: 'DRIVER_EN_ROUTE',
            actorUserId: passengerUserId,
            actorRole: 'PASSENGER',
            source: 'PASSENGER_APP',
            reason: 'Passenger accepted city auction offer',
            payload: { offerId, driverId: offer.driverId, price: offer.price },
        });
        this.realtimeService.publish({
            type: 'order.offer.accepted',
            entity: 'order',
            entityId: offer.orderId,
            at: new Date().toISOString(),
            payload: { orderId: offer.orderId, offerId, driverId: offer.driverId },
        });
        await this.pushService.sendOrderStatusToPassenger(offer.orderId, 'DRIVER_EN_ROUTE');
        return updated;
    }

    async rejectOrderOffer(offerId: string, passengerUserId: string) {
        const offer = await (this.prisma as any).orderOffer.findUnique({
            where: { id: offerId },
            include: { order: true },
        });
        if (!offer || offer.order.passengerId !== passengerUserId) {
            throw new NotFoundException('Предложение не найдено');
        }
        const updated = await (this.prisma as any).orderOffer.update({
            where: { id: offerId },
            data: { status: 'REJECTED' },
        });
        this.realtimeService.publish({
            type: 'order.offer.rejected',
            entity: 'order',
            entityId: offer.orderId,
            at: new Date().toISOString(),
            payload: { orderId: offer.orderId, offerId, driverId: offer.driverId },
        });
        return updated;
    }

    private async requireOrderParticipant(orderId: string, actor?: { userId: string; role?: string }) {
        const order = await this.prisma.order.findUnique({
            where: { id: orderId },
            include: {
                driver: { select: { userId: true } },
            },
        });
        if (!order) throw new NotFoundException('Заказ не найден');
        const actorRole = (actor?.role || '').toUpperCase();
        const isAdmin = actorRole === 'ADMIN';
        const isPassengerOwner = actor?.userId && order.passengerId === actor.userId;
        const isAssignedDriver = actor?.userId && order.driver?.userId === actor.userId;
        if (!isAdmin && !isPassengerOwner && !isAssignedDriver) {
            throw new ForbiddenException('Нет доступа к чату этого заказа');
        }
        return order;
    }

    private isChatWritableStatus(status: string): boolean {
        return new Set([
            'DRIVER_ASSIGNED',
            'DRIVER_EN_ROUTE',
            'DRIVER_ARRIVED',
            'IN_PROGRESS',
        ]).has((status || '').toUpperCase());
    }

    async cancelOrder(orderId: string, userId: string) {
        const order = await this.prisma.order.findUnique({
            where: { id: orderId },
        });

        if (!order) throw new NotFoundException('Order not found');
        if (order.passengerId !== userId) throw new BadRequestException('Not your order');
        if (['COMPLETED', 'CANCELLED'].includes(order.status)) {
            throw new BadRequestException('Order already completed or cancelled');
        }

        const updated = await this.prisma.order.update({
            where: { id: orderId },
            data: { status: 'CANCELLED' },
        });
        await this.recordRideEventSafe({
            orderId: order.id,
            fromStatus: order.status,
            toStatus: 'CANCELLED',
            actorUserId: userId,
            actorRole: 'PASSENGER',
            source: 'PASSENGER_APP',
            reason: 'Passenger cancelled order',
        });
        this.realtimeService.publish({
            type: 'order.status.changed',
            entity: 'order',
            entityId: order.id,
            at: new Date().toISOString(),
            payload: {
                fromStatus: order.status,
                toStatus: 'CANCELLED',
                actorUserId: userId,
                actorRole: 'PASSENGER',
            },
        });
        await this.pushService.sendOrderStatusToPassenger(order.id, 'CANCELLED');
        return updated;
    }

    async updateOrderStatus(orderId: string, status: string, actor?: { userId: string; role?: string }) {
        const order = await this.prisma.order.findUnique({
            where: { id: orderId },
            include: {
                passenger: {
                    select: {
                        id: true,
                        referredBy: true,
                    },
                },
                driver: {
                    select: {
                        id: true,
                        userId: true,
                        user: {
                            select: {
                                referredBy: true,
                            },
                        },
                    },
                },
            },
        });
        if (!order) throw new NotFoundException('Order not found');

        const targetStatus = (status || '').toUpperCase();
        if (!this.isKnownOrderStatus(targetStatus)) {
            throw new BadRequestException(`Unsupported status: ${targetStatus}`);
        }
        const actorRole = (actor?.role || '').toUpperCase();
        const isAdmin = actorRole === 'ADMIN';
        if (!isAdmin) {
            if (!actor?.userId) {
                throw new ForbiddenException('Actor context is required');
            }
            const actorDriverProfile = await this.prisma.driverProfile.findUnique({
                where: { userId: actor.userId },
                select: { id: true },
            });
            const isAssignedDriver =
                order.driver?.userId === actor.userId ||
                order.driver?.id === actor.userId ||
                (!!actorDriverProfile?.id && order.driver?.id === actorDriverProfile.id);
            if (!order.driver || !isAssignedDriver) {
                throw new ForbiddenException('Only assigned driver can update this order');
            }
            const allowedDriverStatuses = new Set(['DRIVER_ARRIVED', 'IN_PROGRESS', 'COMPLETED']);
            if (!allowedDriverStatuses.has(targetStatus)) {
                throw new ForbiddenException('Driver cannot set this status');
            }
            this.assertDriverTransition(order.status, targetStatus);
        }

        const updateData: any = { status: targetStatus };
        if (targetStatus === 'COMPLETED') {
            updateData.completedAt = new Date();
        }

        const updatedOrder = await this.prisma.order.update({
            where: { id: orderId },
            data: updateData,
        });
        await this.recordRideEventSafe({
            orderId: order.id,
            fromStatus: order.status,
            toStatus: targetStatus,
            actorUserId: actor?.userId,
            actorRole: actorRole || null,
            source: isAdmin ? 'ADMIN_PANEL' : 'DRIVER_APP',
            reason: isAdmin ? 'Manual admin status update' : 'Driver status update',
        });
        this.realtimeService.publish({
            type: 'order.status.changed',
            entity: 'order',
            entityId: order.id,
            at: new Date().toISOString(),
            payload: {
                fromStatus: order.status,
                toStatus: targetStatus,
                actorUserId: actor?.userId ?? null,
                actorRole: actorRole || null,
            },
        });
        await this.pushService.sendOrderStatusToPassenger(order.id, targetStatus);

        // Referral bonus is paid from service commission for both sides:
        // inviter of passenger and inviter of driver.
        if (targetStatus === 'COMPLETED' && order.status !== 'COMPLETED') {
            await this.applyDriverOrderCommissionDebit(order);
            await this.applyReferralCommissionBonuses(order);
        }

        return updatedOrder;
    }

    private isKnownOrderStatus(status: string): boolean {
        return new Set([
            'CREATED',
            'SEARCHING_DRIVER',
            'DRIVER_ASSIGNED',
            'DRIVER_EN_ROUTE',
            'DRIVER_ARRIVED',
            'IN_PROGRESS',
            'COMPLETED',
            'CANCELLED',
        ]).has(status);
    }

    private assertDriverTransition(current: string, target: string) {
        const from = (current || '').toUpperCase();
        if (
            target === 'DRIVER_ARRIVED' &&
            !['ACCEPTED', 'DRIVER_ASSIGNED', 'DRIVER_EN_ROUTE'].includes(from)
        ) {
            throw new BadRequestException('Invalid status transition to DRIVER_ARRIVED');
        }
        if (target === 'IN_PROGRESS' && from !== 'DRIVER_ARRIVED') {
            throw new BadRequestException('Invalid status transition to IN_PROGRESS');
        }
        if (target === 'COMPLETED' && from !== 'IN_PROGRESS') {
            throw new BadRequestException('Invalid status transition to COMPLETED');
        }
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
            // Keep order flow stable even before ride_events migration is applied.
        }
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

    private async applyDriverOrderCommissionDebit(order: any) {
        const driverUserId = order.driver?.userId;
        const driverId = order.driver?.id;
        if (!driverUserId) return;

        const driverUser = await this.prisma.user.findUnique({
            where: { id: driverUserId },
            select: { phone: true },
        });
        if (!this.isKazakhstanPhone(driverUser?.phone)) {
            if (typeof order.commissionAmount === 'number' && order.commissionAmount > 0) {
                await this.prisma.order.update({
                    where: { id: order.id },
                    data: { commissionAmount: 0 },
                }).catch(() => null);
            }
            return;
        }

        const settings = await this.prisma.appSettings.findMany({
            where: { key: { in: ['orderCommissionPercent'] } },
        });
        const orderCommissionPercent = parseFloat(
            settings.find((s) => s.key === 'orderCommissionPercent')?.value || '10'
        );
        const commissionAmount =
            typeof order.commissionAmount === 'number' && order.commissionAmount > 0
                ? order.commissionAmount
                : ((order.price || 0) * orderCommissionPercent) / 100;
        if (!Number.isFinite(commissionAmount) || commissionAmount <= 0) return;

        const idempotencyKey = `order-commission:${order.id}:driver:${driverUserId}`;
        let balanceAfterDebit: number | null = null;
        await this.prisma.$transaction(async (tx) => {
            const existing = await (tx as any).walletTransaction.findFirst({
                where: { idempotencyKey },
                select: { id: true },
            });
            if (existing) return;

            const wallet = await tx.wallet.findUnique({
                where: { userId: driverUserId },
                select: { id: true },
            });
            if (!wallet) return;

            if (!(typeof order.commissionAmount === 'number') || order.commissionAmount <= 0) {
                await tx.order.update({
                    where: { id: order.id },
                    data: { commissionAmount },
                });
            }
            const updatedWallet = await tx.wallet.update({
                where: { userId: driverUserId },
                data: { money: { decrement: commissionAmount } },
                select: { money: true },
            });
            balanceAfterDebit = updatedWallet.money;
            await (tx as any).walletTransaction.create({
                data: {
                    walletId: wallet.id,
                    type: 'ORDER_COMMISSION_DEBIT',
                    direction: 'DEBIT',
                    balanceSource: 'MONEY',
                    amount: commissionAmount,
                    actorUserId: driverUserId,
                    orderId: order.id,
                    idempotencyKey,
                    note: `Комиссия сервиса за выполненный заказ ${order.id}`,
                },
            });
        });
        await this.disableDriverOnlineIfBalanceBelowMinimum(
            driverUserId,
            driverId,
            balanceAfterDebit,
        );
    }

    private parsePositiveNumber(value: string | undefined | null, fallback: number): number {
        const parsed = parseFloat(value || '');
        return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
    }

    private async getDriverMinOnlineBalance(): Promise<number> {
        const setting = await this.prisma.appSettings.findUnique({
            where: { key: 'driverMinOnlineBalance' },
        });
        return this.parsePositiveNumber(setting?.value, 100);
    }

    private async disableDriverOnlineIfBalanceBelowMinimum(
        driverUserId: string,
        driverId?: string | null,
        knownBalance?: number | null,
    ) {
        if (!driverId) return;
        const minBalance = await this.getDriverMinOnlineBalance();
        if (minBalance <= 0) return;

        const balance = knownBalance ??
            (await this.prisma.wallet.findUnique({
                where: { userId: driverUserId },
                select: { money: true },
            }))?.money ??
            0;
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
        await this.pushService.sendToUser(driverUserId, {
            title: 'Пополните баланс',
            body: `Баланс меньше ${minBalance} ₸. Вы сняты с линии и не будете получать заказы.`,
            data: {
                type: 'driver_low_balance',
                balance,
                minBalance,
            },
        });
    }

    private async applyReferralCommissionBonuses(order: any) {
        const settings = await this.prisma.appSettings.findMany({
            where: {
                key: {
                    in: [
                        'referralCommissionPercent',
                        'referralPercent',
                        'orderCommissionPercent',
                    ],
                },
            },
        });
        const referralCommissionPercent = parseFloat(
            settings.find((s) => s.key === 'referralCommissionPercent')?.value || '25'
        );
        const orderCommissionPercent = parseFloat(
            settings.find((s) => s.key === 'orderCommissionPercent')?.value || '10'
        );

        const commissionAmount =
            typeof order.commissionAmount === 'number' && order.commissionAmount > 0
                ? order.commissionAmount
                : ((order.price || 0) * orderCommissionPercent) / 100;
        if (commissionAmount <= 0 || referralCommissionPercent <= 0) return;

        const bonusAmount = (commissionAmount * referralCommissionPercent) / 100;
        if (bonusAmount <= 0) return;

        const referralCredits = [
            {
                side: 'PASSENGER',
                code: this.normalizeReferralCode(order.passenger?.referredBy),
            },
            {
                side: 'DRIVER',
                code: this.normalizeReferralCode(order.driver?.user?.referredBy),
            },
        ].filter((item) => item.code);
        if (referralCredits.length === 0) return;

        const referrers = await this.prisma.user.findMany({
            where: { refCode: { in: referralCredits.map((item) => item.code!) } },
            select: { id: true, refCode: true },
        });
        const referrerByCode = new Map(
            referrers.map((referrer) => [
                this.normalizeReferralCode(referrer.refCode),
                referrer,
            ])
        );

        await Promise.all(
            referralCredits.map(async (credit) => {
                const referrer = referrerByCode.get(credit.code!);
                if (!referrer) return;
                const idempotencyKey = `referral:${order.id}:${credit.side}`;
                if (await this.walletTransactionExists(idempotencyKey)) return;

                const wallet = await this.prisma.wallet.findUnique({
                    where: { userId: referrer.id },
                    select: {
                        id: true,
                    },
                });
                if (!wallet) return;
                await this.prisma.wallet.update({
                    where: { userId: referrer.id },
                    data: { bonus: { increment: bonusAmount } },
                });
                await this.recordWalletTransactionSafe({
                    walletId: wallet.id,
                    type: 'REFERRAL_ORDER_BONUS',
                    direction: 'CREDIT',
                    balanceSource: 'BONUS',
                    amount: bonusAmount,
                    actorUserId: referrer.id,
                    orderId: order.id,
                    idempotencyKey,
                    note: `Referral bonus for ${credit.side.toLowerCase()} side of completed order ${order.id}`,
                });
            })
        );
    }

    private normalizeReferralCode(raw?: string | null): string | null {
        const normalized = (raw || '').trim().toUpperCase();
        return normalized.length > 0 ? normalized : null;
    }

    private async recordWalletTransactionSafe(input: {
        walletId: string;
        type: string;
        direction: 'DEBIT' | 'CREDIT';
        balanceSource: 'MONEY' | 'BONUS';
        amount: number;
        note?: string;
        actorUserId?: string;
        orderId?: string;
        idempotencyKey?: string;
    }) {
        try {
            await (this.prisma as any).walletTransaction.create({
                data: {
                    walletId: input.walletId,
                    type: input.type,
                    direction: input.direction,
                    balanceSource: input.balanceSource,
                    amount: input.amount,
                    note: input.note ?? null,
                    actorUserId: input.actorUserId ?? null,
                    orderId: input.orderId ?? null,
                    idempotencyKey: input.idempotencyKey ?? null,
                },
            });
        } catch (_) {
            // Keep order completion stable if wallet transactions migration is absent.
        }
    }

    private async walletTransactionExists(idempotencyKey: string): Promise<boolean> {
        try {
            const existing = await (this.prisma as any).walletTransaction.findFirst({
                where: { idempotencyKey },
                select: { id: true },
            });
            return !!existing;
        } catch (_) {
            return false;
        }
    }

    async rateOrder(orderId: string, userId: string, rating: number, ratedByDriver: boolean) {
        const order = await this.prisma.order.findUnique({
            where: { id: orderId },
            include: {
                driver: {
                    select: {
                        id: true,
                        userId: true,
                    },
                },
            },
        });

        if (!order) throw new NotFoundException('Order not found');
        if (order.status !== 'COMPLETED') {
            throw new BadRequestException('Order must be completed before rating');
        }

        if (ratedByDriver) {
            if (!order.driver || order.driver.userId !== userId) {
                throw new BadRequestException('Not your order');
            }
            if (order.passengerRating != null) {
                throw new BadRequestException('Passenger rating already submitted');
            }
            await this.prisma.order.update({
                where: { id: orderId },
                data: { passengerRating: rating },
            });
        } else {
            if (order.passengerId !== userId) {
                throw new BadRequestException('Not your order');
            }
            if (!order.driverId) {
                throw new BadRequestException('Driver not assigned for this order');
            }
            if (order.driverRating != null) {
                throw new BadRequestException('Driver rating already submitted');
            }
            await this.prisma.order.update({
                where: { id: orderId },
                data: { driverRating: rating },
            });
            await this.updateDriverRating(order.driverId!, rating);
        }

        return { success: true };
    }

    private async updateDriverRating(driverId: string, rating: number) {
        const driverRating = await this.prisma.driverRating.findUnique({
            where: { driverId },
        });

        if (driverRating) {
            const newCount = driverRating.ratingCount + 1;
            const newAvg = (driverRating.ratingAvg * driverRating.ratingCount + rating) / newCount;
            await this.prisma.driverRating.update({
                where: { driverId },
                data: { ratingAvg: newAvg, ratingCount: newCount },
            });
        } else {
            await this.prisma.driverRating.create({
                data: { driverId, ratingAvg: rating, ratingCount: 1 },
            });
        }
    }
}
