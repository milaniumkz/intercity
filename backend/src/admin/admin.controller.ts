import { Controller, Get, Post, Body, Param, Patch, Delete, UseGuards, Request, ForbiddenException, Query, BadRequestException } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { AdminService } from './admin.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

@ApiTags('admin')
@Controller('admin')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class AdminController {
    constructor(private adminService: AdminService) { }

    private ensureAdmin(req: any) {
        if (req.user?.role !== 'ADMIN') {
            throw new ForbiddenException('Admin access required');
        }
    }

    private async ensurePermission(req: any, permissionKey: string) {
        this.ensureAdmin(req);
        const ok = await this.adminService.adminHasPermission(req.user?.sub, permissionKey);
        if (!ok) {
            throw new ForbiddenException(`Permission denied: ${permissionKey}`);
        }
    }

    private async trackAction(
        req: any,
        action: string,
        target?: string,
        details?: Record<string, unknown>,
        status: 'SUCCESS' | 'FAILED' = 'SUCCESS',
    ) {
        await this.adminService.logAdminAction({
            at: new Date().toISOString(),
            adminId: req.user?.sub ?? 'unknown',
            role: req.user?.role ?? 'unknown',
            action,
            target,
            details,
            status,
            ip: req.ip,
            userAgent: req.headers?.['user-agent'],
        });
    }

    private async runTracked<T>(
        req: any,
        action: string,
        target: string | undefined,
        details: Record<string, unknown> | undefined,
        run: () => Promise<T>,
    ): Promise<T> {
        try {
            const result = await run();
            await this.trackAction(req, action, target, details, 'SUCCESS');
            return result;
        } catch (error: any) {
            await this.trackAction(
                req,
                action,
                target,
                {
                    ...(details ?? {}),
                    error: error?.message?.toString() ?? 'Unknown error',
                },
                'FAILED',
            );
            throw error;
        }
    }

    private requiredReason(reasonRaw?: string): string {
        const reason = (reasonRaw ?? '').trim();
        if (!reason) {
            throw new BadRequestException('Reason is required for this action');
        }
        return reason;
    }

    @Get('drivers/pending')
    @ApiOperation({ summary: 'Get pending drivers' })
    async getPendingDrivers(@Request() req) {
        await this.ensurePermission(req, 'drivers.view');
        return this.adminService.getPendingDrivers();
    }

    @Post('drivers/:id/approve')
    @ApiOperation({ summary: 'Approve driver' })
    async approveDriver(@Request() req, @Param('id') id: string, @Body() body?: { reason?: string }) {
        await this.ensurePermission(req, 'drivers.manage');
        const reason = this.requiredReason(body?.reason);
        return this.runTracked(
            req,
            'driver.approve',
            `DriverProfile:${id}`,
            { reason },
            () => this.adminService.approveDriver(id),
        );
    }

    @Post('drivers/:id/reject')
    @ApiOperation({ summary: 'Reject driver' })
    async rejectDriver(@Request() req, @Param('id') id: string, @Body() body?: { reason?: string }) {
        await this.ensurePermission(req, 'drivers.manage');
        const reason = this.requiredReason(body?.reason);
        return this.runTracked(
            req,
            'driver.reject',
            `DriverProfile:${id}`,
            { reason },
            () => this.adminService.rejectDriver(id, reason),
        );
    }

    @Post('drivers/:id/flags')
    @ApiOperation({ summary: 'Set driver priority flags' })
    async setDriverFlags(@Request() req, @Param('id') id: string, @Body() body: { hasCheckers: boolean; hasBranding: boolean }) {
        await this.ensurePermission(req, 'drivers.manage');
        await this.trackAction(req, 'driver.flags.set', `DriverProfile:${id}`, {
            hasCheckers: body.hasCheckers,
            hasBranding: body.hasBranding,
        });
        return this.adminService.setDriverFlags(id, body.hasCheckers, body.hasBranding);
    }

    @Post('drivers/:id/fuel-bonus')
    @ApiOperation({ summary: 'Set driver fuel bonus' })
    async setFuelBonus(@Request() req, @Param('id') id: string, @Body() body: { hours: number }) {
        await this.ensurePermission(req, 'drivers.manage');
        await this.trackAction(req, 'driver.fuelBonus.set', `DriverProfile:${id}`, {
            hours: body.hours,
        });
        return this.adminService.setFuelBonus(id, body.hours);
    }

    @Get('drivers/:id/priority')
    @ApiOperation({ summary: 'Get driver priority info' })
    async getDriverPriority(@Request() req, @Param('id') id: string) {
        await this.ensurePermission(req, 'drivers.view');
        return this.adminService.getDriverPriority(id);
    }

    // Cities
    @Get('cities')
    @ApiOperation({ summary: 'Get all cities' })
    async getCities(@Request() req) {
        await this.ensurePermission(req, 'settings.view');
        return this.adminService.getCities();
    }

    @Post('cities')
    @ApiOperation({ summary: 'Create city' })
    async createCity(@Request() req, @Body() body: { name: string; region?: string; lat: number; lng: number }) {
        await this.ensurePermission(req, 'settings.manage');
        await this.trackAction(req, 'city.create', undefined, body as any);
        return this.adminService.createCity(body);
    }

    @Patch('cities/:id')
    @ApiOperation({ summary: 'Update city' })
    async updateCity(@Request() req, @Param('id') id: string, @Body() body: any) {
        await this.ensurePermission(req, 'settings.manage');
        await this.trackAction(req, 'city.update', `City:${id}`, body as any);
        return this.adminService.updateCity(id, body);
    }

    @Post('cities/:id')
    @ApiOperation({ summary: 'Delete city' })
    async deleteCity(@Request() req, @Param('id') id: string) {
        await this.ensurePermission(req, 'settings.manage');
        await this.trackAction(req, 'city.delete', `City:${id}`);
        return this.adminService.deleteCity(id);
    }

    @Delete('cities/:id')
    @ApiOperation({ summary: 'Delete city (DELETE alias)' })
    async deleteCityDelete(@Request() req, @Param('id') id: string) {
        await this.ensurePermission(req, 'settings.manage');
        await this.trackAction(req, 'city.delete', `City:${id}`);
        return this.adminService.deleteCity(id);
    }

    // Tariffs
    @Get('tariffs/city')
    @ApiOperation({ summary: 'Get all city tariffs' })
    async getAllCityTariffs(@Request() req) {
        await this.ensurePermission(req, 'tariffs.view');
        return this.adminService.getAllCityTariffs();
    }

    @Get('tariffs/city/:cityId')
    @ApiOperation({ summary: 'Get city tariffs' })
    async getCityTariffs(@Request() req, @Param('cityId') cityId: string) {
        await this.ensurePermission(req, 'tariffs.view');
        return this.adminService.getCityTariffs(cityId);
    }

    @Post('tariffs/city')
    @ApiOperation({ summary: 'Create city tariff' })
    async createCityTariff(@Request() req, @Body() body: any) {
        await this.ensurePermission(req, 'tariffs.manage');
        await this.trackAction(req, 'tariff.city.create', undefined, body as any);
        return this.adminService.createCityTariff(body);
    }

    @Patch('tariffs/city/:id')
    @ApiOperation({ summary: 'Update city tariff' })
    async updateCityTariff(@Request() req, @Param('id') id: string, @Body() body: any) {
        await this.ensurePermission(req, 'tariffs.manage');
        await this.trackAction(req, 'tariff.city.update', `TariffCity:${id}`, body as any);
        return this.adminService.updateCityTariff(id, body);
    }

    @Delete('tariffs/city/:id')
    @ApiOperation({ summary: 'Delete city tariff' })
    async deleteCityTariff(@Request() req, @Param('id') id: string) {
        await this.ensurePermission(req, 'tariffs.manage');
        await this.trackAction(req, 'tariff.city.delete', `TariffCity:${id}`);
        return this.adminService.deleteCityTariff(id);
    }

    @Get('tariffs/cargo')
    @ApiOperation({ summary: 'Get cargo tariffs' })
    async getCargoTariffs(@Request() req) {
        await this.ensurePermission(req, 'tariffs.view');
        return this.adminService.getCargoTariffs();
    }

    @Post('tariffs/cargo')
    @ApiOperation({ summary: 'Create cargo tariff' })
    async createCargoTariff(@Request() req, @Body() body: any) {
        await this.ensurePermission(req, 'tariffs.manage');
        await this.trackAction(req, 'tariff.cargo.create', undefined, body as any);
        return this.adminService.createCargoTariff(body);
    }

    @Patch('tariffs/cargo/:id')
    @ApiOperation({ summary: 'Update cargo tariff' })
    async updateCargoTariff(@Request() req, @Param('id') id: string, @Body() body: any) {
        await this.ensurePermission(req, 'tariffs.manage');
        await this.trackAction(req, 'tariff.cargo.update', `TariffCargo:${id}`, body as any);
        return this.adminService.updateCargoTariff(id, body);
    }

    @Delete('tariffs/cargo/:id')
    @ApiOperation({ summary: 'Delete cargo tariff' })
    async deleteCargoTariff(@Request() req, @Param('id') id: string) {
        await this.ensurePermission(req, 'tariffs.manage');
        await this.trackAction(req, 'tariff.cargo.delete', `TariffCargo:${id}`);
        return this.adminService.deleteCargoTariff(id);
    }

    @Get('tariffs/delivery')
    @ApiOperation({ summary: 'Get delivery tariffs' })
    async getDeliveryTariffs(@Request() req) {
        await this.ensurePermission(req, 'tariffs.view');
        return this.adminService.getDeliveryTariffs();
    }

    @Post('tariffs/delivery')
    @ApiOperation({ summary: 'Create delivery tariff' })
    async createDeliveryTariff(@Request() req, @Body() body: any) {
        await this.ensurePermission(req, 'tariffs.manage');
        await this.trackAction(req, 'tariff.delivery.create', undefined, body as any);
        return this.adminService.createDeliveryTariff(body);
    }

    @Patch('tariffs/delivery/:id')
    @ApiOperation({ summary: 'Update delivery tariff' })
    async updateDeliveryTariff(@Request() req, @Param('id') id: string, @Body() body: any) {
        await this.ensurePermission(req, 'tariffs.manage');
        await this.trackAction(req, 'tariff.delivery.update', `TariffDelivery:${id}`, body as any);
        return this.adminService.updateDeliveryTariff(id, body);
    }

    @Delete('tariffs/delivery/:id')
    @ApiOperation({ summary: 'Delete delivery tariff' })
    async deleteDeliveryTariff(@Request() req, @Param('id') id: string) {
        await this.ensurePermission(req, 'tariffs.manage');
        await this.trackAction(req, 'tariff.delivery.delete', `TariffDelivery:${id}`);
        return this.adminService.deleteDeliveryTariff(id);
    }

    @Get('vehicles')
    @ApiOperation({ summary: 'Get all vehicles' })
    async getVehicles(@Request() req) {
        await this.ensurePermission(req, 'vehicles.view');
        return this.adminService.getVehicles();
    }

    @Post('vehicles')
    @ApiOperation({ summary: 'Create vehicle' })
    async createVehicle(@Request() req, @Body() body: any) {
        await this.ensurePermission(req, 'vehicles.manage');
        await this.trackAction(req, 'vehicle.create', undefined, body as any);
        return this.adminService.createVehicle(body);
    }

    @Patch('vehicles/:id')
    @ApiOperation({ summary: 'Update vehicle' })
    async updateVehicle(@Request() req, @Param('id') id: string, @Body() body: any) {
        await this.ensurePermission(req, 'vehicles.manage');
        await this.trackAction(req, 'vehicle.update', id, body as any);
        return this.adminService.updateVehicle(id, body);
    }

    @Delete('vehicles/:id')
    @ApiOperation({ summary: 'Delete vehicle' })
    async deleteVehicle(@Request() req, @Param('id') id: string) {
        await this.ensurePermission(req, 'vehicles.manage');
        await this.trackAction(req, 'vehicle.delete', id);
        return this.adminService.deleteVehicle(id);
    }

    @Get('promos')
    @ApiOperation({ summary: 'Get all promo codes' })
    async getPromos(@Request() req) {
        await this.ensurePermission(req, 'promos.view');
        return this.adminService.getPromos();
    }

    @Post('promos')
    @ApiOperation({ summary: 'Create promo code' })
    async createPromo(@Request() req, @Body() body: any) {
        await this.ensurePermission(req, 'promos.manage');
        await this.trackAction(req, 'promo.create', body?.code?.toString(), body as any);
        return this.adminService.createPromo(body);
    }

    @Patch('promos/:id')
    @ApiOperation({ summary: 'Update promo code' })
    async updatePromo(@Request() req, @Param('id') id: string, @Body() body: any) {
        await this.ensurePermission(req, 'promos.manage');
        await this.trackAction(req, 'promo.update', id, body as any);
        return this.adminService.updatePromo(id, body);
    }

    @Delete('promos/:id')
    @ApiOperation({ summary: 'Deactivate promo code' })
    async deletePromo(@Request() req, @Param('id') id: string) {
        await this.ensurePermission(req, 'promos.manage');
        await this.trackAction(req, 'promo.deactivate', id);
        return this.adminService.deletePromo(id);
    }

    @Get('trip-reviews')
    async getTripReviews(@Request() req, @Query('status') status?: string) {
        await this.ensurePermission(req, 'support.view');
        return this.adminService.getTripReviews(status);
    }
    @Patch('trip-reviews/:id')
    async decideTripReview(@Request() req, @Param('id') id: string, @Body() body: any) {
        await this.ensurePermission(req, 'support.manage');
        return this.runTracked(req, 'trip.review', id, {decision:body.decision,note:body.note}, () => this.adminService.decideTripReview(id,body.decision,body.note,req.user.sub));
    }

    @Get('complaints')
    @ApiOperation({ summary: 'Get complaints' })
    async getComplaints(@Request() req, @Query('status') status?: string) {
        await this.ensurePermission(req, 'support.view');
        return this.adminService.getComplaints(status);
    }

    @Post('complaints')
    @ApiOperation({ summary: 'Create complaint' })
    async createComplaint(@Request() req, @Body() body: any) {
        await this.ensurePermission(req, 'support.manage');
        await this.trackAction(req, 'complaint.create', undefined, body as any);
        return this.adminService.createComplaint(body);
    }

    @Patch('complaints/:id')
    @ApiOperation({ summary: 'Update complaint status' })
    async updateComplaint(@Request() req, @Param('id') id: string, @Body() body: any) {
        await this.ensurePermission(req, 'support.manage');
        await this.trackAction(req, 'complaint.update', id, body as any);
        return this.adminService.updateComplaint(id, body);
    }

    @Get('notifications')
    @ApiOperation({ summary: 'Get notification campaigns' })
    async getNotificationCampaigns(@Request() req) {
        await this.ensurePermission(req, 'notifications.view');
        return this.adminService.getNotificationCampaigns();
    }

    @Post('notifications')
    @ApiOperation({ summary: 'Create notification campaign' })
    async createNotificationCampaign(@Request() req, @Body() body: any) {
        await this.ensurePermission(req, 'notifications.manage');
        await this.trackAction(req, 'notification.create', undefined, body as any);
        return this.adminService.createNotificationCampaign(body, req.user?.sub);
    }

    @Patch('notifications/:id')
    @ApiOperation({ summary: 'Update notification campaign' })
    async updateNotificationCampaign(@Request() req, @Param('id') id: string, @Body() body: any) {
        await this.ensurePermission(req, 'notifications.manage');
        await this.trackAction(req, 'notification.update', id, body as any);
        return this.adminService.updateNotificationCampaign(id, body);
    }

    @Post('notifications/:id/send')
    @ApiOperation({ summary: 'Queue notification campaign dispatch with retry' })
    async sendNotificationCampaign(@Request() req, @Param('id') id: string, @Body() body?: { reason?: string }) {
        await this.ensurePermission(req, 'notifications.manage');
        const reason = this.requiredReason(body?.reason);
        return this.runTracked(
            req,
            'notification.dispatch.queue',
            id,
            { reason },
            () => this.adminService.sendNotificationCampaign(id),
        );
    }

    @Get('notifications/jobs/:jobId')
    @ApiOperation({ summary: 'Get notification dispatch job status' })
    async getNotificationDispatchJob(@Request() req, @Param('jobId') jobId: string) {
        await this.ensurePermission(req, 'notifications.view');
        return this.adminService.getNotificationDispatchJob(jobId);
    }

    @Get('notifications/jobs')
    @ApiOperation({ summary: 'List recent notification dispatch jobs' })
    async listNotificationDispatchJobs(@Request() req, @Query('limit') limit?: string) {
        await this.ensurePermission(req, 'notifications.view');
        return this.adminService.listNotificationDispatchJobs(Number.parseInt(limit ?? '', 10));
    }

    @Post('notifications/jobs/:jobId/requeue')
    @ApiOperation({ summary: 'Requeue failed notification dispatch job' })
    async requeueNotificationDispatchJob(
        @Request() req,
        @Param('jobId') jobId: string,
        @Body() body?: { reason?: string },
    ) {
        await this.ensurePermission(req, 'notifications.manage');
        const reason = this.requiredReason(body?.reason);
        return this.runTracked(
            req,
            'notification.dispatch.requeue',
            jobId,
            { reason },
            () => this.adminService.requeueNotificationDispatchJob(jobId),
        );
    }

    @Delete('notifications/:id')
    @ApiOperation({ summary: 'Delete notification campaign' })
    async deleteNotificationCampaign(@Request() req, @Param('id') id: string) {
        await this.ensurePermission(req, 'notifications.manage');
        await this.trackAction(req, 'notification.delete', id);
        return this.adminService.deleteNotificationCampaign(id);
    }

    // Settings
    @Get('settings')
    @ApiOperation({ summary: 'Get settings' })
    async getSettings(@Request() req) {
        await this.ensurePermission(req, 'settings.view');
        return this.adminService.getSettings();
    }

    @Post('settings')
    @ApiOperation({ summary: 'Set setting' })
    async setSetting(@Request() req, @Body() body: { key: string; value: string }) {
        await this.ensurePermission(req, 'settings.manage');
        await this.trackAction(req, 'settings.upsert', `AppSettings:${body.key}`, {
            key: body.key,
            value: body.value,
        });
        return this.adminService.setSetting(body.key, body.value);
    }

    // Topups
    @Get('topups')
    @ApiOperation({ summary: 'Get all topups' })
    async getTopups(@Request() req) {
        await this.ensurePermission(req, 'finance.view');
        return this.adminService.getTopups();
    }

    @Post('topups/:id/approve')
    @ApiOperation({ summary: 'Approve topup' })
    async approveTopup(@Request() req, @Param('id') id: string, @Body() body?: { reason?: string }) {
        await this.ensurePermission(req, 'finance.manage');
        const reason = this.requiredReason(body?.reason);
        return this.runTracked(
            req,
            'topup.approve',
            `TopupRequest:${id}`,
            { reason },
            () => this.adminService.approveTopup(id),
        );
    }

    @Post('topups/:id/reject')
    @ApiOperation({ summary: 'Reject topup' })
    async rejectTopup(@Request() req, @Param('id') id: string, @Body() body?: { reason?: string }) {
        await this.ensurePermission(req, 'finance.manage');
        const reason = this.requiredReason(body?.reason);
        return this.runTracked(
            req,
            'topup.reject',
            `TopupRequest:${id}`,
            { reason },
            () => this.adminService.rejectTopup(id),
        );
    }

    // Payouts
    @Get('payouts')
    @ApiOperation({ summary: 'Get all payouts' })
    async getPayouts(@Request() req) {
        await this.ensurePermission(req, 'finance.view');
        return this.adminService.getPayouts();
    }

    @Get('wallet-transactions')
    @ApiOperation({ summary: 'Get wallet transactions for finance audit' })
    async getWalletTransactions(
        @Request() req,
        @Query('take') take?: string,
        @Query('skip') skip?: string,
        @Query('walletId') walletId?: string,
        @Query('userId') userId?: string,
        @Query('type') type?: string,
        @Query('source') source?: string,
        @Query('from') from?: string,
        @Query('to') to?: string,
    ) {
        await this.ensurePermission(req, 'finance.view');
        return this.adminService.getWalletTransactions({
            take: Number.parseInt(take ?? '', 10),
            skip: Number.parseInt(skip ?? '', 10),
            walletId,
            userId,
            type,
            source,
            from,
            to,
        });
    }

    @Get('reports/wallet-transactions/csv')
    @ApiOperation({ summary: 'Wallet transactions CSV export' })
    async exportWalletTransactionsCsv(
        @Request() req,
        @Query('walletId') walletId?: string,
        @Query('userId') userId?: string,
        @Query('type') type?: string,
        @Query('source') source?: string,
        @Query('from') from?: string,
        @Query('to') to?: string,
    ) {
        await this.ensurePermission(req, 'finance.view');
        await this.trackAction(req, 'wallet.transactions.export.csv', 'wallet-transactions-report', {
            walletId,
            userId,
            type,
            source,
            from,
            to,
        });
        return {
            filename: `wallet-transactions-${new Date().toISOString().slice(0, 10)}.csv`,
            contentType: 'text/csv; charset=utf-8',
            csv: await this.adminService.exportWalletTransactionsCsv({
                walletId,
                userId,
                type,
                source,
                from,
                to,
            }),
        };
    }

    @Post('payouts/:id/approve')
    @ApiOperation({ summary: 'Approve payout' })
    async approvePayout(@Request() req, @Param('id') id: string, @Body() body?: { reason?: string }) {
        await this.ensurePermission(req, 'finance.manage');
        const reason = this.requiredReason(body?.reason);
        return this.runTracked(
            req,
            'payout.approve',
            `PayoutRequest:${id}`,
            { reason },
            () => this.adminService.approvePayout(id),
        );
    }

    @Post('payouts/:id/reject')
    @ApiOperation({ summary: 'Reject payout' })
    async rejectPayout(@Request() req, @Param('id') id: string, @Body() body?: { reason?: string }) {
        await this.ensurePermission(req, 'finance.manage');
        const reason = this.requiredReason(body?.reason);
        return this.runTracked(
            req,
            'payout.reject',
            `PayoutRequest:${id}`,
            { reason },
            () => this.adminService.rejectPayout(id),
        );
    }

    @Get('orders')
    @ApiOperation({ summary: 'Get recent orders for admin panel' })
    async getOrders(@Request() req) {
        await this.ensurePermission(req, 'orders.view');
        return this.adminService.getOrders();
    }

    @Get('users')
    @ApiOperation({ summary: 'List users with pagination and search' })
    async getUsers(
        @Request() req,
        @Query('take') take?: string,
        @Query('skip') skip?: string,
        @Query('search') search?: string,
        @Query('role') role?: string,
    ) {
        await this.ensurePermission(req, 'users.view');
        return this.adminService.listUsers({
            take: Number.parseInt(take ?? '', 10),
            skip: Number.parseInt(skip ?? '', 10),
            search: search ?? '',
            role: role ?? '',
        });
    }

    @Delete('users/:id')
    @ApiOperation({ summary: 'Safely delete user with dependent records' })
    async deleteUserSafely(
        @Request() req,
        @Param('id') id: string,
        @Query('reason') reason?: string,
    ) {
        await this.ensurePermission(req, 'users.manage');
        const requiredReason = this.requiredReason(reason);
        return this.runTracked(
            req,
            'user.delete.safe',
            id,
            { reason: requiredReason },
            () => this.adminService.deleteUserSafely(id),
        );
    }

    @Get('orders/problems')
    @ApiOperation({ summary: 'Get problem orders for operations center' })
    async getProblemOrders(@Request() req) {
        await this.ensurePermission(req, 'orders.view');
        return this.adminService.getProblemOrders();
    }

    @Get('orders/:id')
    @ApiOperation({ summary: 'Get order detail by id for admin' })
    async getOrderById(@Request() req, @Param('id') id: string) {
        await this.ensurePermission(req, 'orders.view');
        return this.adminService.getOrderById(id);
    }

    @Get('orders/:id/events')
    @ApiOperation({ summary: 'Get order ride events timeline' })
    async getOrderEvents(
        @Request() req,
        @Param('id') id: string,
        @Query('take') take?: string,
    ) {
        await this.ensurePermission(req, 'orders.view');
        return this.adminService.getOrderEvents(id, Number.parseInt(take ?? '', 10));
    }

    @Patch('orders/:id')
    @ApiOperation({ summary: 'Admin update order (status/price/commission)' })
    async adminUpdateOrder(
        @Request() req,
        @Param('id') id: string,
        @Body()
        body: {
            status?: string;
            price?: number;
            commissionAmount?: number;
            assignedReasonJson?: string;
            reason?: string;
            allowUnsafeTransition?: boolean;
        },
    ) {
        await this.ensurePermission(req, 'orders.manage');
        const reason = this.requiredReason(body?.reason);
        return this.runTracked(
            req,
            'order.admin.update',
            id,
            { ...body, reason } as any,
            () => this.adminService.adminUpdateOrder(id, body),
        );
    }

    @Get('reports/finance')
    @ApiOperation({ summary: 'Finance report for selected date range' })
    async getFinanceReport(
        @Request() req,
        @Query('from') from?: string,
        @Query('to') to?: string,
        @Query('currency') currency?: string,
    ) {
        await this.ensurePermission(req, 'finance.view');
        return this.adminService.getFinanceReport(from, to, currency);
    }

    @Get('reports/finance/csv')
    @ApiOperation({ summary: 'Finance report CSV export (text/csv payload)' })
    async exportFinanceReportCsv(
        @Request() req,
        @Query('from') from?: string,
        @Query('to') to?: string,
        @Query('currency') currency?: string,
    ) {
        await this.ensurePermission(req, 'finance.view');
        await this.trackAction(req, 'finance.report.export.csv', 'finance-report', { from, to });
        return {
            filename: `finance-report-${new Date().toISOString().slice(0, 10)}.csv`,
            contentType: 'text/csv; charset=utf-8',
            csv: await this.adminService.exportFinanceReportCsv(from, to, currency),
        };
    }

    @Get('dashboard/kpis')
    @ApiOperation({ summary: 'Get dashboard KPI metrics for admin panel' })
    async getDashboardKpis(@Request() req) {
        await this.ensurePermission(req, 'dashboard.view');
        return this.adminService.getDashboardKpis();
    }

    @Get('collections')
    @ApiOperation({ summary: 'List manageable DB collections' })
    async getCollections(@Request() req) {
        await this.ensurePermission(req, 'collections.view');
        return this.adminService.getCollections();
    }

    @Get('collections/:collection/schema')
    @ApiOperation({ summary: 'Get DB collection schema' })
    async getCollectionSchema(
        @Request() req,
        @Param('collection') collection: string,
    ) {
        await this.ensurePermission(req, 'collections.view');
        return this.adminService.getCollectionSchema(collection);
    }

    @Get('collections/:collection')
    @ApiOperation({ summary: 'List items in a DB collection' })
    async listCollectionItems(
        @Request() req,
        @Param('collection') collection: string,
        @Query('take') take?: string,
        @Query('skip') skip?: string,
    ) {
        await this.ensurePermission(req, 'collections.view');
        return this.adminService.listCollectionItems(
            collection,
            take ? parseInt(take, 10) : undefined,
            skip ? parseInt(skip, 10) : undefined,
        );
    }

    @Post('collections/:collection')
    @ApiOperation({ summary: 'Create item in a DB collection' })
    async createCollectionItem(
        @Request() req,
        @Param('collection') collection: string,
        @Body() body: Record<string, unknown>,
    ) {
        await this.ensurePermission(req, 'collections.manage');
        await this.trackAction(req, 'collection.create', collection, body);
        return this.adminService.createCollectionItem(collection, body);
    }

    @Patch('collections/:collection/:id')
    @ApiOperation({ summary: 'Update item in a DB collection' })
    async updateCollectionItem(
        @Request() req,
        @Param('collection') collection: string,
        @Param('id') id: string,
        @Body() body: Record<string, unknown>,
    ) {
        await this.ensurePermission(req, 'collections.manage');
        await this.trackAction(req, 'collection.update', `${collection}:${id}`, body);
        return this.adminService.updateCollectionItem(collection, id, body);
    }

    @Delete('collections/:collection/:id')
    @ApiOperation({ summary: 'Delete item from a DB collection' })
    async deleteCollectionItem(
        @Request() req,
        @Param('collection') collection: string,
        @Param('id') id: string,
    ) {
        await this.ensurePermission(req, 'collections.manage');
        await this.trackAction(req, 'collection.delete', `${collection}:${id}`);
        return this.adminService.deleteCollectionItem(collection, id);
    }

    @Get('system/overview')
    @ApiOperation({ summary: 'Get system overview for admin panel' })
    async getSystemOverview(@Request() req) {
        await this.ensurePermission(req, 'system.view');
        return this.adminService.getSystemOverview();
    }

    @Get('system/health')
    @ApiOperation({ summary: 'Get backend health status for operations center' })
    async getSystemHealth(@Request() req) {
        await this.ensurePermission(req, 'system.view');
        return this.adminService.getSystemHealth();
    }

    @Get('system/logs')
    @ApiOperation({ summary: 'Get recent in-memory system logs' })
    async getSystemLogs(
        @Request() req,
        @Query('type') type?: string,
        @Query('limit') limit?: string,
    ) {
        await this.ensurePermission(req, 'system.view');
        const normalized = type === 'error' ? 'error' : 'request';
        return this.adminService.getSystemLogs(
            normalized,
            limit ? parseInt(limit, 10) : undefined,
        );
    }

    @Post('system/logs/clear')
    @ApiOperation({ summary: 'Clear in-memory system logs' })
    async clearSystemLogs(@Request() req) {
        await this.ensurePermission(req, 'system.manage');
        await this.trackAction(req, 'system.logs.clear');
        return this.adminService.clearSystemLogs();
    }

    @Get('audit-logs')
    @ApiOperation({ summary: 'Get admin audit logs' })
    async getAuditLogs(
        @Request() req,
        @Query('limit') limit?: string,
        @Query('adminId') adminId?: string,
        @Query('action') action?: string,
        @Query('from') from?: string,
        @Query('to') to?: string,
        @Query('status') status?: string,
    ) {
        await this.ensurePermission(req, 'system.view');
        return this.adminService.getAuditLogs(limit ? parseInt(limit, 10) : undefined, {
            adminId,
            action,
            from,
            to,
            status,
        });
    }

    @Get('audit-logs/csv')
    @ApiOperation({ summary: 'Export admin audit logs to CSV' })
    async exportAuditLogsCsv(
        @Request() req,
        @Query('limit') limit?: string,
        @Query('adminId') adminId?: string,
        @Query('action') action?: string,
        @Query('from') from?: string,
        @Query('to') to?: string,
        @Query('status') status?: string,
    ) {
        await this.ensurePermission(req, 'system.view');
        await this.trackAction(req, 'audit.export.csv', 'audit-logs', {
            limit,
            adminId,
            action,
            from,
            to,
            status,
        });
        return {
            filename: `audit-logs-${new Date().toISOString().slice(0, 10)}.csv`,
            contentType: 'text/csv; charset=utf-8',
            csv: await this.adminService.exportAuditLogsCsv(
                limit ? parseInt(limit, 10) : undefined,
                { adminId, action, from, to, status },
            ),
        };
    }

    @Post('rbac/bootstrap')
    @ApiOperation({ summary: 'Bootstrap default RBAC roles and permissions' })
    async bootstrapRbac(@Request() req) {
        await this.ensurePermission(req, 'rbac.manage');
        return this.adminService.bootstrapRbacDefaults(req.user?.sub);
    }

    @Get('rbac/permissions')
    @ApiOperation({ summary: 'List all admin permissions' })
    async getRbacPermissions(@Request() req) {
        await this.ensurePermission(req, 'rbac.view');
        return this.adminService.listPermissions();
    }

    @Get('rbac/roles')
    @ApiOperation({ summary: 'List all admin roles with assignments' })
    async getRbacRoles(@Request() req) {
        await this.ensurePermission(req, 'rbac.view');
        return this.adminService.listRoles();
    }

    @Post('rbac/roles')
    @ApiOperation({ summary: 'Create custom admin role' })
    async createRbacRole(
        @Request() req,
        @Body() body: { code: string; name: string; description?: string },
    ) {
        await this.ensurePermission(req, 'rbac.manage');
        await this.trackAction(req, 'rbac.role.create', body.code, body as any);
        return this.adminService.createRole(body);
    }

    @Patch('rbac/roles/:id')
    @ApiOperation({ summary: 'Update custom admin role' })
    async updateRbacRole(
        @Request() req,
        @Param('id') id: string,
        @Body() body: { name?: string; description?: string },
    ) {
        await this.ensurePermission(req, 'rbac.manage');
        await this.trackAction(req, 'rbac.role.update', id, body as any);
        return this.adminService.updateRole(id, body);
    }

    @Delete('rbac/roles/:id')
    @ApiOperation({ summary: 'Delete custom admin role' })
    async deleteRbacRole(@Request() req, @Param('id') id: string) {
        await this.ensurePermission(req, 'rbac.manage');
        await this.trackAction(req, 'rbac.role.delete', id);
        return this.adminService.deleteRole(id);
    }

    @Post('rbac/roles/:id/permissions')
    @ApiOperation({ summary: 'Set role permissions (replace all)' })
    async setRbacRolePermissions(
        @Request() req,
        @Param('id') id: string,
        @Body() body: { permissionIds: string[] },
    ) {
        await this.ensurePermission(req, 'rbac.manage');
        await this.trackAction(req, 'rbac.role.permissions.set', id, {
            count: Array.isArray(body.permissionIds) ? body.permissionIds.length : 0,
        });
        return this.adminService.setRolePermissions(id, body.permissionIds ?? []);
    }

    @Get('rbac/admins')
    @ApiOperation({ summary: 'List admin users with assigned RBAC roles' })
    async getRbacAdmins(@Request() req) {
        await this.ensurePermission(req, 'rbac.view');
        return this.adminService.listAdminUsersWithRoles();
    }

    @Post('rbac/admins/:userId/roles')
    @ApiOperation({ summary: 'Set RBAC roles for admin user (replace all)' })
    async setRbacAdminRoles(
        @Request() req,
        @Param('userId') userId: string,
        @Body() body: { roleIds: string[] },
    ) {
        await this.ensurePermission(req, 'rbac.manage');
        await this.trackAction(req, 'rbac.admin.roles.set', userId, {
            count: Array.isArray(body.roleIds) ? body.roleIds.length : 0,
        });
        return this.adminService.setAdminRoles(userId, body.roleIds ?? []);
    }

    @Get('rbac/my-permissions')
    @ApiOperation({ summary: 'Get current admin roles and permissions' })
    async getMyRbacPermissions(@Request() req) {
        this.ensureAdmin(req);
        return this.adminService.getAdminPermissions(req.user?.sub);
    }
}
