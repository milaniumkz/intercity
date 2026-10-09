import { CardPaymentsService } from '../payments/card-payments.service';
import { startTripVerification, finishTripVerification } from '../common/trip-verification';
import { consumeLockedBonus } from '../common/currency';
import { creditDriverDailyBonus } from '../common/driver-daily-bonus';
import { applyDriverActivity } from '../common/driver-activity';
import { DRIVER_ACTIVITY_RULES } from '../common/driver-performance';
import { creditRideReferrals } from '../common/referral-bonus';
import { moneyField, bonusField } from '../common/currency';
import { requireNoActivePassengerOrder } from '../common/active-passenger-order';
import { GeoService } from '../geo/geo.service';
import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { PrismaService } from "../prisma.service";
import { normalizeClientDateTime } from "../common/date-time.util";
import { clientUserSelect } from "../common/public-user-select";

@Injectable()
export class IntercityService {
  constructor(private prisma: PrismaService, private geoService: GeoService, private cardPayments: CardPaymentsService) {}

  private normalizePhoneDigits(value?: string | null) {
    let digits = (value || "").replace(/\D/g, "");
    if (digits.length === 11 && digits.startsWith("8")) {
      digits = `7${digits.slice(1)}`;
    }
    return digits;
  }

  private isKazakhstanPhone(value?: string | null) {
    const digits = this.normalizePhoneDigits(value);
    return digits.startsWith("76") || digits.startsWith("77");
  }

  private toRad(value: number) {
    return (value * Math.PI) / 180;
  }

