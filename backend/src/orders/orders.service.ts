import { CardPaymentsService } from '../payments/card-payments.service';
import { startTripVerification, finishTripVerification } from '../common/trip-verification';
import { consumeLockedBonus } from '../common/currency';
import { ratingReviewHint, reviseDriverRating } from '../common/driver-rating-review';
import { creditDriverDailyBonus } from '../common/driver-daily-bonus';
import { applyDriverActivity } from '../common/driver-activity';
import { DRIVER_ACTIVITY_RULES } from '../common/driver-performance';
import { Prisma } from '@prisma/client';
import { creditRideReferrals } from '../common/referral-bonus';
import { moneyField, bonusField } from '../common/currency';
import { requireNoActivePassengerOrder } from '../common/active-passenger-order';
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
        private cardPayments: CardPaymentsService,
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
        if (normalized === 'BONUS') return 'BONUSES';
        if (['CASH', 'CARD', 'CARD_TRANSFER', 'BONUSES'].includes(normalized)) {
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
        const tariffs = cityId ? await this.prisma.tariffCity.findMany({
            where: { cityId, isActive: true },
            orderBy: { basePrice: 'asc' },
        }) : [];
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
            currency: preview.currency,
            cityId: preview.cityId,
        };
    }

    async getActivePassengerOrder(passengerId: string) {
        const where = { passengerId, status: { notIn: ['COMPLETED', 'CANCELLED'] } };
        const order = await this.prisma.order.findFirst({
            where: { passengerId, status: { notIn: ['COMPLETED', 'CANCELLED'] } },
            orderBy: { createdAt: 'desc' },
            select: { id: true, status: true },
        });
        if (order) return { ...order, type: 'CITY' };
        const request = await this.prisma.intercityRequest.findFirst({
            where, orderBy: { createdAt: 'desc' }, select: { id: true, status: true },
        });
        return request ? { ...request, type: 'INTERCITY' } : null;
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
        const vehicleClass = mode === 'CITY'
            ? this.normalizeVehicleClass(dto.vehicleClass || 'ECONOMY')
            : null;
        if (isCityAuction && (!Number.isFinite(dto.desiredPrice) || dto.desiredPrice! <= 0)) {
            throw new BadRequestException('Укажите желаемую цену поездки');
        }
        const useBonus = !isCityAuction && (paymentMethod === 'BONUSES' ? true : dto.useBonus === true);
        if (mode === 'DELIVERY' && paymentMethod === 'BONUSES') {
            throw new BadRequestException('Bonuses are not available for delivery');
        }

        const preview = isCityAuction
            ? await this.cityAuctionDraftToOrder(dto)
            : await this.previewOrderDtoToOrder(dto);
        if (!isCityAuction && (!Number.isFinite(preview.price) || preview.price <= 0)) {
            throw new BadRequestException('Unable to calculate order price');
        }
        const paymentCardId = paymentMethod === 'CARD' ? await this.cardPayments.cardForOrder(userId, preview.currency) : null;
        const settings = await this.prisma.appSettings.findMany({
            where: { key: { in: ['orderCommissionPercent'] } },
        });
        const commissionPercent = parseFloat(
            settings.find((s) => s.key === 'orderCommissionPercent')?.value || '10'
        );

        let bonusUsedAmount = 0;
        if (useBonus) {
            const wallet = await this.prisma.wallet.findUnique({ where: { userId } });
            if (!wallet || wallet[bonusField(preview.currency)] < preview.price) {
                throw new BadRequestException('Insufficient bonus balance');
            }
            bonusUsedAmount = preview.price;
        }

        const order = await this.prisma.$transaction(async (tx) => {
            await requireNoActivePassengerOrder(tx, userId);
            let userWalletId: string | null = null;
            if (bonusUsedAmount > 0) {
                const wallet = await tx.wallet.findUnique({
                    where: { userId },
                    select: { id: true },
                });
                userWalletId = wallet?.id ?? null;
                const debit = await tx.wallet.updateMany({
                    where: { userId, [bonusField(preview.currency)]: { gte: bonusUsedAmount } },
                    data: { [bonusField(preview.currency)]: { decrement: bonusUsedAmount } },
                });
                if (debit.count !== 1) throw new BadRequestException('Insufficient bonus balance');
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
                    price: isCityAuction ? dto.desiredPrice! : preview.price,
                    currency: preview.currency,
                    priceSource: isCityAuction ? 'DRIVER_OFFER' : 'SYSTEM',
                    paymentMethod,
                    paymentCardId,
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
                        currency: preview.currency,
                        orderId: createdOrder.id,
                        actorUserId: userId,
                        note: 'Bonus used for order payment',
                    },
                }).catch(() => null);
            }
            return createdOrder;
        });

        // Auto-dispatch for CITY-like modes
        if ((mode === 'CITY' || mode === 'CARGO' || mode === 'DELIVERY')) {
            await this.autoDispatchService.assignCityOrder(order.id).catch(() => null);
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
        const route = await this.geoService.getRoute(dto.fromLat, dto.fromLng, dto.toLat, dto.toLng);
        return {
            distance: route.distance,
            duration: route.duration,
            price: 0,
            tariff: null,
            cityId: geoResult?.cityId ?? null,
            currency: geoResult.currency,
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
            if (!tariff) throw new BadRequestException('City tariff is not configured');
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

        return { distance: route.distance, duration: route.duration, price: this.roundRidePrice(price), tariff, cityId, currency: geoResult.currency };
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
        const isOfferDriver = actor?.userId && (order.offers || []).some(
            (offer: any) => offer.driver?.userId === actor.userId
        );
        if (!isAdmin && !isPassengerOwner && !isAssignedDriver && !isOfferDriver) {
            throw new ForbiddenException('Access denied to this order');
        }
        return { ...order, cardPayment: this.cardPayments ? await this.cardPayments.state('CITY',order.id) : null };
    }

    async getOrderChat(orderId: string, actor: { userId: string; role?: string }) {
        const order = await this.requireOrderParticipant(orderId, actor);
        const messages = await (this.prisma as any).orderChatMessage.findMany({
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
        return messages.map((message: any) => this.chatMessageForViewer(message, order, actor.userId));
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
        const message = await (this.prisma as any).orderChatMessage.create({
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
        return this.chatMessageForViewer(message, order, actor.userId);
    }

    private chatMessageForViewer(message: any, order: any, userId: string) {
        return {
            ...message,
            isMine: message.senderId === userId,
            participantRole: message.senderId === order.passengerId ? 'PASSENGER'
                : message.senderId === order.driver?.userId ? 'DRIVER' : 'SUPPORT',
        };
    }

    async increaseAuctionPrice(orderId: string, passengerId: string) {
        const updated = await this.prisma.$transaction(async tx => {
            await tx.$executeRaw`SELECT pg_advisory_xact_lock(741302091)`;
            const order = await tx.order.findUnique({where: {id: orderId}});
            if (!order || order.passengerId !== passengerId) throw new ForbiddenException('Нет доступа к заказу');
            if (order.requestType !== 'CITY_AUCTION' || order.status !== 'SEARCHING_DRIVER' || order.driverId || order.price + 100 > 10000000) throw new BadRequestException('Цена этого заказа уже не может быть изменена');
            await tx.orderOffer.updateMany({where: {orderId, status: 'PENDING'}, data: {status: 'EXPIRED'}});
            await tx.orderAuctionInvitation.deleteMany({where: {orderId}});
            return tx.order.update({where: {id: orderId}, data: {price: {increment: 100}, dispatchRetryAt: null}});
        });
        this.realtimeService.publish({type: 'order.price.updated', entity: 'order', entityId: orderId, at: new Date().toISOString(), payload: {orderId, price: updated.price}});
        await this.autoDispatchService.assignCityOrder(orderId).catch(() => null);
        return updated;
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
        if (!Number.isFinite(input.price) || input.price < 1 || input.price > 10000000) {
            throw new BadRequestException('Укажите цену предложения');
        }
        const offerPrice = Math.round(input.price * 100) / 100;

        const order = await this.prisma.order.findUnique({ where: { id: orderId } });
        if (!order || order.passengerId === driverUserId || order.requestType !== 'CITY_AUCTION' || order.status !== 'SEARCHING_DRIVER') {
            throw new BadRequestException('Аукционная заявка недоступна');
        }

        const offer = await this.prisma.$transaction(async (tx) => {
            await tx.$executeRaw`SELECT pg_advisory_xact_lock(741302091)`;
            const now = new Date();
            const online = await tx.driverOnline.findUnique({where: {driverId: profile.id}});
            if (!online?.isOnline || !['ACTIVE','APPROVED'].includes(profile.status)) throw new BadRequestException('Выйдите на линию для отправки предложения');
            const waiting = await tx.orderOffer.findFirst({where: {driverId: profile.id, status: 'PENDING', expiresAt: {gt: now}, order: {status: 'SEARCHING_DRIVER'}}});
            if (waiting) throw new BadRequestException('Дождитесь ответа на предыдущее предложение');
            const current = await tx.order.findUnique({where: {id: orderId}});
            if (current?.status !== 'SEARCHING_DRIVER' || current.driverId) throw new BadRequestException('Заказ уже недоступен');
            const released = await tx.orderAuctionInvitation.updateMany({where: {orderId, driverId: profile.id, status: 'PENDING', expiresAt: {gt: now}}, data: {status: 'PRICE_SENT'}});
            if (released.count !== 1) throw new BadRequestException('Заказ уже недоступен');
            return tx.orderOffer.upsert({
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
                    expiresAt: new Date(Date.now() + 30_000),
                },
                create: {
                    orderId,
                    driverId: profile.id,
                    price: offerPrice,
                    comment: input.comment?.trim() || null,
                    status: 'PENDING',
                    expiresAt: new Date(Date.now() + 30_000),
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
        });

        this.realtimeService.publish({
            type: 'order.offer.created',
            entity: 'order',
            entityId: orderId,
            at: new Date().toISOString(),
            payload: { orderId, offerId: offer.id, driverId: profile.id },
        });
        await this.autoDispatchService.assignCityOrder(orderId).catch(() => null);
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
        if (offer.order.status !== 'SEARCHING_DRIVER' || offer.status !== 'PENDING' || offer.expiresAt <= new Date()) {
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
            await tx.$executeRaw`SELECT pg_advisory_xact_lock(741302091)`;
            const now = new Date();
            const liveOffer = await tx.orderOffer.findFirst({where: {id: offerId, status: 'PENDING', expiresAt: {gt: now}}});
            if (!liveOffer) throw new BadRequestException('Время предложения истекло');
            const activeCity = await tx.order.findFirst({where: {driverId: offer.driverId, status: {in: ['DRIVER_ASSIGNED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'IN_PROGRESS']}}});
            const activeIntercity = await tx.intercityRequest.findFirst({where: {selectedDriverId: offer.driver.userId, status: {in: ['ACCEPTED', 'DRIVER_ASSIGNED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'IN_PROGRESS']}}});
            const online = await tx.driverOnline.findUnique({where: {driverId: offer.driverId}});
            const driver = await tx.driverProfile.findUnique({where: {id: offer.driverId}, include: {serviceStats: true}});
            if (!driver || !['ACTIVE','APPROVED'].includes(driver.status) || (driver.serviceStats?.activityScore ?? 100) <= 0 || (driver.serviceStats?.activityBlockedUntil && driver.serviceStats.activityBlockedUntil > now)) throw new BadRequestException('Водитель уже недоступен');
            if (activeCity || activeIntercity || !online?.isOnline) throw new BadRequestException('Водитель уже недоступен');
            const claimed = await tx.order.updateMany({
                where: { id: offer.orderId, selectedOfferId: null, status: { in: ['CREATED', 'SEARCHING_DRIVER'] } },
                data: { selectedOfferId: offerId },
            });
            if (claimed.count !== 1) throw new BadRequestException('Order already assigned');
            let bonusUsedAmount = offer.order.bonusUsedAmount || 0;
            if (offer.order.paymentMethod === 'BONUSES' && bonusUsedAmount === 0) {
                const field = bonusField(offer.order.currency);
                const debit = await tx.wallet.updateMany({ where: { userId: passengerUserId, [field]: { gte: offer.price } }, data: { [field]: { decrement: offer.price } } });
                if (debit.count !== 1) throw new BadRequestException('Insufficient bonus balance');
                const wallet = await tx.wallet.findUnique({ where: { userId: passengerUserId } });
                await tx.walletTransaction.create({ data: { walletId: wallet!.id, currency: offer.order.currency, type: 'ORDER_BONUS_USED', direction: 'DEBIT', balanceSource: 'BONUS', amount: offer.price, orderId: offer.orderId } });
                bonusUsedAmount = offer.price;
            }
            const acceptedOffer = await tx.orderOffer.updateMany({where: {id: offerId, status: 'PENDING', expiresAt: {gt: new Date()}}, data: {status: 'ACCEPTED'}});
            if (acceptedOffer.count !== 1) throw new BadRequestException('Предложение уже недоступно');
            await (tx as any).orderOffer.updateMany({
                where: { orderId: offer.orderId, id: { not: offerId }, status: 'PENDING' },
                data: { status: 'REJECTED' },
            });
            await tx.orderAuctionInvitation.updateMany({where: {orderId: offer.orderId, status: 'PENDING'}, data: {status: 'CANCELLED'}});
            await applyDriverActivity(tx, offer.driverId, `accept:city:${offer.orderId}:${offer.driverId}`, DRIVER_ACTIVITY_RULES.acceptReward);
            return tx.order.update({
                where: { id: offer.orderId },
                data: {
                    driverId: offer.driverId,
                    dispatchDriverId: null, dispatchExpiresAt: null, dispatchRetryAt: null,
                    selectedOfferId: offerId,
                    bonusUsedAmount,
                    paidWithBonus: bonusUsedAmount > 0,
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
        const changed = await this.prisma.orderOffer.updateMany({where: {id: offerId, status: 'PENDING', expiresAt: {gt: new Date()}}, data: {status: 'REJECTED'}});
        if (changed.count !== 1) throw new BadRequestException('Предложение уже недоступно');
        const updated = await this.prisma.orderOffer.findUnique({where: {id: offerId}});
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

        const updated = await this.prisma.$transaction(async (tx) => {
            const changed = await tx.order.updateMany({ where: { id: orderId, status: { notIn: ['COMPLETED', 'CANCELLED'] } }, data: { status: 'CANCELLED' } });
            if (changed.count !== 1) throw new BadRequestException('Order already completed or cancelled');
            await tx.tripVerification.updateMany({where:{id:`CITY:${orderId}`,status:'PENDING'},data:{status:'CANCELLED'}});
            if (order.bonusUsedAmount > 0) {
                const wallet = await tx.wallet.update({ where: { userId }, data: { [bonusField(order.currency)]: { increment: order.bonusUsedAmount } } });
                await tx.walletTransaction.create({ data: { walletId: wallet.id, currency: order.currency, type: 'ORDER_BONUS_REFUND', direction: 'CREDIT', balanceSource: 'BONUS', amount: order.bonusUsedAmount, orderId } });
            }
            return tx.order.findUniqueOrThrow({ where: { id: orderId } });
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

        const updatedOrder = await this.prisma.$transaction(async tx => {
            const changed = await tx.order.updateMany({ where: { id: orderId, status: order.status }, data: updateData });
            if (changed.count !== 1) throw new BadRequestException('Order status changed. Refresh the order.');
            if (targetStatus === 'IN_PROGRESS' && order.driver) {
                await startTripVerification(tx, 'CITY', order, order.driver.id, order.driver.userId);
                if (order.paymentMethod === 'CARD') await this.cardPayments.schedule(tx, 'CITY', order, order.driver.userId);
            }
            if (targetStatus === 'COMPLETED') {
                const verification = order.driver ? await finishTripVerification(tx, 'CITY', order, order.driver.id, order.driver.userId, updateData.completedAt) : 'REVIEW';
                if (verification === 'VERIFIED') await this.applyReferralCommissionBonuses(order, tx);
                if (order.driverId) {
                    const profile = await tx.driverProfile.findUnique({ where: { id: order.driverId } });
                    if (profile) await creditDriverDailyBonus(tx, profile.id, profile.userId, order.currency, updateData.completedAt);
                }
            }
            return tx.order.findUniqueOrThrow({ where: { id: orderId } });
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
            if (order.paymentMethod === 'CARD') await this.cardPayments.settleCompletedTrip('CITY', order.id);
            await this.applyDriverOrderCommissionDebit(order);
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
        if (order.currency !== 'RUB' && !this.isKazakhstanPhone(driverUser?.phone)) {
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
            await tx.wallet.updateMany({ where: { userId: driverUserId }, data: { [moneyField(order.currency)]: { increment: 0 } } });
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
                data: { [moneyField(order.currency)]: { decrement: commissionAmount } },
                select: { money: true, moneyRub: true },
            });
            await consumeLockedBonus(tx, wallet.id, order.currency, commissionAmount);
            balanceAfterDebit = updatedWallet[moneyField(order.currency)];
            await (tx as any).walletTransaction.create({
                data: {
                    walletId: wallet.id,
                    type: 'ORDER_COMMISSION_DEBIT',
                    direction: 'DEBIT',
                    balanceSource: 'MONEY',
                    amount: commissionAmount,
                    currency: order.currency,
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
            order.currency,
        );
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

    private async disableDriverOnlineIfBalanceBelowMinimum(
        driverUserId: string,
        driverId?: string | null,
        knownBalance?: number | null,
        currency = 'KZT',
    ) {
        if (!driverId) return;
        const minBalance = await this.getDriverMinOnlineBalance(currency);
        if (minBalance <= 0) return;

        const balance = knownBalance ??
            (await this.prisma.wallet.findUnique({
                where: { userId: driverUserId },
                select: { money: true, moneyRub: true },
            }))?.[moneyField(currency)] ??
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

    private async applyReferralCommissionBonuses(order: any, tx?: Prisma.TransactionClient) {
        const setting = await (tx ?? this.prisma).appSettings.findUnique({ where: { key: 'orderCommissionPercent' } });
        const percent = Number(setting?.value ?? '10');
        const commissionAmount = typeof order.commissionAmount === 'number'
            ? order.commissionAmount : ((order.price || 0) * percent) / 100;
        const ride = {
            id: order.id, currency: order.currency ?? 'KZT', commissionAmount,
            passengerId: order.passengerId ?? order.passenger?.id,
            driverUserId: order.driver?.userId ?? order.driver?.user?.id,
        };
        if (tx) await creditRideReferrals(tx, ride);
        else await this.prisma.$transaction(transaction => creditRideReferrals(transaction, ride));
    }


    private async recordWalletTransactionSafe(input: {
        walletId: string;
        type: string;
        direction: 'DEBIT' | 'CREDIT';
        balanceSource: 'MONEY' | 'BONUS';
        currency?: string;
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
                    currency: input.currency ?? 'KZT',
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

    async rateOrder(orderId: string, userId: string, rating: number, ratedByDriver: boolean, reason?: string) {
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
            const low = rating <= 2;
            const explanation = (reason ?? '').trim();
            if (!Number.isInteger(rating) || rating < 1 || rating > 5) throw new BadRequestException('Выберите оценку от 1 до 5');
            if (low && (explanation.length < 10 || explanation.length > 2000)) throw new BadRequestException('Для низкой оценки опишите случившееся: от 10 до 2000 символов');
            await this.prisma.$transaction(async tx => {
                await tx.$executeRaw`SELECT id FROM "DriverProfile" WHERE id = ${order.driverId} FOR UPDATE`;
                const changed = await tx.order.updateMany({where:{id:orderId,driverRating:null},data:{driverRating:rating,driverRatingStatus:low?'PENDING':'COUNTED',driverRatingReason:low?explanation:null}});
                if (!changed.count) throw new BadRequestException('Оценка уже отправлена');
                if (low) {
                    await tx.complaint.create({data:{type:'LOW_DRIVER_RATING',status:'NEW',text:JSON.stringify({rating,reason:explanation,automation:ratingReviewHint(explanation)}),userId,driverId:order.driverId,orderId}});
                } else {
                    await reviseDriverRating(tx,order.driverId!,null,rating);
                }
            });
            this.realtimeService.publish({
                type: 'driver.rating.updated', entity: 'driver', entityId: order.driverId!,
                at: new Date().toISOString(), payload: { driverId: order.driverId!, orderId },
            });
        }

        return { success: true, pendingReview: !ratedByDriver && rating <= 2 };
    }

}
