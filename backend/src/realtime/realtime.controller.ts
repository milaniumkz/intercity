import { Controller, Get, MessageEvent, Param, Query, Request, Sse, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { filter, interval, map, merge, Observable } from 'rxjs';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { OrdersService } from '../orders/orders.service';
import { DriverService } from '../driver/driver.service';
import { RealtimeService } from './realtime.service';

@ApiTags('realtime')
@Controller('realtime')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class RealtimeController {
    constructor(
        private readonly realtimeService: RealtimeService,
        private readonly ordersService: OrdersService,
        private readonly driverService: DriverService,
    ) { }

    @Get('health')
    @ApiOperation({ summary: 'Realtime module health check' })
    health() {
        return { ok: true, transport: 'sse' };
    }

    @Sse('orders/:id/stream')
    @ApiOperation({ summary: 'SSE stream for order events' })
    async orderStream(
        @Request() req: any,
        @Param('id') orderId: string,
    ): Promise<Observable<MessageEvent>> {
        await this.ordersService.getOrder(orderId, {
            userId: req.user?.sub,
            role: req.user?.role,
        });
        const heartbeat$ = interval(15000).pipe(
            map(() => ({
                type: 'heartbeat',
                data: { at: new Date().toISOString(), orderId },
            })),
        );
        const orderEvents$ = this.realtimeService.stream().pipe(
            filter((event) => event.entity === 'order' && event.entityId === orderId),
            map((event) => ({ type: 'order-event', data: event })),
        );
        return merge(heartbeat$, orderEvents$);
    }

    @Sse('driver/me/stream')
    @ApiOperation({ summary: 'SSE stream for current driver updates' })
    async driverMeStream(@Request() req: any): Promise<Observable<MessageEvent>> {
        const profile = await this.driverService.getMyProfile(req.user?.sub);
        const driverId = profile?.id;
        const userId = req.user?.sub;
        const heartbeat$ = interval(15000).pipe(
            map(() => ({
                type: 'heartbeat',
                data: { at: new Date().toISOString(), driverId: driverId ?? null },
            })),
        );
        const relatedEvents$ = this.realtimeService.stream().pipe(
            filter((event) => event.entity === 'driver' && event.entityId === driverId),
            map((event) => ({ type: 'driver-event', data: event })),
        );
        const orderEvents$ = this.realtimeService.stream().pipe(
            filter((event) => event.entity === 'order'),
            filter((event) => {
                const payload = event.payload ?? {};
                const payloadDriverId = payload['driverId']?.toString();
                const payloadDriverUserId = payload['driverUserId']?.toString();
                const actorUserId = payload['actorUserId']?.toString();
                return (
                    (driverId != null && payloadDriverId == driverId) ||
                    (userId != null && payloadDriverUserId == userId) ||
                    (userId != null && actorUserId == userId)
                );
            }),
            map((event) => ({ type: 'order-event', data: event })),
        );
        return merge(heartbeat$, relatedEvents$, orderEvents$);
    }

    @Sse('events')
    @ApiOperation({ summary: 'Generic SSE stream with optional entity filters' })
    events(
        @Query('entity') entity?: string,
        @Query('entityId') entityId?: string,
    ): Observable<MessageEvent> {
        const heartbeat$ = interval(15000).pipe(
            map(() => ({
                type: 'heartbeat',
                data: { at: new Date().toISOString() },
            })),
        );
        const events$ = this.realtimeService.stream().pipe(
            filter((event) => !entity || event.entity === entity),
            filter((event) => !entityId || event.entityId === entityId),
            map((event) => ({ type: 'event', data: event })),
        );
        return merge(heartbeat$, events$);
    }
}