  private haversineKm(
    fromLat?: number | null,
    fromLng?: number | null,
    toLat?: number | null,
    toLng?: number | null,
  ) {
    if (
      fromLat == null ||
      fromLng == null ||
      toLat == null ||
      toLng == null
    ) {
      return 0;
    }
    const radiusKm = 6371;
    const dLat = this.toRad(toLat - fromLat);
    const dLng = this.toRad(toLng - fromLng);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(this.toRad(fromLat)) *
        Math.cos(this.toRad(toLat)) *
        Math.sin(dLng / 2) *
        Math.sin(dLng / 2);
    return radiusKm * (2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)));
  }

  private normalizeRequestType(raw?: string | null) {
    const normalized = (raw || "").trim().toUpperCase();
    if (
      [
        "INTERCITY",
        "CITY_AUCTION",
        "DELIVERY_CITY",
        "DELIVERY_INTERCITY",
        "DELIVERY_RF",
      ].includes(normalized)
    ) {
      return normalized;
    }
    return "INTERCITY";
  }

  private normalizePaymentMethod(raw?: string | null, requestType?: string) {
    const normalizedRaw = (raw || "").trim().toUpperCase();
    const normalized = normalizedRaw === "BONUS" ? "BONUSES" : normalizedRaw;
    if (normalized === "BONUSES" && requestType?.startsWith("DELIVERY")) {
      throw new BadRequestException("Bonuses are not available for delivery");
    }
    if (["CASH", "CARD", "CARD_TRANSFER", "BONUSES"].includes(normalized)) {
      return normalized;
    }
    return "CASH";
  }

  private normalizeLocationSource(raw?: string | null) {
    const normalized = (raw || "").trim().toUpperCase();
    if (["GEOCODED", "MANUAL", "MAP_PIN"].includes(normalized)) {
      return normalized;
    }
    return "GEOCODED";
  }

  private coerceNullableNumber(value: unknown) {
    if (value == null || value === "") return null;
    const parsed =
      typeof value === "number" ? value : Number.parseFloat(String(value));
    return Number.isFinite(parsed) ? parsed : null;
  }

  private coerceNonEmptyString(value: unknown) {
    const text = typeof value === "string" ? value.trim() : "";
    return text.length > 0 ? text : null;
  }

  private requestDisplayRoute(data: {
    requestType: string;
    fromAddressLabel?: string | null;
    toAddressLabel?: string | null;
    fromManualAddress?: string | null;
    toManualAddress?: string | null;
    fromCity?: string | null;
    toCity?: string | null;
  }) {
    const from =
      data.fromManualAddress ||
      data.fromAddressLabel ||
      data.fromCity ||
      "Точка A";
    const to =
      data.toManualAddress || data.toAddressLabel || data.toCity || "Точка B";
    return { from, to };
  }

  async createRequest(
    userId: string,
    data: {
      requestType?: string;
      fromCity?: string;
      toCity?: string;
      fromLat?: number | null;
      fromLng?: number | null;
      toLat?: number | null;
      toLng?: number | null;
      fromAddressLabel?: string;
      toAddressLabel?: string;
      fromManualAddress?: string;
      toManualAddress?: string;
      fromAddressSource?: string;
      toAddressSource?: string;
      paymentMethod?: string;
      comment?: string;
      baggage?: string;
      seats?: number;
      price?: number;
      date: Date | string;
      hasUnconfirmedLocation?: boolean;
      itemDescription?: string;
      itemWeightKg?: number;
      itemDimensions?: string;
      recipientContact?: string;
    },
  ) {
    const requestType = this.normalizeRequestType(data.requestType);
    const requestDate = normalizeClientDateTime(data.date, "date");
    const paymentMethod = this.normalizePaymentMethod(
      data.paymentMethod,
      requestType,
    );
    const fromLat = this.coerceNullableNumber(data.fromLat);
    const fromLng = this.coerceNullableNumber(data.fromLng);
    const toLat = this.coerceNullableNumber(data.toLat);
    const toLng = this.coerceNullableNumber(data.toLng);
    const fromAddressLabel =
      this.coerceNonEmptyString(data.fromAddressLabel) ??
      this.coerceNonEmptyString(data.fromCity);
    const toAddressLabel =
      this.coerceNonEmptyString(data.toAddressLabel) ??
      this.coerceNonEmptyString(data.toCity);
    const fromManualAddress = this.coerceNonEmptyString(data.fromManualAddress);
    const toManualAddress = this.coerceNonEmptyString(data.toManualAddress);
    const fromSource = this.normalizeLocationSource(data.fromAddressSource);
    const toSource = this.normalizeLocationSource(data.toAddressSource);
    const route = this.requestDisplayRoute({
      requestType,
      fromAddressLabel,
      toAddressLabel,
      fromManualAddress,
      toManualAddress,
      fromCity: data.fromCity ?? null,
      toCity: data.toCity ?? null,
    });
    if (!route.from || !route.to) {
      throw new BadRequestException("From and to locations are required");
    }
    if (requestType.startsWith("DELIVERY") && paymentMethod === "BONUSES") {
      throw new BadRequestException("Bonuses are not available for delivery");
    }
    if (
      requestType.startsWith("DELIVERY") &&
      !this.coerceNonEmptyString(data.itemDescription)
    ) {
      throw new BadRequestException("Delivery item description is required");
    }
    const hasUnconfirmedLocation =
      data.hasUnconfirmedLocation === true ||
      fromSource === "MANUAL" ||
      toSource === "MANUAL" ||
      fromLat == null ||
      fromLng == null ||
      toLat == null ||
      toLng == null;
    const seats =
      Number.isFinite(data.seats as number) && (data.seats as number) > 0
        ? Math.max(1, Math.trunc(data.seats as number))
        : 1;
    const price =
      Number.isFinite(data.price as number) && (data.price as number) >= 0
        ? Number(data.price)
        : 0;

    const currency = await this.geoService.departureCurrency(fromLat, fromLng, data.fromCity);
    const paymentCardId = paymentMethod === 'CARD' ? await this.cardPayments.cardForOrder(userId, currency) : null;
    return this.prisma.$transaction(async (tx) => {
      await requireNoActivePassengerOrder(tx, userId);
      return tx.intercityRequest.create({
      data: {
        passengerId: userId,
        currency,
        requestType,
        fromCity: route.from,
        toCity: route.to,
        fromLat,
        fromLng,
        toLat,
        toLng,
        fromAddressLabel,
        toAddressLabel,
        fromManualAddress,
        toManualAddress,
        fromAddressSource: fromSource,
        toAddressSource: toSource,
        paymentMethod,
        paymentCardId,
        comment: this.coerceNonEmptyString(data.comment),
        baggage: this.coerceNonEmptyString(data.baggage),
        seats,
        price,
        date: requestDate,
        hasUnconfirmedLocation,
        itemDescription: this.coerceNonEmptyString(data.itemDescription),
        itemWeightKg: this.coerceNullableNumber(data.itemWeightKg),
        itemDimensions: this.coerceNonEmptyString(data.itemDimensions),
        recipientContact: this.coerceNonEmptyString(data.recipientContact),
        status: "OPEN",
      },
      });
    });
  }

  async getOpenRequests() {
    return this.prisma.intercityRequest.findMany({
      where: { status: "OPEN" },
      include: { offers: true },
      orderBy: [{ date: "asc" }, { createdAt: "desc" }],
    });
  }

  async getMyRequests(passengerId: string) {
    return this.prisma.intercityRequest.findMany({
      where: { passengerId },
      include: {
        offers: true,
      },
      orderBy: { createdAt: "desc" },
    });
  }

  async getRequest(passengerId: string, requestId: string) {
    const request = await this.requireOwnedRequest(passengerId, requestId);

    const offers = await this.prisma.intercityOffer.findMany({
      where: { requestId },
      orderBy: [{ price: "asc" }, { createdAt: "asc" }],
    });

    return {
      ...request,
      cardPayment: this.cardPayments ? await this.cardPayments.state('INTERCITY',request.id) : null,
      offers: await this.enrichOffers(offers),
    };
  }

  async createOffer(
    driverId: string,
    requestId: string,
    data: { price: number; seats?: number; comment?: string },
  ) {
    const request = await this.prisma.intercityRequest.findUnique({
      where: { id: requestId },
    });

    if (!request || request.status !== "OPEN") {
      throw new NotFoundException("Request not found or not open");
    }
    const price = this.roundOfferPrice(Number(data.price));
    const seats = Number(data.seats);
    if (!Number.isFinite(price) || price <= 0) {
      throw new BadRequestException("Offer price must be valid");
    }
    const requestType = this.normalizeRequestType(
      request.requestType?.toString(),
    );
    if (
      requestType === "INTERCITY" &&
      (!Number.isFinite(seats) || seats <= 0)
    ) {
      throw new BadRequestException("Seats must be valid");
    }
    const requestSeats = Math.max(1, Math.trunc(Number(request.seats ?? 1)));
    const normalizedSeats =
      requestType === "INTERCITY"
        ? Math.max(requestSeats, Math.trunc(seats))
        : 1;
    const comment = this.coerceNonEmptyString(data.comment);
    await this.ensureDriverCanHandleRequest(driverId, request);
    if (requestType === "INTERCITY") {
      await this.ensureDriverRouteHasSeats(driverId, request, normalizedSeats);
    }

    const existingOffer = await this.prisma.intercityOffer.findFirst({
      where: {
        requestId,
        driverId,
        status: { in: ["PENDING", "ACCEPTED"] },
      },
    });
    if (existingOffer) {
      return this.prisma.intercityOffer.update({
        where: { id: existingOffer.id },
        data: {
          price,
          seats: normalizedSeats,
          comment,
          status: existingOffer.status === "ACCEPTED" ? "ACCEPTED" : "PENDING",
        },
      });
    }

    return this.prisma.intercityOffer.create({
      data: {
        requestId,
        driverId,
        price,
        seats: normalizedSeats,
        comment,
        status: "PENDING",
      },
    });
  }

  private roundOfferPrice(price: number) {
    if (!Number.isFinite(price) || price <= 0) return 0;
    const step = 50;
    return Math.ceil(price / step) * step;
  }

  async getOffers(passengerId: string, requestId: string) {
    await this.requireOwnedRequest(passengerId, requestId);
    const offers = await this.prisma.intercityOffer.findMany({
      where: { requestId },
      include: { request: true },
    });
    return this.enrichOffers(offers);
  }

  async acceptOffer(passengerId: string, offerId: string) {
    const offer = await this.prisma.intercityOffer.findUnique({
      where: { id: offerId },
      include: { request: true },
    });

    if (!offer || offer.request.passengerId !== passengerId) {
      throw new NotFoundException("Offer not found");
    }
    if (
      ["ACCEPTED", "DRIVER_ASSIGNED"].includes(offer.request.status) &&
      offer.request.selectedOfferId === offerId
    ) {
      return { success: true, alreadyAccepted: true };
    }
    if (offer.request.status !== "OPEN") {
      throw new BadRequestException("Request is no longer open");
    }

    return this.prisma.$transaction(async (tx) => {
      const freshOffer = await tx.intercityOffer.findUnique({
        where: { id: offerId },
        include: { request: true },
      });
      if (!freshOffer || freshOffer.request.passengerId !== passengerId) {
        throw new NotFoundException("Offer not found");
      }
      if (
        ["ACCEPTED", "DRIVER_ASSIGNED"].includes(freshOffer.request.status) &&
        freshOffer.request.selectedOfferId === offerId
      ) {
        return { success: true, alreadyAccepted: true };
      }
      if (freshOffer.request.status !== "OPEN") {
        throw new BadRequestException("Request is no longer open");
      }

      await this.chargeDriverForAcceptedIntercityRequest(
        tx,
        freshOffer.request,
        freshOffer.driverId,
      );
      await this.chargePassengerBonusForAcceptedOffer(
        tx,
        passengerId,
        freshOffer.request,
        freshOffer.price,
      );
      await this.reserveDriverRouteSeatsForAcceptedOffer(
        tx,
        freshOffer.driverId,
        freshOffer.request,
        freshOffer.seats,
      );

      await tx.intercityOffer.update({
        where: { id: offerId },
        data: { status: "ACCEPTED" },
      });
      await tx.intercityRequest.update({
        where: { id: freshOffer.requestId },
        data: {
          status: "DRIVER_ASSIGNED",
          selectedOfferId: offerId,
          selectedDriverId: freshOffer.driverId,
          acceptedAt: new Date(),
        },
      });
      await tx.intercityOffer.updateMany({
        where: { requestId: freshOffer.requestId, id: { not: offerId } },
        data: { status: "REJECTED" },
      });
      const profile = await tx.driverProfile.findUnique({ where: { userId: freshOffer.driverId } });
      if (profile) await applyDriverActivity(tx, profile.id, `accept:intercity:${freshOffer.requestId}:${profile.id}`, DRIVER_ACTIVITY_RULES.acceptReward);
      return { success: true };
    });
  }

  async cancelRequest(passengerId: string, requestId: string) {
    const request = await this.requireOwnedRequest(passengerId, requestId);

    if (request.status === "CANCELLED") {
      return request;
    }
    if (request.status === "COMPLETED") throw new BadRequestException('Завершённую поездку нельзя отменить');

    return this.prisma.$transaction(async (tx) => {
      await this.refundPassengerBonusForCancelledRequest(
        tx,
        passengerId,
        requestId,
      );
      await tx.intercityOffer.updateMany({
        where: {
          requestId,
          status: "PENDING",
        },
        data: {
          status: "REJECTED",
        },
      });

      return tx.intercityRequest.update({
        where: { id: requestId },
        data: { status: "CANCELLED" },
      });
    });
  }

  async updateDriverRequestStatus(
    driverUserId: string,
    requestId: string,
    status: string,
  ) {
    const target = (status || "").toString().toUpperCase();
    const allowedTargets = new Set([
      "DRIVER_ARRIVED",
      "IN_PROGRESS",
      "COMPLETED",
      "CANCELLED",
    ]);
    if (!allowedTargets.has(target)) {
      throw new BadRequestException("Invalid intercity request status");
    }

    const request = await this.prisma.intercityRequest.findUnique({
      where: { id: requestId },
    });
    if (!request || request.selectedDriverId !== driverUserId) {
      throw new NotFoundException("Request not found");
    }

    const current = (request.status || "").toString().toUpperCase();
    if (["COMPLETED", "CANCELLED"].includes(current)) {
      return request;
    }

    const transitions: Record<string, Set<string>> = {
      ACCEPTED: new Set(["DRIVER_ARRIVED", "CANCELLED"]),
      DRIVER_ASSIGNED: new Set(["DRIVER_ARRIVED", "CANCELLED"]),
      DRIVER_EN_ROUTE: new Set(["DRIVER_ARRIVED", "CANCELLED"]),
      DRIVER_ARRIVED: new Set(["IN_PROGRESS", "CANCELLED"]),
      IN_PROGRESS: new Set(["COMPLETED", "CANCELLED"]),
    };
    if (!transitions[current]?.has(target)) {
      throw new BadRequestException(
        "Invalid intercity request status transition",
      );
    }

    if (target === "COMPLETED") {
      const completedAt = new Date();
      return this.prisma.$transaction(async (tx) => {
        const changed = await tx.intercityRequest.updateMany({ where: { id: requestId, status: request.status }, data: { status: target, completedAt } });
        if (changed.count !== 1) return tx.intercityRequest.findUniqueOrThrow({ where: { id: requestId } });
        await this.chargeDriverForCompletedIntercityRequest(
          tx,
          request,
          driverUserId,
        );
        const profile = await tx.driverProfile.findUnique({ where: { userId: driverUserId } });
        const verification = profile ? await finishTripVerification(tx, 'INTERCITY', request, profile.id, driverUserId, completedAt) : 'REVIEW';
        if (verification === 'VERIFIED') await creditRideReferrals(tx, {
          id: requestId, currency: request.currency,
          commissionAmount: await this.getIntercityAcceptedRequestFee(request, driverUserId),
          passengerId: request.passengerId, driverUserId, intercity: true,
        });
        if (profile) await creditDriverDailyBonus(tx, profile.id, driverUserId, request.currency, completedAt);
        return tx.intercityRequest.update({
          where: { id: requestId },
          data: { status: target },
        });
      });
    }

    return this.prisma.$transaction(async tx => {
      const changed = await tx.intercityRequest.updateMany({ where: { id: requestId, status: current }, data: { status: target } });
      if (changed.count !== 1) throw new BadRequestException('Request status changed. Refresh the request.');
      if (target === 'IN_PROGRESS') {
        const profile = await tx.driverProfile.findUnique({where:{userId:driverUserId}});
        if (profile) await startTripVerification(tx,'INTERCITY',request,profile.id,driverUserId);
        if (request.paymentMethod === 'CARD') {
          const offer=request.selectedOfferId ? await tx.intercityOffer.findUnique({where:{id:request.selectedOfferId}}) : null;
          if (!offer || offer.requestId!==request.id || offer.driverId!==driverUserId || offer.status!=='ACCEPTED') throw new BadRequestException('Не удалось подтвердить согласованную стоимость поездки');
          await this.cardPayments.schedule(tx,'INTERCITY',{...request,price:offer.price},driverUserId);
        }
      }
      if (target === 'CANCELLED') await tx.tripVerification.updateMany({where:{id:`INTERCITY:${requestId}`,status:'PENDING'},data:{status:'CANCELLED'}});
      return tx.intercityRequest.findUniqueOrThrow({where:{id:requestId}});
    });
  }

  private async chargeDriverForCompletedIntercityRequest(
    tx: any,
    request: Record<string, any>,
    driverUserId: string,
  ) {
    const requestId = (request["id"] ?? "").toString();
    if (!requestId) return;
    const fee = await this.getIntercityAcceptedRequestFee(
      request,
      driverUserId,
    );
    if (fee <= 0) return;

    const txAny = tx as any;
    const wallet = await tx.wallet.findUnique({
      where: { userId: driverUserId },
      select: { id: true },
    });
    if (!wallet) return;

    await tx.wallet.update({ where: { id: wallet.id }, data: { [moneyField(request["currency"])]: { increment: 0 } } });
    const existing = await txAny.walletTransaction?.findFirst({
      where: {
        walletId: wallet.id,
        type: "DEBIT_INTERCITY_COMPLETED_REQUEST",
        intercityRequestId: requestId,
      },
      select: { id: true },
    });
    if (existing) return;

    await tx.wallet.update({
      where: { id: wallet.id },
      data: { [moneyField(request["currency"])]: { decrement: fee } },
    });
    await consumeLockedBonus(tx, wallet.id, request["currency"], fee);
    await txAny.walletTransaction
      .create({
        data: {
          walletId: wallet.id,
          type: "DEBIT_INTERCITY_COMPLETED_REQUEST",
          direction: "DEBIT",
          balanceSource: "MONEY",
          amount: fee,
          currency: request["currency"] ?? "KZT",
          actorUserId: driverUserId,
          intercityRequestId: requestId,
          note: `Комиссия сервиса за выполненную межгородскую заявку (${requestId})`,
          idempotencyKey: `intercity-complete:${requestId}:driver:${driverUserId}`,
        },
      })
      .catch(async (error: unknown) => {
        const duplicate = (
          error instanceof Error ? error.message : String(error)
        )
          .toLowerCase()
          .includes("idempotencykey");
        if (duplicate) return null;
        throw error;
      });
  }

  private async requireOwnedRequest(passengerId: string, requestId: string) {
    const request = await this.prisma.intercityRequest.findUnique({
      where: { id: requestId },
    });

    if (!request || request.passengerId !== passengerId) {
      throw new NotFoundException("Request not found");
    }

    return request;
  }

  private async ensureDriverCanHandleRequest(
    driverUserId: string,
    request: Record<string, any>,
  ) {
    const requestType = this.normalizeRequestType(
      request["requestType"]?.toString(),
    );
    if (requestType !== "INTERCITY") {
      return;
    }
    const fee = await this.getIntercityAcceptedRequestFee(
      request,
      driverUserId,
    );
    if (fee <= 0) return;
    const wallet = await this.prisma.wallet.findUnique({
      where: { userId: driverUserId },
      select: { money: true, moneyRub: true },
    });
    if (!wallet || wallet[moneyField(request["currency"])] < fee) {
      throw new BadRequestException(
        "Insufficient balance to respond to intercity request. Please top up wallet.",
      );
    }
  }

  private routeKey(value: unknown) {
    return (value ?? "")
      .toString()
      .trim()
      .replace(/\s+/g, " ")
      .toLocaleLowerCase("ru-RU");
  }

  private async ensureDriverRouteHasSeats(
    driverUserId: string,
    request: Record<string, any>,
    seats: number,
  ) {
    const profile = await this.prisma.driverProfile.findUnique({
      where: { userId: driverUserId },
      select: { id: true },
    });
    if (!profile) throw new NotFoundException("Driver profile not found");
    const routes = await this.prisma.driverIntercityRoute.findMany({
      where: {
        driverId: profile.id,
        isActive: true,
      },
      select: { seatsAvailable: true },
    });
    const route = routes.find(
      (item: any) =>
        this.routeKey(item.fromCity) === this.routeKey(request["fromCity"]) &&
        this.routeKey(item.toCity) === this.routeKey(request["toCity"]),
    );
    if (!route || route.seatsAvailable < seats) {
      throw new BadRequestException("Недостаточно свободных мест на этом маршруте");
    }
  }

  private async reserveDriverRouteSeatsForAcceptedOffer(
    tx: any,
    driverUserId: string,
    request: Record<string, any>,
    seats: number,
  ) {
    const profile = await tx.driverProfile.findUnique({
      where: { userId: driverUserId },
      select: { id: true },
    });
    if (!profile) throw new NotFoundException("Driver profile not found");

    const routes = await tx.driverIntercityRoute.findMany({
      where: {
        driverId: profile.id,
        isActive: true,
      },
      orderBy: { updatedAt: "desc" },
    });
    const route = routes.find(
      (item: any) =>
        this.routeKey(item.fromCity) === this.routeKey(request["fromCity"]) &&
        this.routeKey(item.toCity) === this.routeKey(request["toCity"]),
    );
    const seatsToReserve = Math.max(
      1,
      Math.trunc(Number(request["seats"] || seats || 1)),
    );
    if (!route || route.seatsAvailable < seatsToReserve) {
      throw new BadRequestException("Недостаточно свободных мест на этом маршруте");
    }
    const nextSeats = route.seatsAvailable - seatsToReserve;
    await tx.driverIntercityRoute.update({
      where: { id: route.id },
      data: {
        seatsAvailable: nextSeats,
        isActive: nextSeats > 0,
      },
    });
  }

  private async getIntercityAcceptedRequestFee(
    request: Record<string, any>,
    driverUserId: string,
  ) {
    const rub = request['currency'] === 'RUB';
    const driver = await this.prisma.user.findUnique({
      where: { id: driverUserId },
      select: { phone: true },
    });
    if (!rub && !this.isKazakhstanPhone(driver?.phone)) return 0;

    const distanceKm = this.haversineKm(
      this.coerceNullableNumber(request["fromLat"]),
      this.coerceNullableNumber(request["fromLng"]),
      this.coerceNullableNumber(request["toLat"]),
      this.coerceNullableNumber(request["toLng"]),
    );

    const bandSetting = await this.prisma.appSettings.findUnique({
      where: { key: rub ? "intercityCommissionByDistanceKmRub" : "intercityCommissionByDistanceKm" },
    });
    if (bandSetting?.value) {
      try {
        const bands = JSON.parse(bandSetting.value);
        if (Array.isArray(bands)) {
          for (const raw of bands) {
            const band = raw as Record<string, unknown>;
            const fromKm = Number(band.fromKm ?? band.from ?? 0);
            const toRaw = band.toKm ?? band.to;
            const toKm =
              toRaw == null || toRaw === "" ? null : Number(toRaw);
            const fee = Number(band.fee ?? band.amount ?? 0);
            if (
              Number.isFinite(fromKm) &&
              (toKm == null || Number.isFinite(toKm)) &&
              Number.isFinite(fee) &&
              fee >= 0 &&
              distanceKm >= fromKm &&
              (toKm == null || distanceKm < toKm)
            ) {
              return fee;
            }
          }
        }
      } catch {
        // Fallback to legacy fixed fee below.
      }
    }

    const setting = await this.prisma.appSettings.findUnique({
      where: { key: rub ? "intercityAcceptedRequestFeeRub" : "intercityAcceptedRequestFee" },
    });
    const parsed = Number.parseFloat(setting?.value || (rub ? "0" : "500"));
    if (!Number.isFinite(parsed) || parsed < 0) return 0;
    return parsed;
  }

  private async chargeDriverForAcceptedIntercityRequest(
    tx: any,
    request: Record<string, any>,
    driverUserId: string,
  ) {
    const requestType = this.normalizeRequestType(
      request["requestType"]?.toString(),
    );
    if (requestType !== "INTERCITY") {
      return;
    }
    const fee = await this.getIntercityAcceptedRequestFee(
      request,
      driverUserId,
    );
    if (fee <= 0) return;

    const requestId = (request["id"] ?? "").toString();
    if (!requestId) return;

    const txAny = tx as any;
    const wallet = await tx.wallet.findUnique({
      where: { userId: driverUserId },
      select: { id: true, money: true, moneyRub: true },
    });
    if (!wallet || wallet[moneyField(request["currency"])] < fee) {
      throw new BadRequestException(
        "Selected driver has insufficient balance for intercity request.",
      );
    }

    await tx.wallet.update({ where: { id: wallet.id }, data: { [moneyField(request["currency"])]: { increment: 0 } } });
    const existing = await txAny.walletTransaction?.findFirst({
      where: {
        walletId: wallet.id,
        type: "DEBIT_INTERCITY_ACCEPTED_REQUEST",
        intercityRequestId: requestId,
      },
    });
    if (existing) {
      return;
    }

    const charged = await tx.wallet.updateMany({
      where: { id: wallet.id, [moneyField(request["currency"])]: { gte: fee } },
      data: { [moneyField(request["currency"])]: { decrement: fee } },
    });
    if (charged.count !== 1) throw new BadRequestException("Selected driver has insufficient balance for intercity request.");
    await consumeLockedBonus(tx, wallet.id, request["currency"], fee);
    await txAny.walletTransaction
      .create({
        data: {
          walletId: wallet.id,
          type: "DEBIT_INTERCITY_ACCEPTED_REQUEST",
          direction: "DEBIT",
          balanceSource: "MONEY",
          amount: fee,
          currency: request["currency"] ?? "KZT",
          actorUserId: driverUserId,
          intercityRequestId: requestId,
          note: `Списание за принятую межгородскую заявку (${requestId})`,
          idempotencyKey: `intercity-accept:${requestId}:driver:${driverUserId}`,
        },
      })
      .catch(async (error: unknown) => {
        const duplicate = (
          error instanceof Error ? error.message : String(error)
        )
          .toLowerCase()
          .includes("idempotencykey");
        if (duplicate) {
          return null;
        }
        throw error;
      });
  }

  private async chargePassengerBonusForAcceptedOffer(
    tx: any,
    passengerId: string,
    request: Record<string, any>,
    offerPrice: number,
  ) {
    const paymentMethod = (request["paymentMethod"] ?? "")
      .toString()
      .toUpperCase();
    if (paymentMethod !== "BONUSES") return;

    const amount = Number(offerPrice);
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new BadRequestException("Invalid bonus payment amount");
    }

    const requestId = (request["id"] ?? "").toString();
    if (!requestId) return;

    const txAny = tx as any;
    const wallet = await tx.wallet.findUnique({
      where: { userId: passengerId },
      select: { id: true, bonus: true, bonusRub: true },
    });
    if (!wallet || wallet[bonusField(request["currency"])] < amount) {
      throw new BadRequestException("Insufficient bonus balance");
    }

    await tx.wallet.update({ where: { id: wallet.id }, data: { [bonusField(request["currency"])]: { increment: 0 } } });
    const existing = await txAny.walletTransaction?.findFirst({
      where: {
        walletId: wallet.id,
        type: "INTERCITY_OFFER_BONUS_USED",
        intercityRequestId: requestId,
      },
    });
    if (existing) return;

    const debit = await tx.wallet.updateMany({
      where: { id: wallet.id, [bonusField(request["currency"])]: { gte: amount } },
      data: { [bonusField(request["currency"])]: { decrement: amount } },
    });
    if (debit.count !== 1) throw new BadRequestException("Insufficient bonus balance");
    await txAny.walletTransaction
      .create({
        data: {
          walletId: wallet.id,
          type: "INTERCITY_OFFER_BONUS_USED",
          direction: "DEBIT",
          balanceSource: "BONUS",
          currency: request["currency"] ?? "KZT",
          amount,
          actorUserId: passengerId,
          intercityRequestId: requestId,
          note: `Оплата бонусами по предложению водителя (${requestId})`,
          idempotencyKey: `intercity-bonus:${requestId}:passenger:${passengerId}`,
        },
      })
      .catch(async (error: unknown) => {
        const duplicate = (
          error instanceof Error ? error.message : String(error)
        )
          .toLowerCase()
          .includes("idempotencykey");
        if (duplicate) return null;
        throw error;
      });
  }

  private async refundPassengerBonusForCancelledRequest(
    tx: any,
    passengerId: string,
    requestId: string,
  ) {
    const txAny = tx as any;
    const wallet = await tx.wallet.findUnique({
      where: { userId: passengerId },
      select: { id: true },
    });
    if (!wallet) return;

    await tx.wallet.update({ where: { id: wallet.id }, data: { ['bonusRub']: { increment: 0 } } });
    const debit = await txAny.walletTransaction?.findFirst({
      where: {
        walletId: wallet.id,
        type: "INTERCITY_OFFER_BONUS_USED",
        intercityRequestId: requestId,
      },
      orderBy: { createdAt: "desc" },
    });
    if (!debit) return;

    const existingRefund = await txAny.walletTransaction?.findFirst({
      where: {
        walletId: wallet.id,
        type: "INTERCITY_OFFER_BONUS_REFUND",
        intercityRequestId: requestId,
      },
    });
    if (existingRefund) return;

    const amount = Number(debit.amount);
    if (!Number.isFinite(amount) || amount <= 0) return;

    await tx.wallet.update({
      where: { id: wallet.id },
      data: { [bonusField(debit.currency)]: { increment: amount } },
    });
    await txAny.walletTransaction
      .create({
        data: {
          walletId: wallet.id,
          type: "INTERCITY_OFFER_BONUS_REFUND",
          direction: "CREDIT",
          balanceSource: "BONUS",
          currency: debit.currency ?? "KZT",
          amount,
          actorUserId: passengerId,
          intercityRequestId: requestId,
          note: `Возврат бонусов при отмене заявки (${requestId})`,
          idempotencyKey: `intercity-bonus-refund:${requestId}:passenger:${passengerId}`,
        },
      })
      .catch(async (error: unknown) => {
        const duplicate = (
          error instanceof Error ? error.message : String(error)
        )
          .toLowerCase()
          .includes("idempotencykey");
        if (duplicate) return null;
        throw error;
      });
  }

  private async enrichOffers(offers: Array<Record<string, any>>) {
    const driverIds = Array.from(
      new Set(
        offers
          .map((offer) => offer["driverId"]?.toString().trim() ?? "")
          .filter((driverId) => driverId.length > 0),
      ),
    );

    if (driverIds.length === 0) {
      return offers;
    }

    const drivers = await this.prisma.user.findMany({
      where: {
        id: { in: driverIds },
      },
      select: {
        ...clientUserSelect,
        driverProfile: {
          select: {
            id: true,
            carModel: true,
            carNumber: true,
            rating: {
              select: {
                ratingAvg: true,
                ratingCount: true,
              },
            },
          },
        },
      },
    });

    const driversById = new Map(drivers.map((driver) => [driver.id, driver]));

    return offers.map((offer) => ({
      ...offer,
      driver: driversById.get(offer["driverId"]?.toString() ?? "") ?? null,
    }));
  }
}
