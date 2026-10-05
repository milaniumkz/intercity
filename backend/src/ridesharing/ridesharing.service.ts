import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { normalizeClientDateTime } from '../common/date-time.util';

@Injectable()
export class RidesharingService {
    constructor(private prisma: PrismaService) { }

    async createTrip(driverId: string, data: {
        fromCity: string;
        toCity: string;
        fromLat: number;
        fromLng: number;
        toLat: number;
        toLng: number;
        seatsTotal: number;
        pricePerSeat: number;
        departureTime: Date | string;
        promoteToTop?: boolean;
    }) {
        if (!Number.isFinite(data.seatsTotal) || data.seatsTotal < 1) {
            throw new BadRequestException('Seats total must be at least 1');
        }
        if (data.seatsTotal > 8) {
            throw new BadRequestException('Seats total is too large');
        }
        if (!Number.isFinite(data.pricePerSeat) || data.pricePerSeat < 0) {
            throw new BadRequestException('Price per seat must be valid');
        }
        const departureTime = normalizeClientDateTime(
            data.departureTime,
            'departureTime',
        );
        const {
            promoteToTop,
            departureTime: _rawDepartureTime,
            ...tripData
        } = data;
        return this.prisma.rideSharingTrip.create({
            data: {
                driverId,
                ...tripData,
                departureTime,
                topUntil: this.resolveTopUntil(
                    departureTime,
                    promoteToTop === true,
                ),
                seatsAvailable: tripData.seatsTotal,
                status: 'OPEN',
            },
        });
    }

    async searchTrips(query: { fromCity?: string; toCity?: string; date?: Date }) {
        const where: any = { status: 'OPEN' };

        if (query.fromCity) {
            where.fromCity = { contains: query.fromCity, mode: 'insensitive' };
        }
        if (query.toCity) {
            where.toCity = { contains: query.toCity, mode: 'insensitive' };
        }
        if (query.date) {
            const startOfDay = new Date(query.date);
            startOfDay.setHours(0, 0, 0, 0);
            const endOfDay = new Date(query.date);
            endOfDay.setHours(23, 59, 59, 999);
            where.departureTime = { gte: startOfDay, lte: endOfDay };
        }

        return this.prisma.rideSharingTrip.findMany({
            where,
            orderBy: [
                { topUntil: 'desc' },
                { departureTime: 'asc' },
                { createdAt: 'desc' },
            ],
        });
    }

    async getDriverTrips(driverId: string) {
        return this.prisma.rideSharingTrip.findMany({
            where: { driverId },
            include: {
                bookings: {
                    orderBy: { createdAt: 'desc' },
                },
            },
            orderBy: [
                { topUntil: 'desc' },
                { createdAt: 'desc' },
            ],
        });
    }

    async promoteTripToTop(driverId: string, tripId: string) {
        const trip = await this.prisma.rideSharingTrip.findFirst({
            where: { id: tripId, driverId },
        });
        if (!trip || trip.status !== 'OPEN') {
            throw new NotFoundException('Поездка не найдена или уже закрыта');
        }

        return this.prisma.rideSharingTrip.update({
            where: { id: tripId },
            data: {
                topUntil: this.resolveTopUntil(trip.departureTime, true),
            },
        });
    }

    private resolveTopUntil(
        departureTime: Date,
        promoteToTop: boolean,
    ) {
        if (!promoteToTop) {
            return null;
        }
        const now = Date.now();
        const oneDayFromNow = now + 24 * 60 * 60 * 1000;
        return new Date(Math.min(oneDayFromNow, departureTime.getTime()));
    }

    async bookTrip(passengerId: string, tripId: string, seats: number) {
        if (!Number.isFinite(seats) || seats < 1) {
            throw new BadRequestException('Seats must be at least 1');
        }
        const trip = await this.prisma.rideSharingTrip.findUnique({
            where: { id: tripId },
        });

        if (!trip || trip.status !== 'OPEN') {
            throw new NotFoundException('Trip not found or not open');
        }

        if (trip.seatsAvailable < seats) {
            throw new BadRequestException('Not enough seats available');
        }

        const booking = await this.prisma.$transaction(async (tx) => {
            const freshTrip = await tx.rideSharingTrip.findUnique({
                where: { id: tripId },
            });
            if (!freshTrip || freshTrip.status !== 'OPEN') {
                throw new NotFoundException('Trip not found or not open');
            }
            if (freshTrip.seatsAvailable < seats) {
                throw new BadRequestException('Not enough seats available');
            }

            const created = await tx.rideSharingBooking.create({
                data: {
                    tripId,
                    passengerId,
                    seats,
                    status: 'CONFIRMED',
                },
            });

            const nextAvailable = freshTrip.seatsAvailable - seats;
            await tx.rideSharingTrip.update({
                where: { id: tripId },
                data: {
                    seatsAvailable: nextAvailable,
                    status: nextAvailable <= 0 ? 'FULL' : freshTrip.status,
                },
            });

            return created;
        });

        return booking;
    }
}
