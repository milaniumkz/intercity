import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';

export function departureDay(date: Date | string, offset = 300) {
    const at = new Date(date);
    if (!Number.isFinite(at.getTime()) || !Number.isInteger(offset) || offset < -720 || offset > 840) {
        throw new BadRequestException('Не удалось определить дату и часовой пояс отправления');
    }
    return new Date(at.getTime() + offset * 60000).toISOString().slice(0, 10);
}
export const departureCityKey = (name: string) => name.trim().toLocaleLowerCase('ru-RU').replace(/ё/g, 'е').replace(/[‐‑–—-]/g, ' ').replace(/\s+/g, ' ');

/** Serialize all creation paths per account; the comparison is by local calendar day, not time. */
export async function requireNoDuplicateDeparture(tx: any, userId: string, kind: 'PASSENGER' | 'DRIVER', data: {
    fromCity: string; toCity: string; date: Date; offset: number; driverProfileId?: string;
}) {
    if (typeof data.fromCity !== 'string' || typeof data.toCity !== 'string' || data.fromCity.trim().length < 2 || data.toCity.trim().length < 2) throw new BadRequestException('Выберите город отправления и назначения');
    const day = departureDay(data.date, data.offset);
    const users = await tx.$queryRaw`SELECT id FROM "User" WHERE id=${userId} FOR UPDATE`;
    if (users.length !== 1) throw new NotFoundException('Пользователь не найден');
    const window = {gte: new Date(data.date.getTime() - 3 * 86400000), lte: new Date(data.date.getTime() + 3 * 86400000)};
    const same = (row: any, date: Date | string, offset?: number) => date != null &&
        departureCityKey(row.fromCity) === departureCityKey(data.fromCity) &&
        departureCityKey(row.toCity) === departureCityKey(data.toCity) && departureDay(date, offset ?? data.offset) === day;
    let existing: any;
    if (kind === 'PASSENGER') {
        const rows = await tx.intercityRequest.findMany({where:{passengerId:userId, requestType:'INTERCITY', status:{notIn:['COMPLETED','CANCELLED']}, date:window}});
        existing = rows.find(row => same(row, row.date, row.departureOffsetMinutes));
    } else {
        const profileId = data.driverProfileId ?? (await tx.driverProfile.findUnique({where:{userId},select:{id:true}}))?.id;
        const routes = profileId ? await tx.driverIntercityRoute.findMany({where:{driverId:profileId,OR:[{departureAt:window},{departureAt:null}]}}) : [];
        for (const row of routes) {
            if (departureCityKey(row.fromCity) !== departureCityKey(data.fromCity) || departureCityKey(row.toCity) !== departureCityKey(data.toCity)) continue;
            if (row.isActive && row.departureAt && same(row, row.departureAt, row.departureOffsetMinutes)) { existing = row; break; }
            // Disabling a route does not cancel its existing passenger bookings.
            const bookings = await tx.intercityRequest.findMany({where:{reservedRouteId:row.id,reservedSeats:{gt:0},status:{notIn:['COMPLETED','CANCELLED']},date:window}});
            if (bookings.some(booking => departureDay(booking.date,row.departureOffsetMinutes ?? booking.departureOffsetMinutes ?? data.offset) === day)) { existing = row; break; }
        }
        if (!existing) {
            const trips = await tx.rideSharingTrip.findMany({where:{driverId:userId,status:{notIn:['COMPLETED','CANCELLED','CLOSED']},departureTime:window}});
            existing = trips.find(row => same(row, row.departureTime, row.departureOffsetMinutes));
        }
    }
    if (existing) throw new ConflictException({code:'DUPLICATE_INTERCITY_DEPARTURE',
        message:'На этот маршрут и дату уже есть заявка. Выберите другую дату или откройте существующую заявку.',
        existingId:existing.id, departureDate:day});
}
