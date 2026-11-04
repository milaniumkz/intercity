import { BadRequestException } from '@nestjs/common';
import { moneyField } from './currency';

/** Convert a passenger's already-debited bonus fare into the driver's earned money. */
export async function settleBonusRidePayment(tx: any, kind: 'CITY' | 'INTERCITY', ride: any, driverUserId: string, gross: number) {
    if (!ride.paidWithBonus && !['BONUS','BONUSES'].includes(ride.paymentMethod)) return;
    if (!Number.isFinite(gross) || gross <= 0) throw new BadRequestException('Некорректная бонусная оплата поездки');
    const link = kind === 'CITY' ? { orderId: ride.id } : { intercityRequestId: ride.id };
    const debit = await tx.walletTransaction.findFirst({where:{...link,type:kind === 'CITY' ? 'ORDER_BONUS_USED' : 'INTERCITY_OFFER_BONUS_USED',direction:'DEBIT',currency:ride.currency,wallet:{userId:ride.passengerId}}});
    if (!debit || Math.abs(debit.amount-gross)>0.005) throw new BadRequestException('Не подтверждена бонусная оплата поездки');
    const key = `bonus-ride-payment:${kind}:${ride.id}:driver:${driverUserId}`;
    if (await tx.walletTransaction.findFirst({where:{idempotencyKey:key}})) return;
    const wallet = await tx.wallet.upsert({where:{userId:driverUserId},create:{userId:driverUserId},update:{}});
    await tx.wallet.update({where:{id:wallet.id},data:{[moneyField(ride.currency)]:{increment:gross}}});
    await tx.walletTransaction.create({data:{...link,walletId:wallet.id,type:'RIDE_BONUS_PAYMENT_CREDIT',direction:'CREDIT',balanceSource:'MONEY',amount:gross,currency:ride.currency,idempotencyKey:key,actorUserId:driverUserId,note:'Оплата завершённой поездки бонусами пассажира'}});
}
