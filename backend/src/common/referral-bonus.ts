import { Prisma } from '@prisma/client';
import { bonusField } from './currency';

export async function creditRideReferrals(tx: Prisma.TransactionClient, ride: {
    id: string; currency: string; commissionAmount: number;
    passengerId: string; driverUserId?: string;
    intercity?: boolean;
}) {
    const setting = await tx.appSettings.findUnique({ where: { key: 'referralCommissionPercent' } });
    const percent = Number(setting?.value ?? '25');
    if (!Number.isFinite(percent) || percent <= 0 || percent > 100 ||
        !Number.isFinite(ride.commissionAmount) || ride.commissionAmount <= 0) return;
    const amount = Math.round(ride.commissionAmount * percent) / 100;
    if (amount <= 0) return;
    const invited = await tx.user.findMany({
        where: { id: { in: [ride.passengerId, ride.driverUserId].filter(Boolean) } },
        select: { id: true, referredBy: true },
    });
    const credits: Array<{ userId: string; side: string }> = [];
    for (const [side, userId] of [['PASSENGER', ride.passengerId], ['DRIVER', ride.driverUserId]]) {
        const code = invited.find(user => user.id === userId)?.referredBy?.trim().toUpperCase();
        if (!code) continue;
        const referrer = await tx.user.findUnique({ where: { refCode: code }, select: { id: true } });
        if (referrer && referrer.id !== userId) credits.push({ userId: referrer.id, side });
    }
    // Stable wallet order avoids deadlocks when the same two inviters earn together.
    credits.sort((a, b) => a.userId.localeCompare(b.userId) || a.side.localeCompare(b.side));
    for (const credit of credits) {
        const wallet = await tx.wallet.upsert({ where: { userId: credit.userId }, create: { userId: credit.userId }, update: {} });
        await tx.wallet.update({ where: { id: wallet.id }, data: { [bonusField(ride.currency)]: { increment: 0 } } });
        const key = `referral:${ride.intercity ? 'intercity:' : ''}${ride.id}:${credit.side}`;
        if (await tx.walletTransaction.findFirst({ where: { idempotencyKey: key } })) continue;
        await tx.walletTransaction.create({ data: {
            walletId: wallet.id, type: 'REFERRAL_ORDER_BONUS', direction: 'CREDIT', balanceSource: 'BONUS',
            amount, currency: ride.currency, actorUserId: credit.userId,
            orderId: ride.intercity ? null : ride.id,
            intercityRequestId: ride.intercity ? ride.id : null,
            idempotencyKey: key, note: `Referral bonus for ${credit.side.toLowerCase()} side of completed ride`,
        } });
        await tx.wallet.update({ where: { id: wallet.id }, data: { [bonusField(ride.currency)]: { increment: amount } } });
    }
}
