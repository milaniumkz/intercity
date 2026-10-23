import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { kazakhstanPeriod, money } from '../tax/kz-social-calculator';

export function earningsMonth(period: string) {
    if (typeof period !== 'string' || !/^20\d{2}-(0[1-9]|1[0-2])$/.test(period)) throw new BadRequestException('Укажите месяц в формате YYYY-MM');
    const [year, month] = period.split('-').map(Number);
    return { start: new Date(`${period}-01T00:00:00+05:00`),
        end: new Date(Date.UTC(year, month, 1, -5)) };
}

@Injectable()
export class DriverEarningsService {
    constructor(private readonly prisma: PrismaService) {}

    async summary(userId: string, period = kazakhstanPeriod(new Date()), currency = 'KZT') {
        const { start, end } = earningsMonth(period);
        if (!['KZT', 'RUB'].includes(currency)) throw new BadRequestException('Выберите KZT или RUB');
        return this.prisma.$transaction(async tx => {
            const driver = await tx.driverProfile.findUnique({ where: { userId }, select: { id: true } });
            if (!driver) throw new NotFoundException('Профиль водителя не найден');
            const dateFilter = { OR: [{ completedAt: { gte: start, lt: end } },
                { completedAt: null, updatedAt: { gte: start, lt: end } }] };
            const [orders, requests, wallet, profile, enabled] = await Promise.all([
                tx.order.findMany({ where: { driverId: driver.id, status: 'COMPLETED', currency, ...dateFilter },
                    select: { id: true, price: true, paymentMethod: true, paidWithBonus: true, completedAt: true } }),
                tx.intercityRequest.findMany({ where: { selectedDriverId: userId, status: 'COMPLETED', currency, ...dateFilter },
                    select: { id: true, price: true, selectedOfferId: true, paymentMethod: true, completedAt: true } }),
                tx.wallet.findUnique({ where: { userId }, select: { id: true } }),
                tx.taxProfile.findUnique({ where: { userId }, select: { kind: true, status: true, countryCode: true } }),
                tx.appSettings.findUnique({ where: { key: 'kzTaxEnabled' } }),
            ]);
            const cityIds = orders.map(row => row.id), intercityIds = requests.map(row => row.id);
            const offerIds = requests.map(row => row.selectedOfferId).filter(Boolean);
            const incomeSelect = { sourceKind: true, sourceId: true, profileKind: true, status: true,
                gross: true, opv: true, opvr: true, so: true, osms: true, withheld: true } as const;
            const [offers, cardPayments, commissionRows, monthIncome, rideIncome, remittances, bonusPayments] = await Promise.all([
                tx.intercityOffer.findMany({ where: { id: { in: offerIds }, driverId: userId }, select: { id: true, price: true } }),
                tx.tripCardPayment.findMany({ where: { driverUserId: userId, currency, OR: [
                    { kind: 'CITY', tripId: { in: cityIds } }, { kind: 'INTERCITY', tripId: { in: intercityIds } },
                ] }, select: { kind: true, tripId: true, amount: true, status: true, earningsCredited: true, refundedAt: true } }),
                tx.walletTransaction.groupBy({ by: ['type'], where: { walletId: wallet?.id ?? '', currency,
                    direction: 'DEBIT', OR: [
                        { type: 'ORDER_COMMISSION_DEBIT', orderId: { in: cityIds } },
                        { type: { in: ['DEBIT_INTERCITY_ACCEPTED_REQUEST', 'DEBIT_INTERCITY_COMPLETED_REQUEST'] }, intercityRequestId: { in: intercityIds } },
                    ] }, _sum: { amount: true } }),
                tx.taxIncomeEntry.findMany({ where: { ownerKey: userId, period, currency }, select: incomeSelect }),
                tx.taxIncomeEntry.findMany({ where: { ownerKey: userId, currency, sourceKind: { in: ['CITY', 'INTERCITY'] }, OR: [
                    { sourceKind: 'CITY', sourceId: { in: cityIds } }, { sourceKind: 'INTERCITY', sourceId: { in: intercityIds } },
                ] }, select: incomeSelect }),
                currency === 'KZT' ? tx.taxRemittance.aggregate({ where: { ownerKey: userId, period }, _sum: { amount: true } })
                    : Promise.resolve({ _sum: { amount: null } }),
                tx.walletTransaction.findMany({where:{walletId:wallet?.id ?? '',currency,type:'RIDE_BONUS_PAYMENT_CREDIT',direction:'CREDIT',OR:[{orderId:{in:cityIds}},{intercityRequestId:{in:intercityIds}}]},select:{orderId:true,intercityRequestId:true,amount:true}}),
            ]);
            const acceptedPrices = new Map(offers.map(row => [row.id, row.price]));
            const bonusByTrip = new Map(bonusPayments.map(row => [row.orderId ? `CITY:${row.orderId}` : `INTERCITY:${row.intercityRequestId}`, money(row.amount)]));
            const paymentByTrip = new Map(cardPayments.map(row => [`${row.kind}:${row.tripId}`, row]));
            const trips = [...orders.map(row => ({ ...row, paymentMethod:row.paidWithBonus ? 'BONUSES' : row.paymentMethod, kind: 'CITY' })), ...requests.map(row => ({ ...row,
                kind: 'INTERCITY', price: acceptedPrices.get(row.selectedOfferId) ?? row.price }))];
            let bonus = money(0), pendingBonus = money(0);
            let gross = money(0), cash = money(0), card = money(0), pendingCard = money(0), refundedCard = money(0);
            for (const trip of trips) {
                const fare = money(trip.price);
                gross = gross.add(fare);
                if (['BONUS','BONUSES'].includes(trip.paymentMethod)) {const paid = bonusByTrip.get(`${trip.kind}:${trip.id}`) ?? money(0);bonus = bonus.add(paid);pendingBonus = pendingBonus.add(Prisma.Decimal.max(0, fare.sub(paid)));continue;}
                if (trip.paymentMethod !== 'CARD') { cash = cash.add(fare); continue; }
                const payment = paymentByTrip.get(`${trip.kind}:${trip.id}`);
                if (payment?.refundedAt || payment?.status === 'REFUNDED') refundedCard = refundedCard.add(fare);
                else if (payment?.earningsCredited && payment.status === 'SETTLED') card = card.add(money(payment.amount));
                else pendingCard = pendingCard.add(fare);
            }
            const sum = (rows: any[], field: string) => rows.reduce((total, row) => total.add(money(row[field] ?? 0)), money(0)) as Prisma.Decimal;
            const accounted = monthIncome.filter(row => row.status === 'ACCOUNTED');
            const liability = (rows: any[]) => ['opv', 'opvr', 'so', 'osms'].reduce((total, field) => total.add(sum(rows, field)), money(0));
            const accrued = liability(accounted), withheld = sum(accounted, 'withheld');
            const rideAccrued = liability(rideIncome.filter(row => row.status === 'ACCOUNTED'));
            const commission = commissionRows.reduce((total, row) => total.add(money(row._sum.amount ?? 0)), money(0));
            const remitted = money(remittances._sum.amount ?? 0);
            const received = cash.add(card).add(bonus);
            const incomeByTrip = new Map(rideIncome.map(row => [`${row.sourceKind}:${row.sourceId}`, row]));
            return { period, currency, timeZone: 'Asia/Almaty', profile,
                trips: { total: trips.length, city: orders.length, intercity: requests.length,
                    legacyDates: trips.filter(row => !row.completedAt).length },
                gross, received, cash, card, bonus, pendingBonus, pendingCard, refundedCard, commission,
                afterCommission: received.sub(commission), net: received.sub(commission).sub(rideAccrued),
                commissionBreakdown: commissionRows.map(row => ({ type: row.type, amount: money(row._sum.amount ?? 0) })),
                tax: { enabled: enabled?.value === 'true',
                    showSocialPayments: currency === 'KZT' && ((profile?.countryCode === 'KZ' && profile?.kind === 'SELF_EMPLOYED') ||
                        [...monthIncome, ...rideIncome].some(row => row.profileKind === 'SELF_EMPLOYED')),
                    opv: sum(accounted, 'opv'), opvr: sum(accounted, 'opvr'), so: sum(accounted, 'so'), osms: sum(accounted, 'osms'),
                    accrued, withheld, debt: Prisma.Decimal.max(0, accrued.sub(withheld)), remitted,
                    payable: Prisma.Decimal.max(0, accrued.sub(remitted)), rideAccrued,
                    referralAccrued: liability(accounted.filter(row => row.sourceKind === 'REFERRAL')),
                    reviewCount: monthIncome.filter(row => row.status === 'REVIEW').length,
                    reviewGross: sum(monthIncome.filter(row => row.status === 'REVIEW'), 'gross'),
                    unaccountedTrips: trips.filter(row => incomeByTrip.get(`${row.kind}:${row.id}`)?.status !== 'ACCOUNTED').length,
                } };
        }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead });
    }
}
