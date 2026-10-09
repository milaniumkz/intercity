import { releaseVerifiedTripRewards } from '../common/trip-verification';
import { reviseDriverRating, validateReviewDecision } from '../common/driver-rating-review';
import { parseDailyBonus } from '../common/driver-daily-bonus';
import { moneyField, bonusField, walletCurrency } from '../common/currency';
import { Injectable, NotFoundException, BadRequestException, Logger, ServiceUnavailableException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { NotificationDispatchService } from './notification-dispatch.service';
import { adminUserSelect } from '../common/public-user-select';
import { countryCodeFromRegion } from '../common/currency';

type RequestLogItem = {
    at: string;
    method: string;
    path: string;
    statusCode: number;
    durationMs: number;
    ip?: string;
    userAgent?: string;
};

type ErrorLogItem = {
    at: string;
    source: string;
    message: string;
    path?: string;
    method?: string;
    statusCode?: number;
};

type AdminAuditLogItem = {
    at: string;
    adminId: string;
    role: string;
    action: string;
    target?: string;
    details?: Record<string, unknown>;
    status?: string;
    ip?: string;
    userAgent?: string;
};

type PermissionSeed = {
    key: string;
    module: string;
    action: string;
    description: string;
};

@Injectable()
export class AdminService {
    private readonly logger = new Logger(AdminService.name);
    private readonly startedAt = new Date();
    private readonly requestLogs: RequestLogItem[] = [];
    private readonly errorLogs: ErrorLogItem[] = [];
    private readonly auditLogs: AdminAuditLogItem[] = [];
    private readonly logsLimit = 2000;
    private readonly defaultPermissions: PermissionSeed[] = [
        { key: 'dashboard.view', module: 'dashboard', action: 'view', description: 'Просмотр dashboard' },
        { key: 'orders.view', module: 'orders', action: 'view', description: 'Просмотр заказов' },
        { key: 'orders.manage', module: 'orders', action: 'manage', description: 'Управление заказами' },
        { key: 'drivers.view', module: 'drivers', action: 'view', description: 'Просмотр водителей' },
        { key: 'drivers.manage', module: 'drivers', action: 'manage', description: 'Управление водителями' },
        { key: 'users.view', module: 'users', action: 'view', description: 'Просмотр пользователей' },
        { key: 'users.manage', module: 'users', action: 'manage', description: 'Управление пользователями' },
        { key: 'finance.view', module: 'finance', action: 'view', description: 'Просмотр финансов' },
        { key: 'finance.manage', module: 'finance', action: 'manage', description: 'Управление финансами' },
        { key: 'tariffs.view', module: 'tariffs', action: 'view', description: 'Просмотр тарифов' },
        { key: 'tariffs.manage', module: 'tariffs', action: 'manage', description: 'Управление тарифами' },
        { key: 'vehicles.view', module: 'vehicles', action: 'view', description: 'Просмотр автопарка' },
        { key: 'vehicles.manage', module: 'vehicles', action: 'manage', description: 'Управление автопарком' },
        { key: 'promos.view', module: 'promos', action: 'view', description: 'Просмотр промокодов' },
        { key: 'promos.manage', module: 'promos', action: 'manage', description: 'Управление промокодами' },
        { key: 'support.view', module: 'support', action: 'view', description: 'Просмотр жалоб' },
        { key: 'support.manage', module: 'support', action: 'manage', description: 'Управление жалобами' },
        { key: 'notifications.view', module: 'notifications', action: 'view', description: 'Просмотр рассылок' },
        { key: 'notifications.manage', module: 'notifications', action: 'manage', description: 'Управление рассылками' },
        { key: 'settings.view', module: 'settings', action: 'view', description: 'Просмотр настроек' },
        { key: 'settings.manage', module: 'settings', action: 'manage', description: 'Управление настройками' },
        { key: 'collections.view', module: 'collections', action: 'view', description: 'Просмотр коллекций БД' },
        { key: 'collections.manage', module: 'collections', action: 'manage', description: 'Изменение коллекций БД' },
        { key: 'system.view', module: 'system', action: 'view', description: 'Просмотр мониторинга и логов' },
        { key: 'system.manage', module: 'system', action: 'manage', description: 'Критические системные действия' },
        { key: 'rbac.view', module: 'rbac', action: 'view', description: 'Просмотр ролей и прав' },
        { key: 'rbac.manage', module: 'rbac', action: 'manage', description: 'Управление ролями и правами' },
    ];

    constructor(
        private prisma: PrismaService,
        private readonly realtimeService: RealtimeService,
        private readonly notificationDispatchService: NotificationDispatchService,
    ) { }

    private async existingOptionalTables(tableNames: string[]) {
        const existing = new Set<string>();
        for (const tableName of tableNames) {
            try {
                const rows = await this.prisma.$queryRawUnsafe<Array<{ regclass: string | null }>>(
                    `SELECT to_regclass('public."${tableName}"') as regclass`,
                );
                if (rows[0]?.regclass) {
                    existing.add(tableName);
                }
            } catch (_) {
                // If metadata lookup fails, treat the table as unavailable.
            }
        }
        return existing;
    }

    async getPendingDrivers() {
        return this.prisma.driverProfile.findMany({
            where: { status: 'PENDING' },
            include: {
                user: { select: adminUserSelect },
            },
        });
    }

    async approveDriver(driverId: string) {
        const profile = await this.prisma.driverProfile.findUnique({
            where: { id: driverId },
        });
        if (!profile) throw new NotFoundException('Driver not found');

        await this.prisma.driverProfile.update({
            where: { id: driverId },
            data: { status: 'ACTIVE', rejectionReason: null },
        });

        // Set service start date
        await this.prisma.driverServiceStats.update({
            where: { driverId },
            data: { serviceStartAt: new Date() },
        });

        return { success: true };
    }

    async rejectDriver(driverId: string, reason?: string) {
        const profile = await this.prisma.driverProfile.findUnique({
            where: { id: driverId },
        });
        if (!profile) throw new NotFoundException('Driver not found');

        return this.prisma.driverProfile.update({
            where: { id: driverId },
            data: { status: 'REJECTED', rejectionReason: reason || null },
        });
    }

    async setDriverFlags(driverId: string, hasCheckers: boolean, hasBranding: boolean) {
        return this.prisma.driverPriorityFlags.upsert({
            where: { driverId },
            update: { hasCheckers, hasBranding },
            create: { driverId, hasCheckers, hasBranding },
        });
    }

    async setFuelBonus(driverId: string, hours = 24) {
        if (hours !== 24) throw new BadRequestException('Бонус заправки действует 24 часа');
        const bonusUntil = new Date(Date.now() + 24 * 60 * 60 * 1000);
        return this.prisma.driverPartnerFuelBonus.upsert({
            where: { driverId },
            update: { bonusActiveUntil: bonusUntil },
            create: { driverId, bonusActiveUntil: bonusUntil },
        });
    }

    async getDriverPriority(driverId: string) {
        const profile = await this.prisma.driverProfile.findUnique({
            where: { id: driverId },
            include: {
                rating: true,
                priorityFlags: true,
                serviceStats: true,
                fuelBonus: true,
            },
        });
        return profile;
    }

    // Cities CRUD
    async getCities() {
        return this.prisma.city.findMany({ orderBy: { name: 'asc' } });
    }

    async createCity(data: { name: string; region?: string; countryCode?: string; lat: number; lng: number }) {
        if (data.countryCode != null && typeof data.countryCode !== 'string') throw new BadRequestException('Country must be KZ or RU');
        const countryCode = data.countryCode?.toUpperCase() || countryCodeFromRegion(data.region);
        if (!['KZ', 'RU'].includes(countryCode)) throw new BadRequestException('Country must be KZ or RU');
        return this.prisma.city.create({ data: { ...data, countryCode } });
    }

    async updateCity(id: string, data: Partial<{ name: string; region: string; countryCode: string; lat: number; lng: number; isActive: boolean }>) {
        if (data.countryCode != null) {
            if (typeof data.countryCode !== 'string') throw new BadRequestException('Country must be KZ or RU');
            data = { ...data, countryCode: data.countryCode.toUpperCase() };
            if (!['KZ', 'RU'].includes(data.countryCode)) throw new BadRequestException('Country must be KZ or RU');
        }
        return this.prisma.city.update({ where: { id }, data });
    }

    async deleteCity(id: string) {
        return this.prisma.city.delete({ where: { id } });
    }

    // Tariffs CRUD
    async getCityTariffs(cityId: string) {
        return this.prisma.tariffCity.findMany({ where: { cityId } });
    }

    async getAllCityTariffs() {
        return this.prisma.tariffCity.findMany({
            include: { city: true },
            orderBy: { createdAt: 'desc' },
        });
    }

    async createCityTariff(data: { cityId: string; name: string; basePrice: number; pricePerKm: number; pricePerMin: number; minPrice: number }) {
        this.validateCityTariff(data);
        const city = await this.prisma.city.findUnique({ where: { id: data.cityId } });
        if (!city) throw new BadRequestException('City not found');
        return this.prisma.tariffCity.create({ data });
    }

    async updateCityTariff(id: string, data: Partial<{ name: string; basePrice: number; pricePerKm: number; pricePerMin: number; minPrice: number; isActive: boolean }>) {
        this.validateCityTariff(data);
        return this.prisma.tariffCity.update({ where: { id }, data });
    }

    private validateCityTariff(data: Partial<{ name: string; basePrice: number; pricePerKm: number; pricePerMin: number; minPrice: number }>) {
        if (data.name != null && (typeof data.name !== 'string' || !data.name.trim())) throw new BadRequestException('Tariff name is required');
        for (const key of ['basePrice', 'pricePerKm', 'pricePerMin', 'minPrice'] as const) {
            const value = data[key];
            if (value != null && (typeof value !== 'number' || !Number.isFinite(value) || value < 0)) {
                throw new BadRequestException(`Invalid tariff amount: ${key}`);
            }
        }
    }

    async deleteCityTariff(id: string) {
        return this.prisma.tariffCity.delete({ where: { id } });
    }

    async getCargoTariffs() {
        return this.prisma.tariffCargo.findMany();
    }

    async createCargoTariff(data: { name: string; basePrice: number; pricePerKm: number; pricePerKg: number; minPrice: number }) {
        return this.prisma.tariffCargo.create({ data });
    }

    async updateCargoTariff(id: string, data: Partial<{ name: string; basePrice: number; pricePerKm: number; pricePerKg: number; minPrice: number; isActive: boolean }>) {
        return this.prisma.tariffCargo.update({ where: { id }, data });
    }

    async deleteCargoTariff(id: string) {
        return this.prisma.tariffCargo.delete({ where: { id } });
    }

    async getDeliveryTariffs() {
        return this.prisma.tariffDelivery.findMany();
    }

    async createDeliveryTariff(data: { name: string; basePrice: number; pricePerKm: number; pricePerKg: number; minPrice: number; doorToDoorFee: number }) {
        return this.prisma.tariffDelivery.create({ data });
    }

    async updateDeliveryTariff(id: string, data: Partial<{ name: string; basePrice: number; pricePerKm: number; pricePerKg: number; minPrice: number; doorToDoorFee: number; isActive: boolean }>) {
        return this.prisma.tariffDelivery.update({ where: { id }, data });
    }

    async deleteDeliveryTariff(id: string) {
        return this.prisma.tariffDelivery.delete({ where: { id } });
    }

    async getVehicles() {
        return this.safeOptionalAdminList('vehicles', () =>
            (this.prisma as any).vehicle.findMany({
                orderBy: { createdAt: 'desc' },
                include: {
                    driver: {
                        include: { user: { select: adminUserSelect } },
                    },
                },
                take: 500,
            }),
        );
    }

    async createVehicle(data: {
        driverId: string;
        brand: string;
        model: string;
        year?: number;
        plateNumber: string;
        color?: string;
        verificationStatus?: string;
        isActive?: boolean;
    }) {
        return (this.prisma as any).vehicle.create({
            data: {
                driverId: data.driverId,
                brand: data.brand,
                model: data.model,
                year: data.year ?? null,
                plateNumber: data.plateNumber,
                color: data.color ?? null,
                verificationStatus: data.verificationStatus ?? 'PENDING',
                isActive: data.isActive ?? true,
            },
        });
    }

    async updateVehicle(id: string, data: Record<string, unknown>) {
        return (this.prisma as any).vehicle.update({
            where: { id },
            data: this.sanitizePayload(data, true),
        });
    }

    async deleteVehicle(id: string) {
        return (this.prisma as any).vehicle.delete({ where: { id } });
    }

    async getPromos() {
        return this.safeOptionalAdminList('promos', () =>
            (this.prisma as any).promoCode.findMany({
                orderBy: { createdAt: 'desc' },
                include: {
                    city: true,
                    usages: {
                        select: { id: true, userId: true, orderId: true, discount: true, createdAt: true },
                        take: 50,
                        orderBy: { createdAt: 'desc' },
                    },
                },
                take: 500,
            }),
        );
    }

    async createPromo(data: Record<string, unknown>) {
        return (this.prisma as any).promoCode.create({
            data: {
                code: (data['code'] ?? '').toString().trim().toUpperCase(),
                title: (data['title'] ?? '').toString().trim(),
                discountType: (data['discountType'] ?? 'PERCENT').toString().toUpperCase(),
                discountValue: Number(data['discountValue'] ?? 0),
                minOrderAmount: data['minOrderAmount'] != null ? Number(data['minOrderAmount']) : null,
                maxDiscount: data['maxDiscount'] != null ? Number(data['maxDiscount']) : null,
                usageLimit: data['usageLimit'] != null ? Number(data['usageLimit']) : null,
                perUserLimit: data['perUserLimit'] != null ? Number(data['perUserLimit']) : 1,
                startsAt: data['startsAt'] != null ? new Date(data['startsAt'] as string) : null,
                expiresAt: data['expiresAt'] != null ? new Date(data['expiresAt'] as string) : null,
                isActive: data['isActive'] == null ? true : data['isActive'] === true,
                cityId: data['cityId']?.toString() || null,
            },
        });
    }

    async updatePromo(id: string, data: Record<string, unknown>) {
        const payload: Record<string, unknown> = {};
        if (data['title'] != null) payload['title'] = data['title']?.toString().trim();
        if (data['discountType'] != null) payload['discountType'] = data['discountType']?.toString().toUpperCase();
        if (data['discountValue'] != null) payload['discountValue'] = Number(data['discountValue']);
        if (data['minOrderAmount'] != null) payload['minOrderAmount'] = Number(data['minOrderAmount']);
        if (data['maxDiscount'] != null) payload['maxDiscount'] = Number(data['maxDiscount']);
        if (data['usageLimit'] != null) payload['usageLimit'] = Number(data['usageLimit']);
        if (data['perUserLimit'] != null) payload['perUserLimit'] = Number(data['perUserLimit']);
        if (data['startsAt'] != null) payload['startsAt'] = new Date(data['startsAt'] as string);
        if (data['expiresAt'] != null) payload['expiresAt'] = new Date(data['expiresAt'] as string);
        if (data['isActive'] != null) payload['isActive'] = data['isActive'] === true;
        if (data['cityId'] != null) payload['cityId'] = data['cityId']?.toString() || null;
        return (this.prisma as any).promoCode.update({
            where: { id },
            data: payload,
        });
    }

    async deletePromo(id: string) {
        return (this.prisma as any).promoCode.update({
            where: { id },
            data: { isActive: false },
        });
    }

    async getComplaints(status?: string) {
        return this.safeOptionalAdminList('complaints', () =>
            (this.prisma as any).complaint.findMany({
                where: status ? { status: status.toUpperCase() } : undefined,
                orderBy: { createdAt: 'desc' },
                include: {
                    user: { select: adminUserSelect },
                    driver: { include: { user: { select: adminUserSelect } } },
                    order: true,
                },
                take: 500,
            }),
        );
    }

    async createComplaint(data: Record<string, unknown>) {
        return (this.prisma as any).complaint.create({
            data: {
                type: (data['type'] ?? 'GENERAL').toString(),
                text: (data['text'] ?? '').toString(),
                status: (data['status'] ?? 'NEW').toString().toUpperCase(),
                userId: data['userId']?.toString() || null,
                driverId: data['driverId']?.toString() || null,
                orderId: data['orderId']?.toString() || null,
            },
        });
    }

    async updateComplaint(id: string, data: Record<string, unknown>) {
        const complaint = await this.prisma.complaint.findUnique({where:{id}});
        if (!complaint) throw new BadRequestException('Обращение не найдено');
        if (complaint.type === 'LOW_DRIVER_RATING') {
            const {decision,note,rating} = validateReviewDecision(data);
            const result = await this.prisma.$transaction(async tx => {
                const order = await tx.order.findUnique({where:{id:complaint.orderId!}});
                if (!order?.driverId || order.driverRating == null) throw new BadRequestException('Оценка поездки не найдена');
                await tx.$executeRaw`SELECT id FROM "DriverProfile" WHERE id = ${order.driverId} FOR UPDATE`;
                const fresh = await tx.order.findUnique({where:{id:order.id}});
                const oldRating = fresh!.driverRatingStatus === 'COUNTED' ? fresh!.driverRating : null;
                const effectiveRating = decision === 'REJECT' ? null : decision === 'CHANGE' ? rating : fresh!.driverRating!;
                await reviseDriverRating(tx,order.driverId,oldRating,effectiveRating);
                await tx.order.update({where:{id:order.id},data:{driverRating:effectiveRating ?? fresh!.driverRating,driverRatingStatus:decision==='REJECT'?'REJECTED':'COUNTED'}});
                return tx.complaint.update({where:{id},data:{status:'RESOLVED',resolutionNote:`${decision}: ${note}`}});
            });
            this.realtimeService.publish({type:'driver.rating.updated',entity:'driver',entityId:complaint.driverId!,at:new Date().toISOString(),payload:{driverId:complaint.driverId,orderId:complaint.orderId}});
            return result;
        }
        const payload: Record<string, unknown> = {};
        if (data['status'] != null) payload['status'] = data['status']?.toString().toUpperCase();
        if (data['resolutionNote'] != null) payload['resolutionNote'] = data['resolutionNote']?.toString();
        if (data['text'] != null) payload['text'] = data['text']?.toString();
        return (this.prisma as any).complaint.update({
            where: { id },
            data: payload,
        });
    }

    async getNotificationCampaigns() {
        return this.safeOptionalAdminList('notificationCampaigns', () =>
            (this.prisma as any).notificationCampaign.findMany({
                orderBy: { createdAt: 'desc' },
                include: { city: true },
                take: 500,
            }),
        );
    }

    private async safeOptionalAdminList<T>(
        section: string,
        loader: () => Promise<T[]>,
    ): Promise<T[]> {
        try {
            return await loader();
        } catch (error: any) {
            this.logger.warn(
                `Optional admin section "${section}" is unavailable: ${error?.message?.toString?.() ?? error}`,
            );
            return [];
        }
    }

    async createNotificationCampaign(data: Record<string, unknown>, adminId?: string) {
        let created: any;
        try {
            created = await (this.prisma as any).notificationCampaign.create({
                data: {
                    title: (data['title'] ?? '').toString(),
                    body: (data['body'] ?? '').toString(),
                    audience: (data['audience'] ?? 'ALL').toString().toUpperCase(),
                    cityId: data['cityId']?.toString() || null,
                    isSent: data['isSent'] === true,
                    sentAt: data['isSent'] === true ? new Date() : null,
                    createdById: adminId ?? null,
                },
            });
        } catch (error) {
            if (this.isMissingCollectionStorageError(error, 'NotificationCampaign')) {
                throw new ServiceUnavailableException(
                    'Notification module is unavailable until database migrations are applied',
                );
            }
            throw error;
        }
        this.realtimeService.publish({
            type: 'notification.campaign.created',
            entity: 'system',
            entityId: created.id,
            at: new Date().toISOString(),
            payload: { title: created.title, audience: created.audience },
        });
        return created;
    }

    async updateNotificationCampaign(id: string, data: Record<string, unknown>) {
        const payload: Record<string, unknown> = {};
        if (data['title'] != null) payload['title'] = data['title']?.toString();
        if (data['body'] != null) payload['body'] = data['body']?.toString();
        if (data['audience'] != null) payload['audience'] = data['audience']?.toString().toUpperCase();
        if (data['cityId'] != null) payload['cityId'] = data['cityId']?.toString() || null;
        if (data['isSent'] != null) {
            payload['isSent'] = data['isSent'] === true;
            if (data['isSent'] === true) {
                payload['sentAt'] = new Date();
            }
        }
        let updated: any;
        try {
            updated = await (this.prisma as any).notificationCampaign.update({
                where: { id },
                data: payload,
            });
        } catch (error) {
            if (this.isMissingCollectionStorageError(error, 'NotificationCampaign')) {
                throw new ServiceUnavailableException(
                    'Notification module is unavailable until database migrations are applied',
                );
            }
            throw error;
        }
        this.realtimeService.publish({
            type: 'notification.campaign.updated',
            entity: 'system',
            entityId: updated.id,
            at: new Date().toISOString(),
            payload: { isSent: updated.isSent, sentAt: updated.sentAt?.toISOString?.() ?? null },
        });
        return updated;
    }

    async deleteNotificationCampaign(id: string) {
        let deleted: any;
        try {
            deleted = await (this.prisma as any).notificationCampaign.delete({ where: { id } });
        } catch (error) {
            if (this.isMissingCollectionStorageError(error, 'NotificationCampaign')) {
                throw new ServiceUnavailableException(
                    'Notification module is unavailable until database migrations are applied',
                );
            }
            throw error;
        }
        this.realtimeService.publish({
            type: 'notification.campaign.deleted',
            entity: 'system',
            entityId: id,
            at: new Date().toISOString(),
            payload: { title: deleted.title },
        });
        return deleted;
    }

    async sendNotificationCampaign(id: string) {
        let campaign: any;
        try {
            campaign = await (this.prisma as any).notificationCampaign.findUnique({
                where: { id },
                select: { id: true },
            });
        } catch (error) {
            if (this.isMissingCollectionStorageError(error, 'NotificationCampaign')) {
                throw new ServiceUnavailableException(
                    'Notification module is unavailable until database migrations are applied',
                );
            }
            throw error;
        }
        if (!campaign) {
            throw new NotFoundException('Campaign not found');
        }
        const job = await this.notificationDispatchService.enqueue(id);
        this.realtimeService.publish({
            type: 'notification.dispatch.queued',
            entity: 'system',
            entityId: id,
            at: new Date().toISOString(),
            payload: { jobId: job.id },
        });
        return job;
    }

    async requeueNotificationDispatchJob(jobId: string) {
        const job = await this.notificationDispatchService.getJob(jobId);
        if (!job) throw new NotFoundException('Dispatch job not found');
        if (job.status !== 'FAILED') {
            throw new BadRequestException('Only FAILED jobs can be requeued');
        }
        const queued = await this.notificationDispatchService.enqueue(job.campaignId, {
            retryCount: (job.retryCount ?? 0) + 1,
            requeuedFromJobId: job.id,
        });
        this.realtimeService.publish({
            type: 'notification.dispatch.requeued',
            entity: 'system',
            entityId: job.campaignId,
            at: new Date().toISOString(),
            payload: {
                previousJobId: job.id,
                newJobId: queued.id,
                retryCount: queued.retryCount ?? 0,
            },
        });
        return queued;
    }

    async getNotificationDispatchJob(jobId: string) {
        const job = await this.notificationDispatchService.getJob(jobId);
        if (!job) throw new NotFoundException('Dispatch job not found');
        return job;
    }

    async listNotificationDispatchJobs(limit?: number) {
        return this.notificationDispatchService.listJobs(limit ?? 100);
    }

    async getTripReviews(status?: string) {
        return this.prisma.tripVerification.findMany({ where: status ? { status } : { status: { in: ['REVIEW', 'APPROVED', 'REJECTED'] } }, orderBy: { completedAt: 'desc' }, take: 250 });
    }
    async decideTripReview(id: string, decision: string, note: string, adminId: string) {
        if (!['APPROVE', 'REJECT'].includes(decision) || typeof note !== 'string' || note.trim().length < 5 || note.length > 2000) throw new BadRequestException('Выберите решение и укажите обоснование (5–2000 символов).');
        const record = await this.prisma.$transaction(async tx => {
            await tx.$executeRaw`SELECT id FROM "TripVerification" WHERE id = ${id} FOR UPDATE`;
            const current = await tx.tripVerification.findUnique({where:{id}});
            if (!current) throw new NotFoundException('Trip review not found');
            if (current.status !== 'REVIEW') throw new BadRequestException('Решение уже принято. Обновите список.');
            const updated = await tx.tripVerification.update({where:{id},data:{status:decision === 'APPROVE' ? 'APPROVED' : 'REJECTED',resolutionNote:note.trim(),reviewedBy:adminId,reviewedAt:new Date()}});
            if (decision === 'APPROVE') await releaseVerifiedTripRewards(tx,updated);
            return updated;
        });
        this.realtimeService.publish({type:'driver.bonus.updated',entity:'driver',entityId:record.driverId,at:new Date().toISOString(),payload:{tripId:record.tripId,reviewStatus:record.status}});
        return record;
    }

    // Settings
    async getSettings() {
        return this.prisma.appSettings.findMany();
    }

    async setSetting(key: string, value: string) {
        if (key === 'kassa24SavedCardsEnabled' && !['true','false'].includes(value)) throw new BadRequestException('Укажите true или false');
        if (key === 'kassa24AcquiringId' && (!/^\d+$/.test(value) || !Number.isSafeInteger(Number(value)) || Number(value) <= 0)) throw new BadRequestException('Укажите числовой acquiringId терминала Kassa24');
        if (['driverDailyBonusKZT', 'driverDailyBonusRUB'].includes(key)) {
            try { parseDailyBonus(value); } catch (error: any) { throw new BadRequestException(error.message); }
        }
        if (key === 'referralCommissionPercent') {
            const percent = Number(value);
            if (!value.trim() || !Number.isFinite(percent) || percent < 0 || percent > 100) throw new BadRequestException('Referral commission percentage must be between 0 and 100');
        }
        if (['appStoreUrl', 'googlePlayUrl'].includes(key) && value.trim()) {
            let url: URL;
            try { url = new URL(value); } catch { throw new BadRequestException('Invalid app store URL'); }
            const host = key === 'appStoreUrl' ? 'apps.apple.com' : 'play.google.com';
            if (url.protocol !== 'https:' || url.hostname !== host) throw new BadRequestException('Invalid app store URL');
        }
        const setting = await this.prisma.appSettings.upsert({
            where: { key },
            update: { value },
            create: { key, value },
        });
        if (key.startsWith('driverDailyBonus')) this.realtimeService.publish({ type: 'promotion.settings.changed', entity: 'system', at: new Date().toISOString(), payload: { currency: key.endsWith('RUB') ? 'RUB' : 'KZT' } });
        return setting;
    }

    // Topups
    async getTopups() {
        return this.prisma.topupRequest.findMany({
            orderBy: { createdAt: 'desc' },
            include: {
                wallet: {
                    include: {
                        user: { select: adminUserSelect },
                    },
                },
            },
        });
    }

    async approveTopup(id: string) {
        const topup = await this.prisma.topupRequest.findUnique({
            where: { id },
            include: { wallet: true },
        });
        if (!topup) throw new NotFoundException('Topup not found');
        if (topup.status !== 'PENDING') {
            throw new BadRequestException(`Topup already ${topup.status.toLowerCase()}`);
        }

        await this.prisma.$transaction(async (tx) => {
            const current = await tx.topupRequest.findUnique({ where: { id } });
            if (!current) throw new NotFoundException('Topup not found');
            if (current.status !== 'PENDING') {
                throw new BadRequestException(`Topup already ${current.status.toLowerCase()}`);
            }
            const claimed = await tx.topupRequest.updateMany({
                where: { id, status: 'PENDING' }, data: { status: 'APPROVED' },
            });
            if (claimed.count !== 1) throw new BadRequestException('Topup already processed');
            await tx.wallet.update({
                where: { id: topup.walletId },
                data: { [moneyField(topup.currency)]: { increment: topup.amount } },
            });
            await (tx as any).walletTransaction.create({
                data: {
                    walletId: topup.walletId,
                    type: 'TOPUP_APPROVED',
                    direction: 'CREDIT',
                    balanceSource: 'MONEY',
                    amount: topup.amount,
                    currency: topup.currency,
                    topupRequestId: topup.id,
                    note: 'Admin approved topup request',
                },
            }).catch(() => null);
        });
        this.realtimeService.publish({
            type: 'finance.topup.approved',
            entity: 'system',
            entityId: id,
            at: new Date().toISOString(),
            payload: { amount: topup.amount, currency: topup.currency, walletId: topup.walletId },
        });
        return { success: true };
    }

    async rejectTopup(id: string) {
        const topup = await this.prisma.topupRequest.findUnique({ where: { id } });
        if (!topup) throw new NotFoundException('Topup not found');
        if (topup.status !== 'PENDING') {
            throw new BadRequestException(`Topup already ${topup.status.toLowerCase()}`);
        }
        const updated = await this.prisma.topupRequest.update({
            where: { id },
            data: { status: 'REJECTED' },
        });
        this.realtimeService.publish({
            type: 'finance.topup.rejected',
            entity: 'system',
            entityId: id,
            at: new Date().toISOString(),
            payload: { amount: updated.amount, walletId: updated.walletId },
        });
        return updated;
    }

    // Payouts
    async getPayouts() {
        return this.prisma.payoutRequest.findMany({
            orderBy: { createdAt: 'desc' },
            select: {
                id: true,
                walletId: true,
                amount: true,
                currency: true,
                status: true,
                adminId: true,
                createdAt: true,
                updatedAt: true,
                wallet: {
                    include: {
                        user: { select: adminUserSelect },
                    },
                },
            },
        });
    }

    async getWalletTransactions(params?: {
        take?: number;
        skip?: number;
        walletId?: string;
        userId?: string;
        type?: string;
        source?: string;
        from?: string;
        to?: string;
    }) {
        const take = Math.max(1, Math.min(500, Number(params?.take ?? 100) || 100));
        const skip = Math.max(0, Number(params?.skip ?? 0) || 0);
        const where: any = {};
        if (params?.walletId?.trim()) where.walletId = params.walletId.trim();
        if (params?.type?.trim()) where.type = params.type.trim().toUpperCase();
        if (params?.source?.trim()) where.balanceSource = params.source.trim().toUpperCase();
        if (params?.from || params?.to) {
            where.createdAt = {
                ...(params.from ? { gte: new Date(params.from) } : {}),
                ...(params.to ? { lte: new Date(params.to) } : {}),
            };
        }
        if (params?.userId?.trim()) {
            where.wallet = { userId: params.userId.trim() };
        }
        try {
            return await (this.prisma as any).walletTransaction.findMany({
                where,
                include: {
                    wallet: {
                        include: {
                            user: { select: adminUserSelect },
                        },
                    },
                },
                orderBy: { createdAt: 'desc' },
                skip,
                take,
            });
        } catch (_) {
            return [];
        }
    }

    async exportWalletTransactionsCsv(params?: {
        walletId?: string;
        userId?: string;
        type?: string;
        source?: string;
        from?: string;
        to?: string;
    }) {
        const rows = await this.getWalletTransactions({
            ...params,
            take: 5000,
            skip: 0,
        });
        const lines: string[] = [];
        lines.push('id,createdAt,walletId,userId,userPhone,type,direction,balanceSource,amount,currency,note,orderId,topupRequestId,payoutRequestId');
        for (const row of rows as any[]) {
            const user = row?.wallet?.user ?? {};
            const cols = [
                row?.id ?? '',
                row?.createdAt ? new Date(row.createdAt).toISOString() : '',
                row?.walletId ?? '',
                user?.id ?? '',
                user?.phone ?? '',
                row?.type ?? '',
                row?.direction ?? '',
                row?.balanceSource ?? '',
                row?.amount ?? '',
                row?.currency ?? 'KZT',
                (row?.note ?? '').toString().replace(/[\r\n,]+/g, ' ').trim(),
                row?.orderId ?? '',
                row?.topupRequestId ?? '',
                row?.payoutRequestId ?? '',
            ];
            lines.push(cols.join(','));
        }
        return lines.join('\n');
    }

    async approvePayout(id: string) {
        const payout = await this.prisma.payoutRequest.findUnique({
            where: { id },
            select: {
                id: true,
                walletId: true,
                amount: true,
                currency: true,
                status: true,
            },
        });
        if (!payout) throw new NotFoundException('Payout not found');
        if (payout.status !== 'PENDING') {
            throw new BadRequestException(`Payout already ${payout.status.toLowerCase()}`);
        }
        if (await this.resolvePayoutRefundSource(this.prisma, id) === 'BONUS') throw new BadRequestException('Бонусы не выводятся. Отклоните заявку, чтобы вернуть бонусы.');
        const updated = await this.prisma.payoutRequest.update({
            where: { id },
            data: { status: 'APPROVED' },
        });
        this.realtimeService.publish({
            type: 'finance.payout.approved',
            entity: 'system',
            entityId: id,
            at: new Date().toISOString(),
            payload: { amount: updated.amount, walletId: updated.walletId },
        });
        return updated;
    }

    async rejectPayout(id: string) {
        const payout = await this.prisma.payoutRequest.findUnique({
            where: { id },
            select: {
                id: true,
                walletId: true,
                amount: true,
                currency: true,
                status: true,
            },
        });
        if (!payout) throw new NotFoundException('Payout not found');
        if (payout.status !== 'PENDING') {
            throw new BadRequestException(`Payout already ${payout.status.toLowerCase()}`);
        }
        let payoutSource: 'MONEY' | 'BONUS' = 'MONEY';

        await this.prisma.$transaction(async (tx) => {
            const current = await tx.payoutRequest.findUnique({
                where: { id },
                select: {
                    id: true,
                    status: true,
                },
            });
            if (!current) throw new NotFoundException('Payout not found');
            if (current.status !== 'PENDING') {
                throw new BadRequestException(`Payout already ${current.status.toLowerCase()}`);
            }
            payoutSource = await this.resolvePayoutRefundSource(tx, id);
            const refundToBonus = payoutSource === 'BONUS';
            const claimed = await tx.payoutRequest.updateMany({
                where: { id, status: 'PENDING' }, data: { status: 'REJECTED' },
            });
            if (claimed.count !== 1) throw new BadRequestException('Payout already processed');
            await tx.wallet.update({
                where: { id: payout.walletId },
                data: refundToBonus
                    ? { [bonusField(payout.currency)]: { increment: payout.amount } }
                    : { [moneyField(payout.currency)]: { increment: payout.amount } },
            });
            await (tx as any).walletTransaction.create({
                data: {
                    walletId: payout.walletId,
                    type: 'PAYOUT_REJECTED_REFUND',
                    direction: 'CREDIT',
                    balanceSource: payoutSource,
                    amount: payout.amount,
                    currency: payout.currency,
                    payoutRequestId: payout.id,
                    note: 'Admin rejected payout, funds returned',
                },
            }).catch(() => null);
        });
        this.realtimeService.publish({
            type: 'finance.payout.rejected',
            entity: 'system',
            entityId: id,
            at: new Date().toISOString(),
            payload: { amount: payout.amount, currency: payout.currency, walletId: payout.walletId, source: payoutSource },
        });
        return { success: true };
    }

    private async resolvePayoutRefundSource(
        db: { payoutRequest: any; walletTransaction?: any },
        payoutId: string,
    ): Promise<'MONEY' | 'BONUS'> {
        try {
            const payout = await db.payoutRequest.findUnique({
                where: { id: payoutId },
                select: { source: true },
            });
            if (payout?.source === 'BONUS') {
                return 'BONUS';
            }
            if (payout?.source === 'MONEY') {
                return 'MONEY';
            }
        } catch (error) {
            if (!this.isMissingPayoutSourceStorageError(error)) {
                throw error;
            }
        }

        try {
            const walletTransaction = await db.walletTransaction?.findFirst({
                where: {
                    payoutRequestId: payoutId,
                    type: 'PAYOUT_REQUEST_CREATED',
                },
                orderBy: { createdAt: 'desc' },
                select: { balanceSource: true },
            });
            if (walletTransaction?.balanceSource === 'BONUS') {
                return 'BONUS';
            }
        } catch (_) {
            // Fall back to the legacy default when transaction storage is unavailable.
        }

        return 'MONEY';
    }

    private isMissingPayoutSourceStorageError(error: unknown): boolean {
        const message =
            error instanceof Error ? error.message : String(error ?? '');
        return message.includes('PayoutRequest.source') &&
            message.includes('does not exist');
    }

    async getOrders() {
        return this.prisma.order.findMany({
            orderBy: { createdAt: 'desc' },
            include: {
                passenger: { select: adminUserSelect },
                driver: { include: { user: { select: adminUserSelect } } },
                city: true,
            },
            take: 200,
        });
    }

    async getProblemOrders() {
        return this.prisma.order.findMany({
            where: {
                OR: [
                    { status: 'CANCELLED' },
                    {
                        AND: [
                            { status: { in: ['DRIVER_ASSIGNED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED'] } },
                            { updatedAt: { lte: new Date(Date.now() - 30 * 60 * 1000) } },
                        ],
                    },
                ],
            },
            orderBy: { updatedAt: 'desc' },
            include: {
                passenger: { select: adminUserSelect },
                driver: { include: { user: { select: adminUserSelect } } },
                city: true,
            },
            take: 200,
        });
    }

    async getOrderById(id: string) {
        const order = await this.prisma.order.findUnique({
            where: { id },
            include: {
                passenger: { select: adminUserSelect },
                driver: { include: { user: { select: adminUserSelect } } },
                city: true,
            },
        });
        if (!order) throw new NotFoundException('Order not found');
        return order;
    }

    async getOrderEvents(id: string, take = 100) {
        const order = await this.prisma.order.findUnique({
            where: { id },
            select: { id: true },
        });
        if (!order) throw new NotFoundException('Order not found');
        try {
            return await (this.prisma as any).rideEvent.findMany({
                where: { orderId: id },
                orderBy: { createdAt: 'desc' },
                take: Math.max(1, Math.min(500, Number.isFinite(take) ? take : 100)),
            });
        } catch (_) {
            return [];
        }
    }

    async deleteUserSafely(userId: string) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            include: { driverProfile: true, wallet: true },
        });
        if (!user) throw new NotFoundException('User not found');

        const driverId = user.driverProfile?.id;
        const optionalTableNames = [
            'AdminAuditLog',
            'AdminUserRole',
            'Vehicle',
            'Complaint',
            'PromoUsage',
            'RideEvent',
            'WalletTransaction',
        ];
        const availableTables = await this.existingOptionalTables(optionalTableNames);

        const hardDelete = async () => this.prisma.$transaction(async (tx) => {
            const txAny = tx as any;
            const safeDeleteMany = async (
                delegateName: string,
                tableName: string,
                args: Record<string, unknown>,
            ) => {
                if (!availableTables.has(tableName)) return;
                const delegate = txAny[delegateName];
                if (delegate?.deleteMany == null) return;
                await delegate.deleteMany(args);
            };

            const restoreTripSeatsAfterBookingCleanup = async (
                bookings: Array<{ tripId: string; seats: number }>,
            ) => {
                if (bookings.length === 0) return;

                const seatsByTrip = new Map<string, number>();
                for (const booking of bookings) {
                    seatsByTrip.set(
                        booking.tripId,
                        (seatsByTrip.get(booking.tripId) ?? 0) + booking.seats,
                    );
                }

                for (const [tripId, seatsToRestore] of seatsByTrip.entries()) {
                    const trip = await tx.rideSharingTrip.findUnique({
                        where: { id: tripId },
                        select: {
                            id: true,
                            seatsAvailable: true,
                            seatsTotal: true,
                            status: true,
                        },
                    });
                    if (!trip) continue;

                    const nextSeatsAvailable = Math.min(
                        trip.seatsTotal,
                        trip.seatsAvailable + seatsToRestore,
                    );
                    await tx.rideSharingTrip.update({
                        where: { id: tripId },
                        data: {
                            seatsAvailable: nextSeatsAvailable,
                            status: 'OPEN',
                        },
                    });
                }
            };

            await safeDeleteMany('adminAuditLog', 'AdminAuditLog', { where: { adminId: userId } });
            await safeDeleteMany('adminUserRole', 'AdminUserRole', { where: { userId } });
            await tx.refreshToken.deleteMany({ where: { userId } });

            if (driverId) {
                await safeDeleteMany('vehicle', 'Vehicle', { where: { driverId } });
            }

            await safeDeleteMany('complaint', 'Complaint', {
                where: {
                    OR: [
                        { userId },
                        ...(driverId ? [{ driverId }] : []),
                    ],
                },
            });

            const ordersToDelete = await tx.order.findMany({
                where: {
                    OR: [
                        { passengerId: userId },
                        ...(driverId ? [{ driverId }] : []),
                    ],
                },
                select: { id: true },
            });
            const orderIds = ordersToDelete.map((o) => o.id);
            if (orderIds.length > 0) {
                await safeDeleteMany('promoUsage', 'PromoUsage', {
                    where: { orderId: { in: orderIds } },
                });
                await safeDeleteMany('rideEvent', 'RideEvent', {
                    where: { orderId: { in: orderIds } },
                });
                await tx.order.deleteMany({
                    where: { id: { in: orderIds } },
                });
            }

            await safeDeleteMany('promoUsage', 'PromoUsage', { where: { userId } });

            const passengerIntercityRequestIds = (
                await tx.intercityRequest.findMany({
                    where: { passengerId: userId },
                    select: { id: true },
                })
            ).map((request) => request.id);

            const driverIntercityOffers = await tx.intercityOffer.findMany({
                where: { driverId: userId },
                select: { id: true },
            });
            const driverIntercityOfferIds = driverIntercityOffers.map((offer) => offer.id);

            if (passengerIntercityRequestIds.length > 0) {
                await tx.intercityOffer.deleteMany({
                    where: { requestId: { in: passengerIntercityRequestIds } },
                });
                await tx.intercityRequest.deleteMany({
                    where: { id: { in: passengerIntercityRequestIds } },
                });
            }

            if (driverIntercityOfferIds.length > 0) {
                await tx.intercityRequest.updateMany({
                    where: {
                        OR: [
                            { selectedDriverId: userId },
                            { selectedOfferId: { in: driverIntercityOfferIds } },
                        ],
                    },
                    data: {
                        status: 'OPEN',
                        selectedOfferId: null,
                        selectedDriverId: null,
                        acceptedAt: null,
                    },
                });
                await tx.intercityOffer.deleteMany({
                    where: { id: { in: driverIntercityOfferIds } },
                });
            }

            const passengerBookings = await tx.rideSharingBooking.findMany({
                where: { passengerId: userId },
                select: { id: true, tripId: true, seats: true },
            });
            if (passengerBookings.length > 0) {
                await restoreTripSeatsAfterBookingCleanup(
                    passengerBookings.map((booking) => ({
                        tripId: booking.tripId,
                        seats: booking.seats,
                    })),
                );
                await tx.rideSharingBooking.deleteMany({
                    where: { id: { in: passengerBookings.map((booking) => booking.id) } },
                });
            }

            const driverTripIds = (
                await tx.rideSharingTrip.findMany({
                    where: { driverId: userId },
                    select: { id: true },
                })
            ).map((trip) => trip.id);
            if (driverTripIds.length > 0) {
                await tx.rideSharingBooking.deleteMany({
                    where: { tripId: { in: driverTripIds } },
                });
                await tx.rideSharingTrip.deleteMany({
                    where: { id: { in: driverTripIds } },
                });
            }

            if (driverId) {
                await tx.driverOnline.deleteMany({ where: { driverId } });
                await tx.driverRating.deleteMany({ where: { driverId } });
                await tx.driverPriorityFlags.deleteMany({ where: { driverId } });
                await tx.driverServiceStats.deleteMany({ where: { driverId } });
                await tx.driverPartnerFuelBonus.deleteMany({ where: { driverId } });
                await tx.driverProfile.deleteMany({ where: { id: driverId } });
            }

            if (user.wallet) {
                await tx.topupRequest.deleteMany({ where: { walletId: user.wallet.id } });
                await tx.payoutRequest.deleteMany({ where: { walletId: user.wallet.id } });
                await safeDeleteMany('walletTransaction', 'WalletTransaction', {
                    where: { walletId: user.wallet.id },
                });
                await tx.wallet.deleteMany({ where: { id: user.wallet.id } });
            }

            await tx.user.delete({ where: { id: userId } });

            return { success: true, mode: 'deleted' };
        });

        const anonymizeQaUser = async () => this.prisma.$transaction(async (tx) => {
            const deletedSuffix = `${Date.now()}_${userId.slice(0, 8)}`;
            const deletedPhone = `deleted_${deletedSuffix}`;
            const deletedRefCode = `DEL_${userId.replace(/-/g, '').slice(0, 20)}`;

            await tx.refreshToken.deleteMany({ where: { userId } });

            if (driverId) {
                await tx.driverOnline.updateMany({
                    where: { driverId },
                    data: { isOnline: false },
                });
                await tx.driverProfile.updateMany({
                    where: { id: driverId },
                    data: {
                        status: 'DELETED',
                        carModel: null,
                        carNumber: `DELETED-${userId.slice(0, 8)}`,
                    },
                });
            }

            if (user.wallet) {
                await tx.wallet.updateMany({
                    where: { id: user.wallet.id },
                    data: { money: 0, bonus: 0, moneyRub: 0, bonusRub: 0 },
                });
            }

            await tx.user.update({
                where: { id: userId },
                data: {
                    phone: deletedPhone,
                    name: `DELETED_QA_${userId.slice(0, 8)}`,
                    refCode: deletedRefCode,
                    refLink: `deleted://${userId}`,
                    pushToken: null,
                    pushPlatform: null,
                    pushTokenUpdatedAt: null,
                    cityId: null,
                    referredBy: null,
                },
            });

            return { success: true, mode: 'anonymized' };
        });

        try {
            return await hardDelete();
        } catch (error: any) {
            const isQaUser = user.name.startsWith('QA_TEST_');
            if (!isQaUser) {
                throw error;
            }
            this.logger.warn(
                `Hard delete failed for QA user ${userId}; falling back to anonymization: ${error?.message?.toString?.() ?? error}`,
            );
            return anonymizeQaUser();
        }
    }

    async adminUpdateOrder(
        id: string,
        data: {
            status?: string;
            price?: number;
            commissionAmount?: number;
            assignedReasonJson?: string;
            reason?: string;
            allowUnsafeTransition?: boolean;
        },
    ) {
        const order = await this.prisma.order.findUnique({ where: { id } });
        if (!order) throw new NotFoundException('Order not found');
        const payload: any = {};
        if (data.status != null && data.status.trim().length > 0) {
            const targetStatus = data.status.trim().toUpperCase();
            if (!this.isKnownOrderStatus(targetStatus)) {
                throw new BadRequestException(`Unsupported status: ${targetStatus}`);
            }
            this.assertAdminTransition(order.status, targetStatus, data.allowUnsafeTransition === true);
            payload.status = targetStatus;
            if (payload.status === 'COMPLETED') {
                payload.completedAt = new Date();
            }
        }
        if (typeof data.price === 'number' && Number.isFinite(data.price) && data.price >= 0) {
            payload.price = data.price;
        }
        if (
            typeof data.commissionAmount === 'number' &&
            Number.isFinite(data.commissionAmount) &&
            data.commissionAmount >= 0
        ) {
            payload.commissionAmount = data.commissionAmount;
        }
        if (data.assignedReasonJson != null) {
            payload.assignedReasonJson = data.assignedReasonJson;
        }
        if (Object.keys(payload).length === 0) {
            throw new NotFoundException('No valid fields to update');
        }
        const updated = await this.prisma.order.update({
            where: { id },
            data: payload,
        });
        if (payload.status && payload.status !== order.status) {
            try {
                await (this.prisma as any).rideEvent.create({
                    data: {
                        orderId: order.id,
                        fromStatus: order.status,
                        toStatus: payload.status,
                        actorRole: 'ADMIN',
                        source: 'ADMIN_PANEL',
                        reason: data.reason ?? 'Manual admin status update',
                        payload: {
                            price: payload.price ?? null,
                            commissionAmount: payload.commissionAmount ?? null,
                        },
                    },
                });
            } catch (_) {
                // Keep admin update resilient before ride_events migration is applied.
            }
        }
        if (payload.status && payload.status !== order.status) {
            this.realtimeService.publish({
                type: 'order.status.changed',
                entity: 'order',
                entityId: order.id,
                at: new Date().toISOString(),
                payload: {
                    fromStatus: order.status,
                    toStatus: payload.status,
                    actorRole: 'ADMIN',
                },
            });
        }
        return updated;
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

    private assertAdminTransition(currentRaw: string, targetRaw: string, allowUnsafeTransition: boolean) {
        const current = (currentRaw || '').toUpperCase();
        const target = (targetRaw || '').toUpperCase();
        if (current === target) return;
        if (allowUnsafeTransition) return;
        const allowed: Record<string, Set<string>> = {
            CREATED: new Set(['SEARCHING_DRIVER', 'CANCELLED']),
            SEARCHING_DRIVER: new Set(['DRIVER_ASSIGNED', 'DRIVER_EN_ROUTE', 'CANCELLED']),
            DRIVER_ASSIGNED: new Set(['DRIVER_EN_ROUTE', 'CANCELLED']),
            DRIVER_EN_ROUTE: new Set(['DRIVER_ARRIVED', 'IN_PROGRESS', 'CANCELLED']),
            DRIVER_ARRIVED: new Set(['IN_PROGRESS', 'CANCELLED']),
            IN_PROGRESS: new Set(['COMPLETED', 'CANCELLED']),
            COMPLETED: new Set([]),
            CANCELLED: new Set([]),
        };
        const fromSet = allowed[current] ?? new Set<string>();
        if (!fromSet.has(target)) {
            throw new BadRequestException(
                `Unsafe transition ${current} -> ${target}. Set allowUnsafeTransition=true for forced override.`,
            );
        }
    }

    async getFinanceReport(from?: string, to?: string, selectedCurrency?: string) {
        const currency = walletCurrency(selectedCurrency);
        const fromDate = from ? new Date(from) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
        const toDate = to ? new Date(to) : new Date();
        const timeWhere = {
            gte: fromDate,
            lte: toDate,
        };
        const [ordersCompletedCount, completedAgg, commissionAgg, topupAgg, payoutAgg] =
            await Promise.all([
                this.prisma.order.count({
                    where: {
                        status: 'COMPLETED',
                        currency,
                        createdAt: timeWhere,
                    },
                }),
                this.prisma.order.aggregate({
                    where: {
                        status: 'COMPLETED',
                        currency,
                        createdAt: timeWhere,
                    },
                    _sum: { price: true },
                }),
                this.prisma.order.aggregate({
                    where: {
                        status: 'COMPLETED',
                        currency,
                        createdAt: timeWhere,
                    },
                    _sum: { commissionAmount: true },
                }),
                this.prisma.topupRequest.aggregate({
                    where: {
                        status: 'APPROVED',
                        currency,
                        createdAt: timeWhere,
                    },
                    _sum: { amount: true },
                }),
                this.prisma.payoutRequest.aggregate({
                    where: {
                        status: 'APPROVED',
                        currency,
                        createdAt: timeWhere,
                    },
                    _sum: { amount: true },
                }),
            ]);
        return {
            currency,
            from: fromDate.toISOString(),
            to: toDate.toISOString(),
            ordersCompletedCount,
            revenue: completedAgg._sum.price ?? 0,
            commission: commissionAgg._sum.commissionAmount ?? 0,
            topupsApproved: topupAgg._sum.amount ?? 0,
            payoutsApproved: payoutAgg._sum.amount ?? 0,
            netFlow:
                (topupAgg._sum.amount ?? 0) - (payoutAgg._sum.amount ?? 0),
        };
    }

    async exportFinanceReportCsv(from?: string, to?: string, selectedCurrency?: string) {
        const currency = walletCurrency(selectedCurrency);
        const report = await this.getFinanceReport(from, to, currency);
        const fromDate = new Date(report.from);
        const toDate = new Date(report.to);
        const [orders, topups, payouts] = await Promise.all([
            this.prisma.order.findMany({
                where: {
                    status: 'COMPLETED',
                        currency,
                    createdAt: { gte: fromDate, lte: toDate },
                },
                select: {
                    id: true,
                    createdAt: true,
                    price: true,
                    commissionAmount: true,
                    passengerId: true,
                    driverId: true,
                },
                orderBy: { createdAt: 'desc' },
                take: 1000,
            }),
            this.prisma.topupRequest.findMany({
                where: {
                    status: 'APPROVED',
                        currency,
                    createdAt: { gte: fromDate, lte: toDate },
                },
                select: { id: true, createdAt: true, amount: true, walletId: true },
                orderBy: { createdAt: 'desc' },
                take: 1000,
            }),
            this.prisma.payoutRequest.findMany({
                where: {
                    status: 'APPROVED',
                        currency,
                    createdAt: { gte: fromDate, lte: toDate },
                },
                select: { id: true, createdAt: true, amount: true, walletId: true },
                orderBy: { createdAt: 'desc' },
                take: 1000,
            }),
        ]);

        const lines: string[] = [];
        lines.push('section,key,value');
        lines.push(`summary,currency,${currency}`);
        lines.push(`summary,from,${report.from}`);
        lines.push(`summary,to,${report.to}`);
        lines.push(`summary,ordersCompletedCount,${report.ordersCompletedCount}`);
        lines.push(`summary,revenue,${report.revenue}`);
        lines.push(`summary,commission,${report.commission}`);
        lines.push(`summary,topupsApproved,${report.topupsApproved}`);
        lines.push(`summary,payoutsApproved,${report.payoutsApproved}`);
        lines.push(`summary,netFlow,${report.netFlow}`);
        lines.push('');
        lines.push('completed_orders,id,createdAt,price,commissionAmount,passengerId,driverId');
        for (const row of orders) {
            lines.push(
                [
                    'completed_orders',
                    row.id,
                    row.createdAt.toISOString(),
                    row.price,
                    row.commissionAmount ?? 0,
                    row.passengerId,
                    row.driverId ?? '',
                ].join(',')
            );
        }
        lines.push('');
        lines.push('topups,id,createdAt,amount,walletId');
        for (const row of topups) {
            lines.push(['topups', row.id, row.createdAt.toISOString(), row.amount, row.walletId].join(','));
        }
        lines.push('');
        lines.push('payouts,id,createdAt,amount,walletId');
        for (const row of payouts) {
            lines.push(['payouts', row.id, row.createdAt.toISOString(), row.amount, row.walletId].join(','));
        }
        return lines.join('\n');
    }

    async getDashboardKpis() {
        const [
            activeOrders,
            completedOrders,
            cancelledOrders,
            onlineDrivers,
            activeClients24h,
            problemOrders,
            completedAgg,
            commissionAgg,
        ] = await Promise.all([
            this.prisma.order.count({
                where: {
                    status: {
                        in: ['CREATED', 'SEARCHING_DRIVER', 'DRIVER_ASSIGNED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'IN_PROGRESS'],
                    },
                },
            }),
            this.prisma.order.count({ where: { status: 'COMPLETED' } }),
            this.prisma.order.count({ where: { status: 'CANCELLED' } }),
            this.prisma.driverOnline.count({ where: { isOnline: true } }),
            this.prisma.order.findMany({
                where: { createdAt: { gte: new Date(Date.now() - 24 * 60 * 60 * 1000) } },
                select: { passengerId: true },
                distinct: ['passengerId'],
            }),
            this.prisma.order.count({
                where: {
                    OR: [
                        { status: 'CANCELLED' },
                        {
                            AND: [
                                { status: { in: ['DRIVER_ASSIGNED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED'] } },
                                { updatedAt: { lte: new Date(Date.now() - 30 * 60 * 1000) } },
                            ],
                        },
                    ],
                },
            }),
            this.prisma.order.aggregate({
                where: { status: 'COMPLETED', currency: 'KZT' },
                _sum: { price: true },
            }),
            this.prisma.order.aggregate({
                where: { status: 'COMPLETED', currency: 'KZT' },
                _sum: { commissionAmount: true },
            }),
        ]);

        const financeByCurrency = await this.prisma.order.groupBy({ by: ['currency'], where: { status: 'COMPLETED' }, _sum: { price: true, commissionAmount: true } });
        const dispatchJobs = await this.notificationDispatchService.listJobs(500);
        const queued = dispatchJobs.filter((j) => j.status === 'QUEUED').length;
        const running = dispatchJobs.filter((j) => j.status === 'RUNNING').length;
        const done = dispatchJobs.filter((j) => j.status === 'DONE').length;
        const failed = dispatchJobs.filter((j) => j.status === 'FAILED').length;
        const dayAgo = Date.now() - 24 * 60 * 60 * 1000;
        const jobs24h = dispatchJobs.filter((j) => {
            const t = new Date(j.queuedAt).getTime();
            return Number.isFinite(t) && t >= dayAgo;
        });
        const retries24h = jobs24h.filter((j) => (j.retryCount ?? 0) > 0).length;
        const retryDone24h = jobs24h.filter((j) => (j.retryCount ?? 0) > 0 && j.status === 'DONE').length;
        const done24h = jobs24h.filter((j) => j.status === 'DONE').length;
        const failed24h = jobs24h.filter((j) => j.status === 'FAILED').length;
        const completed24h = done24h + failed24h;
        const successRate24h = completed24h > 0 ? (done24h / completed24h) : 1;
        const dispatchDegraded24h = completed24h >= 5 && (failed24h >= 5 || successRate24h < 0.8);

        return {
            activeOrders,
            completedOrders,
            cancelledOrders,
            onlineDrivers,
            activeClients24h: activeClients24h.length,
            problemOrders,
            currency: 'KZT',
            financeByCurrency,
            revenueCompleted: completedAgg._sum.price ?? 0,
            commissionsCompleted: commissionAgg._sum.commissionAmount ?? 0,
            notificationDispatchQueued: queued,
            notificationDispatchRunning: running,
            notificationDispatchDone: done,
            notificationDispatchFailed: failed,
            notificationDispatchTotal: dispatchJobs.length,
            notificationDispatchDone24h: done24h,
            notificationDispatchFailed24h: failed24h,
            notificationDispatchCompleted24h: completed24h,
            notificationDispatchSuccessRate24h: Number(successRate24h.toFixed(4)),
            notificationDispatchDegraded24h: dispatchDegraded24h,
            notificationDispatchRetries24h: retries24h,
            notificationDispatchRetryDone24h: retryDone24h,
        };
    }

    async getCollections() {
        return Prisma.dmmf.datamodel.models
            .map((m) => m.name)
            .sort((a, b) => a.localeCompare(b));
    }

    getCollectionSchema(collection: string) {
        const model = this.resolveModel(collection);
        return {
            collection: model.name,
            dbName: model.dbName ?? null,
            primaryKey: model.primaryKey?.fields ?? ['id'],
            uniqueFields: model.uniqueFields,
            fields: model.fields.map((f) => ({
                name: f.name,
                type: f.type,
                kind: f.kind,
                isRequired: f.isRequired,
                isList: f.isList,
                isId: f.isId,
                isUnique: f.isUnique,
                hasDefaultValue: f.hasDefaultValue,
                relationName: f.relationName ?? null,
                relationFromFields: f.relationFromFields ?? [],
            })),
        };
    }

    async listCollectionItems(collection: string, take = 100, skip = 0) {
        const delegate = this.resolveDelegate(collection);
        const model = this.resolveModel(collection);
        const safeTake = Math.max(1, Math.min(500, Number.isFinite(take) ? take : 100));
        const safeSkip = Math.max(0, Number.isFinite(skip) ? skip : 0);
        const fieldNames = new Set(model.fields.map((f) => f.name));
        const orderBy = fieldNames.has('createdAt')
            ? { createdAt: 'desc' }
            : fieldNames.has('updatedAt')
                ? { updatedAt: 'desc' }
                : fieldNames.has('id')
                    ? { id: 'asc' }
                    : undefined;
        try {
            return await delegate.findMany({
                ...(orderBy ? { orderBy } : {}),
                take: safeTake,
                skip: safeSkip,
            });
        } catch (error) {
            if (this.isMissingCollectionStorageError(error, collection)) {
                return [];
            }
            throw error;
        }
    }

    async createCollectionItem(collection: string, data: Record<string, unknown>) {
        const delegate = this.resolveDelegate(collection);
        return delegate.create({ data: this.sanitizePayload(data, false) });
    }

    async updateCollectionItem(collection: string, id: string, data: Record<string, unknown>) {
        const delegate = this.resolveDelegate(collection);
        const where = this.resolveWhereById(collection, id);
        return delegate.update({
            where,
            data: this.sanitizePayload(data, true),
        });
    }

    async deleteCollectionItem(collection: string, id: string) {
        const delegate = this.resolveDelegate(collection);
        const where = this.resolveWhereById(collection, id);
        return delegate.delete({ where });
    }

    private resolveDelegate(collection: string): any {
        const model = this.resolveModel(collection);
        const key = model.name[0].toLowerCase() + model.name.slice(1);
        const delegate = (this.prisma as any)[key];
        if (!delegate) {
            throw new NotFoundException(`Collection not supported: ${collection}`);
        }
        return delegate;
    }

    private resolveModel(collection: string) {
        const model = Prisma.dmmf.datamodel.models.find((m) => m.name === collection);
        if (!model) {
            throw new NotFoundException(`Collection not supported: ${collection}`);
        }
        return model;
    }

    private resolveWhereById(collection: string, id: string): Record<string, unknown> {
        const model = this.resolveModel(collection);
        const preferredUnique = model.fields.find((f) => f.isId)
            ?? model.fields.find((f) => f.name === 'id')
            ?? model.fields.find((f) => f.isUnique);
        if (preferredUnique) {
            return {
                [preferredUnique.name]: this.parseIdByFieldType(id, preferredUnique.type),
            };
        }
        throw new NotFoundException(`Collection ${collection} has no unique id-like field`);
    }

    private parseIdByFieldType(value: string, type: string): unknown {
        if (type === 'Int' || type === 'BigInt') {
            const asInt = Number(value);
            if (!Number.isFinite(asInt)) {
                throw new NotFoundException('Invalid numeric id');
            }
            return type === 'Int' ? Math.trunc(asInt) : BigInt(Math.trunc(asInt));
        }
        if (type === 'Float' || type === 'Decimal') {
            const asNum = Number(value);
            if (!Number.isFinite(asNum)) {
                throw new NotFoundException('Invalid numeric id');
            }
            return asNum;
        }
        if (type === 'Boolean') {
            return value === 'true';
        }
        if (type === 'DateTime') {
            const dt = new Date(value);
            if (Number.isNaN(dt.getTime())) {
                throw new NotFoundException('Invalid datetime id');
            }
            return dt;
        }
        return value;
    }

    private isMissingCollectionStorageError(error: unknown, collection: string): boolean {
        const message = error instanceof Error ? error.message : String(error ?? '');
        if (!message) {
            return false;
        }

        return (
            message.includes(`The table \`${collection}\` does not exist`) ||
            message.includes(`relation "${collection}" does not exist`) ||
            message.includes('does not exist in the current database') ||
            message.includes('does not exist')
        );
    }

    private sanitizePayload(
        data: Record<string, unknown>,
        isUpdate: boolean,
    ): Record<string, unknown> {
        const payload = { ...data };
        delete payload.id;
        delete payload.createdAt;
        delete payload.updatedAt;
        if (isUpdate) {
            // Keep update-specific shape clean for Prisma.
        }
        return payload;
    }

    recordHttpRequest(log: RequestLogItem) {
        this.requestLogs.push(log);
        if (this.requestLogs.length > this.logsLimit) {
            this.requestLogs.splice(0, this.requestLogs.length - this.logsLimit);
        }
        if (log.statusCode >= 500) {
            this.recordError({
                at: log.at,
                source: 'http',
                message: `HTTP ${log.statusCode}`,
                path: log.path,
                method: log.method,
                statusCode: log.statusCode,
            });
        }
    }

    recordError(log: ErrorLogItem) {
        this.errorLogs.push(log);
        if (this.errorLogs.length > this.logsLimit) {
            this.errorLogs.splice(0, this.errorLogs.length - this.logsLimit);
        }
    }

    clearSystemLogs() {
        this.requestLogs.length = 0;
        this.errorLogs.length = 0;
        return { success: true };
    }

    getSystemLogs(type: 'request' | 'error' = 'request', limit = 200) {
        const safeLimit = Math.max(1, Math.min(2000, Number.isFinite(limit) ? limit : 200));
        const source = type === 'error' ? this.errorLogs : this.requestLogs;
        return source.slice(Math.max(0, source.length - safeLimit)).reverse();
    }

    async logAdminAction(log: AdminAuditLogItem) {
        this.auditLogs.push(log);
        if (this.auditLogs.length > this.logsLimit) {
            this.auditLogs.splice(0, this.auditLogs.length - this.logsLimit);
        }
        await (this.prisma as any).adminAuditLog.create({
            data: {
                adminId: log.adminId,
                action: log.action,
                targetType: log.target ?? null,
                targetId: log.details?.['targetId']?.toString() ?? null,
                status: (log.status ?? 'SUCCESS').toUpperCase(),
                details: log.details ? (log.details as Prisma.JsonObject) : Prisma.JsonNull,
                ip: log.ip ?? null,
                userAgent: log.userAgent ?? null,
            },
        }).catch(() => {
            // Keep admin operation flow independent from audit persistence errors.
        });
    }

    async getAuditLogs(
        limit = 200,
        filters?: { adminId?: string; action?: string; from?: string; to?: string; status?: string },
    ) {
        const safeLimit = Math.max(1, Math.min(2000, Number.isFinite(limit) ? limit : 200));
        const where: any = {};
        if (filters?.adminId) where.adminId = filters.adminId;
        if (filters?.action) where.action = { contains: filters.action };
        if (filters?.status) where.status = filters.status.toUpperCase();
        if (filters?.from || filters?.to) {
            where.createdAt = {};
            if (filters.from) where.createdAt.gte = new Date(filters.from);
            if (filters.to) where.createdAt.lte = new Date(filters.to);
        }
        const dbLogs = await (this.prisma as any).adminAuditLog.findMany({
            where,
            orderBy: { createdAt: 'desc' },
            take: safeLimit,
            include: {
                admin: {
                    select: { id: true, name: true, phone: true, role: true },
                },
            },
        }).catch(() => []);
        if (dbLogs.length > 0) {
            return dbLogs;
        }
        return this.auditLogs.slice(Math.max(0, this.auditLogs.length - safeLimit)).reverse();
    }

    async exportAuditLogsCsv(
        limit = 1000,
        filters?: { adminId?: string; action?: string; from?: string; to?: string; status?: string },
    ) {
        const safeLimit = Math.max(1, Math.min(5000, Number.isFinite(limit) ? limit : 1000));
        const where: any = {};
        if (filters?.adminId) where.adminId = filters.adminId;
        if (filters?.action) where.action = { contains: filters.action };
        if (filters?.status) where.status = filters.status.toUpperCase();
        if (filters?.from || filters?.to) {
            where.createdAt = {};
            if (filters.from) where.createdAt.gte = new Date(filters.from);
            if (filters.to) where.createdAt.lte = new Date(filters.to);
        }
        const rows = await (this.prisma as any).adminAuditLog.findMany({
            where,
            orderBy: { createdAt: 'desc' },
            take: safeLimit,
            include: {
                admin: {
                    select: { id: true, name: true, phone: true, role: true },
                },
            },
        }).catch(() => []);

        const esc = (value: unknown) => {
            const text = (value ?? '').toString().replaceAll('"', '""');
            return `"${text}"`;
        };

        const lines: string[] = [];
        lines.push('id,createdAt,adminId,adminName,adminPhone,adminRole,action,status,targetType,targetId,ip,userAgent,detailsJson');
        for (const row of rows) {
            lines.push(
                [
                    esc(row.id),
                    esc(row.createdAt?.toISOString?.() ?? row.createdAt),
                    esc(row.adminId),
                    esc(row.admin?.name ?? ''),
                    esc(row.admin?.phone ?? ''),
                    esc(row.admin?.role ?? ''),
                    esc(row.action),
                    esc(row.status),
                    esc(row.targetType),
                    esc(row.targetId),
                    esc(row.ip),
                    esc(row.userAgent),
                    esc(JSON.stringify(row.details ?? {})),
                ].join(',')
            );
        }
        return lines.join('\n');
    }

    async getSystemHealth() {
        const now = new Date().toISOString();
        const startedAt = this.startedAt.toISOString();
        let db = 'DOWN';
        let dbError: string | null = null;
        try {
            await this.prisma.$queryRaw`SELECT 1`;
            db = 'UP';
        } catch (e: any) {
            dbError = e?.message?.toString() ?? 'DB check failed';
        }
        return {
            status: db === 'UP' ? 'OK' : 'DEGRADED',
            now,
            startedAt,
            uptimeSec: Math.floor(process.uptime()),
            db,
            dbError,
            memoryMb: Math.round(process.memoryUsage().rss / 1024 / 1024),
            node: process.version,
        };
    }

    async bootstrapRbacDefaults(actorAdminId: string) {
        for (const permission of this.defaultPermissions) {
            await (this.prisma as any).adminPermission.upsert({
                where: { key: permission.key },
                update: {
                    module: permission.module,
                    action: permission.action,
                    description: permission.description,
                },
                create: permission,
            });
        }

        const superAdmin = await (this.prisma as any).adminRole.upsert({
            where: { code: 'SUPER_ADMIN' },
            update: { name: 'Super Admin', description: 'Полный доступ', isSystem: true },
            create: {
                code: 'SUPER_ADMIN',
                name: 'Super Admin',
                description: 'Полный доступ',
                isSystem: true,
            },
        });

        const permissions = await (this.prisma as any).adminPermission.findMany({
            select: { id: true },
        });
        for (const permission of permissions) {
            await (this.prisma as any).adminRolePermission.upsert({
                where: {
                    roleId_permissionId: {
                        roleId: superAdmin.id,
                        permissionId: permission.id,
                    },
                },
                update: {},
                create: {
                    roleId: superAdmin.id,
                    permissionId: permission.id,
                },
            });
        }

        const allAdmins = await this.prisma.user.findMany({
            where: { role: 'ADMIN' },
            select: { id: true },
        });
        for (const admin of allAdmins) {
            await (this.prisma as any).adminUserRole.upsert({
                where: {
                    userId_roleId: {
                        userId: admin.id,
                        roleId: superAdmin.id,
                    },
                },
                update: {},
                create: {
                    userId: admin.id,
                    roleId: superAdmin.id,
                },
            });
        }

        await this.logAdminAction({
            at: new Date().toISOString(),
            adminId: actorAdminId,
            role: 'ADMIN',
            action: 'rbac.bootstrap',
            target: 'RBAC',
            details: { assignedAdmins: allAdmins.length },
        });

        return {
            success: true,
            rolesAssigned: allAdmins.length,
            permissions: permissions.length,
        };
    }

    async listPermissions() {
        return (this.prisma as any).adminPermission.findMany({
            orderBy: [{ module: 'asc' }, { action: 'asc' }, { key: 'asc' }],
        });
    }

    async listRoles() {
        return (this.prisma as any).adminRole.findMany({
            orderBy: [{ isSystem: 'desc' }, { code: 'asc' }],
            include: {
                permissions: {
                    include: { permission: true },
                },
                users: {
                    include: {
                        user: {
                            select: { id: true, name: true, phone: true, role: true },
                        },
                    },
                },
            },
        });
    }

    async createRole(data: { code: string; name: string; description?: string }) {
        return (this.prisma as any).adminRole.create({
            data: {
                code: data.code.trim().toUpperCase(),
                name: data.name.trim(),
                description: data.description?.trim() || null,
                isSystem: false,
            },
        });
    }

    async updateRole(roleId: string, data: { name?: string; description?: string }) {
        return (this.prisma as any).adminRole.update({
            where: { id: roleId },
            data: {
                ...(data.name != null ? { name: data.name.trim() } : {}),
                ...(data.description !== undefined ? { description: data.description?.trim() || null } : {}),
            },
        });
    }

    async deleteRole(roleId: string) {
        return this.prisma.$transaction(async (tx) => {
            const txAny = tx as any;
            const role = await txAny.adminRole.findUnique({ where: { id: roleId } });
            if (!role) throw new NotFoundException('Role not found');
            if (role.isSystem) {
                throw new NotFoundException('System role cannot be deleted');
            }
            await txAny.adminRolePermission.deleteMany({ where: { roleId } });
            await txAny.adminUserRole.deleteMany({ where: { roleId } });
            await txAny.adminRole.delete({ where: { id: roleId } });
            return { success: true };
        });
    }

    async setRolePermissions(roleId: string, permissionIds: string[]) {
        const uniqueIds = Array.from(new Set(permissionIds.filter((id) => id.trim().length > 0)));
        return this.prisma.$transaction(async (tx) => {
            const txAny = tx as any;
            await txAny.adminRole.findUniqueOrThrow({ where: { id: roleId } });
            const found = await txAny.adminPermission.findMany({
                where: { id: { in: uniqueIds } },
                select: { id: true },
            });
            const foundSet = new Set(found.map((p) => p.id));
            const validIds = uniqueIds.filter((id) => foundSet.has(id));
            await txAny.adminRolePermission.deleteMany({ where: { roleId } });
            if (validIds.length > 0) {
                await txAny.adminRolePermission.createMany({
                    data: validIds.map((permissionId) => ({ roleId, permissionId })),
                    skipDuplicates: true,
                });
            }
            return { success: true, permissionsAssigned: validIds.length };
        });
    }

    async setAdminRoles(userId: string, roleIds: string[]) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            select: { id: true, role: true },
        });
        if (!user) throw new NotFoundException('Admin user not found');
        if (user.role !== 'ADMIN') throw new NotFoundException('User is not ADMIN');
        const uniqueRoleIds = Array.from(new Set(roleIds.filter((id) => id.trim().length > 0)));
        return this.prisma.$transaction(async (tx) => {
            const txAny = tx as any;
            await txAny.adminUserRole.deleteMany({ where: { userId } });
            if (uniqueRoleIds.length > 0) {
                await txAny.adminUserRole.createMany({
                    data: uniqueRoleIds.map((roleId) => ({ userId, roleId })),
                    skipDuplicates: true,
                });
            }
            return { success: true, rolesAssigned: uniqueRoleIds.length };
        });
    }

    async listAdminUsersWithRoles() {
        return this.prisma.user.findMany({
            where: { role: 'ADMIN' },
            select: {
                id: true,
                name: true,
                phone: true,
                role: true,
                adminRoles: {
                    include: {
                        role: true,
                    },
                },
            },
            orderBy: { createdAt: 'desc' },
        });
    }

    async getAdminPermissions(userId: string) {
        const rows = await (this.prisma as any).adminUserRole.findMany({
            where: { userId },
            include: {
                role: {
                    include: {
                        permissions: {
                            include: { permission: true },
                        },
                    },
                },
            },
        });
        const keys = new Set<string>();
        const roles: string[] = [];
        for (const row of rows) {
            roles.push(row.role.code);
            for (const rp of row.role.permissions) {
                keys.add(rp.permission.key);
            }
        }
        return {
            userId,
            roles,
            permissions: Array.from(keys).sort(),
        };
    }

    async listUsers(params: { take?: number; skip?: number; search?: string; role?: string }) {
        const takeRaw = Number.isFinite(params.take) ? Number(params.take) : 100;
        const skipRaw = Number.isFinite(params.skip) ? Number(params.skip) : 0;
        const take = Math.min(Math.max(takeRaw, 1), 500);
        const skip = Math.max(skipRaw, 0);
        const search = (params.search ?? '').trim();
        const role = (params.role ?? '').trim().toUpperCase();
        const where: Prisma.UserWhereInput = {};
        if (search) {
            where.OR = [
                { id: { contains: search, mode: 'insensitive' } },
                { phone: { contains: search, mode: 'insensitive' } },
                { name: { contains: search, mode: 'insensitive' } },
            ];
        }
        if (role && role !== 'ALL') {
            where.role = role as any;
        }
        const [items, total] = await this.prisma.$transaction([
            this.prisma.user.findMany({
                where,
                orderBy: { createdAt: 'desc' },
                skip,
                take,
                select: {
                    id: true,
                    phone: true,
                    name: true,
                    role: true,
                    cityId: true,
                    createdAt: true,
                    updatedAt: true,
                    city: {
                        select: {
                            id: true,
                            name: true,
                        },
                    },
                },
            }),
            this.prisma.user.count({ where }),
        ]);
        return { items, total, take, skip };
    }

    async adminHasPermission(userId: string, permissionKey: string) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            select: { role: true },
        });
        if (!user || user.role !== 'ADMIN') return false;
        try {
            const roleCount = await (this.prisma as any).adminRole.count();
            if (roleCount === 0) return true;

            const roleRows = await (this.prisma as any).adminUserRole.findMany({
                where: { userId },
                include: {
                    role: {
                        include: {
                            permissions: {
                                include: { permission: true },
                            },
                        },
                    },
                },
            });
            if (roleRows.length === 0) return false;
            if (roleRows.some((row) => row.role.code === 'SUPER_ADMIN')) return true;
            return roleRows.some((row) =>
                row.role.permissions.some((rp) => rp.permission.key === permissionKey)
            );
        } catch {
            // Legacy mode when RBAC tables are not migrated yet.
            return true;
        }
    }

    async getSystemOverview() {
        const [users, drivers, orders, cities, topupsPending, payoutsPending] = await Promise.all([
            this.prisma.user.count(),
            this.prisma.driverProfile.count(),
            this.prisma.order.count(),
            this.prisma.city.count(),
            this.prisma.topupRequest.count({ where: { status: 'PENDING' } }),
            this.prisma.payoutRequest.count({ where: { status: 'PENDING' } }),
        ]);

        const mem = process.memoryUsage();
        const uptimeSec = Math.floor(process.uptime());
        return {
            now: new Date().toISOString(),
            startedAt: this.startedAt.toISOString(),
            uptimeSec,
            memory: {
                rssMb: Math.round(mem.rss / 1024 / 1024),
                heapUsedMb: Math.round(mem.heapUsed / 1024 / 1024),
                heapTotalMb: Math.round(mem.heapTotal / 1024 / 1024),
            },
            counters: {
                users,
                drivers,
                orders,
                cities,
                topupsPending,
                payoutsPending,
            },
            logs: {
                requests: this.requestLogs.length,
                errors: this.errorLogs.length,
                adminActions: this.auditLogs.length,
            },
            env: {
                nodeEnv: process.env.NODE_ENV ?? 'unknown',
                version: process.version,
                pid: process.pid,
            },
        };
    }
}
