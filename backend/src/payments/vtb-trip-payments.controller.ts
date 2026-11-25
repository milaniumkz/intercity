import { Body, Controller, Get, HttpCode, Param, Post, Query, Redirect, Request, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { VtbTripPaymentsService } from './vtb-trip-payments.service';
@Controller('payments/vtb/trips')
export class VtbTripPaymentsController {
    constructor(private readonly service: VtbTripPaymentsService) {}
    @Post(':kind/:tripId/checkout') @UseGuards(JwtAuthGuard)
    checkout(@Request() req, @Param('kind') kind: string, @Param('tripId') tripId: string) {
        return this.service.checkout(req.user.sub, kind.toUpperCase(), tripId);
    }
    @Get('return') @Redirect()
    async returnToApp(@Query('kind') kind: string, @Query('tripId') tripId: string) {
        return { url: await this.service.returnTarget(kind || '', tripId || ''), statusCode: 302 };
    }
    @Post('callback') @HttpCode(200)
    callback(@Body() _body: any) { void this.service.tick().catch(() => undefined); return { ok: true }; }
    @Get('callback')
    callbackGet() { void this.service.tick().catch(() => undefined); return { ok: true }; }
}
