import { BadRequestException, ConflictException, Injectable, OnModuleDestroy, OnModuleInit, UnauthorizedException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { Prisma } from '@prisma/client';
import * as bcrypt from 'bcrypt';
import { randomUUID } from 'node:crypto';
import { rm } from 'node:fs/promises';
import { join } from 'node:path';

@Injectable()
export class AccountDeletionService implements OnModuleInit, OnModuleDestroy {
    private timer?: ReturnType<typeof setInterval>;
    private cleaning = false;
    constructor(private prisma: PrismaService) {}
    onModuleInit() { this.timer = setInterval(() => { void this.cleanupFiles(); }, 30000); this.timer.unref(); void this.cleanupFiles(); }
    onModuleDestroy() { if (this.timer) clearInterval(this.timer); }
    async deleteOwnAccount(userId: string, password: string) {
        const original = await this.prisma.user.findUnique({where: {id: userId}});
        if (!original) throw new UnauthorizedException('Аккаунт не найден');
        if (!await bcrypt.compare(password, original.password)) throw new BadRequestException('Неверный пароль');
        if (original.role === 'ADMIN') throw new BadRequestException('Удаление административного аккаунта недоступно в приложении');
        const cleanupDirectory = await this.prisma.$transaction(async tx => {
            await tx.$executeRaw`SELECT pg_advisory_xact_lock(741302091)`;
            await tx.$executeRaw`SELECT id FROM "User" WHERE id=${userId} FOR UPDATE`;
            const user = await tx.user.findUnique({where: {id: userId}, include: {driverProfile: true, wallet: true}});
            if (!user || user.password !== original.password) throw new UnauthorizedException('Повторите вход в аккаунт');
            const driverId = user.driverProfile?.id;
            const active = await tx.order.findFirst({where: {OR: [{passengerId: userId}, ...(driverId ? [{driverId}] : [])], status: {in: ['DRIVER_ASSIGNED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS']}}});
            const intercity = await tx.intercityRequest.findFirst({where: {OR: [{passengerId: userId},{selectedDriverId: userId}], status: {in: ['ACCEPTED','DRIVER_ASSIGNED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS']}}});
            const sharing = await tx.rideSharingTrip.findFirst({where: {status: {in: ['IN_PROGRESS','STARTED']}, OR: [{driverId: userId},{bookings: {some: {passengerId: userId, status: {not: 'CANCELLED'}}}}]}});
            if (active || intercity || sharing) throw new ConflictException('Завершите текущую поездку, затем удалите аккаунт. Обращаться в поддержку не нужно.');
            if (await tx.tripCardPayment.findFirst({where: {OR: [{passengerId: userId},{driverUserId: userId}], status: {in: ['PENDING','PROCESSING','CHECKING','PAID','REFUND_PENDING']}}})) throw new ConflictException('Дождитесь завершения обработки оплаты и повторите удаление');
            // Retain only anonymous accounting references, never the original account.
            const archiveId = randomUUID();
            await tx.user.create({data: {id: archiveId, phone: `erased:${archiveId}`, name: 'Удалённый аккаунт', password: '', refCode: `erased:${archiveId}`, refLink: ''}});
            const ownOrders = (await tx.order.findMany({where: {passengerId: userId}, select: {id: true}})).map(item => item.id);
            await tx.orderChatMessage.deleteMany({where: {OR: [{senderId: userId},{orderId: {in: ownOrders}}]}});
            await tx.rideEvent.updateMany({where: {OR: [{actorUserId: userId},{orderId: {in: ownOrders}}]}, data: {actorUserId: null, payload: Prisma.DbNull, reason: null}});
            await tx.order.updateMany({where: {passengerId: userId, status: {in: ['CREATED','SEARCHING_DRIVER']}}, data: {status: 'CANCELLED', dispatchDriverId: null, dispatchExpiresAt: null}});
            await tx.orderAuctionInvitation.deleteMany({where: {orderId: {in: ownOrders}}});
            await tx.orderOffer.updateMany({where: {orderId: {in: ownOrders}, status: 'PENDING'}, data: {status: 'REJECTED'}});
            await tx.order.updateMany({where: {passengerId: userId}, data: {passengerId: archiveId, fromLat: 0, fromLng: 0, toLat: 0, toLng: 0, fromAddress: 'Удалено', toAddress: 'Удалено', fromManualAddress: null, toManualAddress: null, comment: null, deliveryRecipientContact: null, deliveryItemDescription: null, paymentCardId: null, driverRatingReason: null}});
            await tx.intercityRequest.updateMany({where: {passengerId: userId, status: {notIn: ['COMPLETED','CANCELLED']}}, data: {status: 'CANCELLED'}});
            await tx.intercityRequest.updateMany({where: {passengerId: userId}, data: {passengerId: archiveId, fromLat: null, fromLng: null, toLat: null, toLng: null, fromCity: 'Удалено', toCity: 'Удалено', fromAddressLabel: null, toAddressLabel: null, fromManualAddress: null, toManualAddress: null, comment: null, recipientContact: null, itemDescription: null, baggage: null, paymentCardId: null}});
            await tx.intercityOffer.updateMany({where: {driverId: userId}, data: {driverId: archiveId, status: 'REJECTED', comment: null}});
            await tx.intercityRequest.updateMany({where: {selectedDriverId: userId}, data: {selectedDriverId: null}});
            const bookings = await tx.rideSharingBooking.findMany({where: {passengerId: userId, status: {not: 'CANCELLED'}}});
            for (const booking of bookings) await tx.rideSharingTrip.updateMany({where: {id: booking.tripId, status: 'OPEN'}, data: {seatsAvailable: {increment: booking.seats}}});
            await tx.rideSharingBooking.deleteMany({where: {passengerId: userId}});
            await tx.rideSharingTrip.updateMany({where: {driverId: userId}, data: {driverId: archiveId, status: 'CANCELLED', fromCity: 'Удалено', toCity: 'Удалено', fromLat: 0, fromLng: 0, toLat: 0, toLng: 0}});
            await tx.tripVerification.deleteMany({where: {OR: [{passengerId: userId},{driverUserId: userId}]}});
            await tx.savedPaymentCard.deleteMany({where: {userId}});
            await tx.cardBinding.deleteMany({where: {userId}});
            await tx.tripCardPayment.updateMany({where: {passengerId: userId}, data: {passengerId: archiveId, cardId: 'ERASED', lastError: null}});
            await tx.tripCardPayment.updateMany({where: {driverUserId: userId}, data: {driverUserId: archiveId, lastError: null}});
            await tx.refreshToken.deleteMany({where: {userId}});
            await tx.promoUsage.deleteMany({where: {userId}});
            await tx.adminUserRole.deleteMany({where: {userId}});
            await tx.complaint.deleteMany({where: {OR: [{userId}, ...(driverId ? [{driverId}] : [])]}});
            await tx.adminAuditLog.updateMany({where: {adminId: userId}, data: {adminId: archiveId, details: Prisma.DbNull, ip: null, userAgent: null}});
            await tx.adminAuditLog.deleteMany({where: {targetId: {in: [userId, ...ownOrders, ...(driverId ? [driverId] : [])]}}});
            await tx.user.updateMany({where: {referredBy: user.refCode}, data: {referredBy: null}});
            await tx.walletTransaction.updateMany({where: {actorUserId: userId}, data: {actorUserId: null, note: null}});
            if (user.wallet) {
                await tx.walletTransaction.updateMany({where: {walletId: user.wallet.id}, data: {note: null}});
                await tx.payoutRequest.updateMany({where: {walletId: user.wallet.id, status: 'PENDING'}, data: {status: 'REJECTED'}});
                await tx.wallet.update({where: {id: user.wallet.id}, data: {userId: archiveId}});
            }
            if (driverId) {
                await tx.order.updateMany({where: {driverId}, data: {driverId: null}});
                await tx.orderOffer.deleteMany({where: {driverId}});
                await tx.driverOnline.deleteMany({where: {driverId}});
                await tx.driverRating.deleteMany({where: {driverId}});
                await tx.driverPriorityFlags.deleteMany({where: {driverId}});
                await tx.driverServiceStats.deleteMany({where: {driverId}});
                await tx.driverPartnerFuelBonus.deleteMany({where: {driverId}});
                await tx.driverDailyParticipation.deleteMany({where: {driverId}});
                await tx.vehicle.deleteMany({where: {driverId}});
                await tx.driverProfile.delete({where: {id: driverId}});
                await tx.accountDeletionFileJob.create({data: {directory: driverId}});
            }
            // Keep the minimum encrypted fiscal identity only where actual income
            // has been accounted. Pending declarations are erased with the account.
            await tx.taxIncomeEntry.updateMany({where: {ownerKey: userId}, data: {ownerKey: archiveId}});
            await tx.taxRemittance.updateMany({where: {ownerKey: userId}, data: {ownerKey: archiveId}});
            await tx.taxPeriodBasis.updateMany({where: {ownerKey: userId}, data: {ownerKey: archiveId}});
            await tx.taxAccountingIdentity.updateMany({where: {ownerKey: userId}, data: {ownerKey: archiveId}});
            await tx.techEvent.updateMany({where:{userId},data:{ip:null,client:Prisma.DbNull,details:Prisma.DbNull,message:'Персональные сведения удалены по запросу владельца аккаунта'}});
            await tx.user.delete({where: {id: userId}});
            return driverId;
        }, {maxWait: 10000, timeout: 30000});
        await this.cleanupFiles();
        const filesPending = cleanupDirectory ? await this.prisma.accountDeletionFileJob.count({where: {directory: cleanupDirectory}}).catch(() => 1) > 0 : false;
        return {deleted: true, filesPending};
    }
    async cleanupFiles() {
        if (this.cleaning) return;
        this.cleaning = true;
        try {
            for (const job of await this.prisma.accountDeletionFileJob.findMany({take: 20})) {
                if (!/^[0-9a-f-]{36}$/i.test(job.directory)) continue;
                try {
                    await rm(join(process.env.UPLOAD_DIR || join(process.cwd(), 'uploads'), job.directory), {recursive: true, force: true});
                    const privateRoot=process.env.TECH_STORAGE_DIR||join(process.cwd(),'technical-data');
                    for(const file of await this.prisma.techFile.findMany({where:{objectId:job.directory,deletedAt:null}})) {
                        if(!/^[a-f0-9]{32}\.bin$/.test(file.path))throw new Error('Invalid private file path');
                        await rm(join(privateRoot,file.path),{force:true});
                        await this.prisma.techFile.update({where:{id:file.id},data:{deletedAt:new Date()}});
                    }
                    await this.prisma.accountDeletionFileJob.deleteMany({where: {id: job.id}});
                } catch { /* Durable job retries removal after a filesystem failure. */ }
            }
        } catch { /* Database readiness is retried on the next tick. */ }
        finally { this.cleaning = false; }
    }
}
