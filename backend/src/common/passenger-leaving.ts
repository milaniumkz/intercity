import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { PushService } from '../notifications/push.service';

export async function passengerLeaving(prisma: PrismaService, kind: 'CITY' | 'INTERCITY', tripId: string, userId: string, realtime: RealtimeService, push: PushService) {
    const result = await prisma.$transaction(async tx => {
        const trip = kind === 'CITY' ? await tx.order.findUnique({where: {id: tripId}}) : await tx.intercityRequest.findUnique({where: {id: tripId}});
        if (!trip || trip.passengerId !== userId) throw new ForbiddenException('Нет доступа к поездке');
        if (trip.status !== 'DRIVER_ARRIVED') throw new BadRequestException('Сообщить «Выхожу» можно после прибытия водителя');
        const driver = kind === 'CITY' ? await tx.driverProfile.findUnique({where: {id: (trip as any).driverId || ''}}) : await tx.driverProfile.findUnique({where: {userId: (trip as any).selectedDriverId || ''}});
        if (!driver) throw new BadRequestException('Водитель не назначен');
        if (trip.passengerLeavingAt) return {changed: false, driver, at: trip.passengerLeavingAt};
        const at = new Date();
        const changed = kind === 'CITY'
            ? await tx.order.updateMany({where: {id: tripId, status: 'DRIVER_ARRIVED', passengerLeavingAt: null}, data: {passengerLeavingAt: at}})
            : await tx.intercityRequest.updateMany({where: {id: tripId, status: 'DRIVER_ARRIVED', passengerLeavingAt: null}, data: {passengerLeavingAt: at}});
        if (!changed.count) {
            const current = kind === 'CITY' ? await tx.order.findUnique({where: {id: tripId}}) : await tx.intercityRequest.findUnique({where: {id: tripId}});
            if (current?.status !== 'DRIVER_ARRIVED' || !current.passengerLeavingAt) throw new BadRequestException('Статус поездки изменился');
            return {changed: false, driver, at: current.passengerLeavingAt};
        }
        return {changed: true, driver, at};
    });
    if (result.changed) {
        realtime.publish({type: 'driver.passenger.leaving', entity: 'driver', entityId: result.driver.id, at: result.at.toISOString(), payload: {tripId, orderId: tripId, isIntercity: kind === 'INTERCITY', passengerLeavingAt: result.at.toISOString()}});
        void push.sendToUser(result.driver.userId, {title: 'Пассажир выходит', body: 'Пассажир сообщил, что выходит к машине.', data: {type: 'passenger_leaving', orderId: tripId, route: '/driver/home', isIntercity: kind === 'INTERCITY'}}).catch(() => false);
    }
    return {sent: true, passengerLeavingAt: result.at};
}
