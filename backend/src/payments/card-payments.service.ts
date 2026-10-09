import { Injectable, BadRequestException, NotFoundException, OnModuleInit, OnModuleDestroy, Logger } from '@nestjs/common';
import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { PushService } from '../notifications/push.service';
import { moneyField } from '../common/currency';
import { Kassa24Gateway, confirmedPayment } from './kassa24-gateway';

@Injectable()
export class CardPaymentsService implements OnModuleInit, OnModuleDestroy {
    private readonly logger = new Logger(CardPaymentsService.name);
    private timer: ReturnType<typeof setInterval>;
    private running = false;
    private readonly login = process.env.KASSA24_LOGIN || process.env.KASSA24_MERCHANT_ID || '';
    private readonly demo = process.env.KASSA24_DEMO === 'true';
    private readonly encryptionSecret = process.env.KASSA24_TOKEN_ENCRYPTION_KEY || process.env.JWT_SECRET || '';
    readonly gateway = new Kassa24Gateway({baseUrl:process.env.KASSA24_API_URL || 'https://ecommerce.pult24.kz',login:this.login,password:process.env.KASSA24_PASSWORD || '',demo:this.demo});
    constructor(private readonly prisma:PrismaService, private readonly realtime:RealtimeService, private readonly push:PushService) { }
    onModuleInit() { this.timer=setInterval(()=>void this.tick().catch(()=>this.logger.warn('Card payment reconciliation will retry')),2000); this.timer.unref(); }
    onModuleDestroy() { clearInterval(this.timer); }
    private key() { return createHash('sha256').update(`intercity:saved-payment-card:v1:${this.encryptionSecret}`).digest(); }
    encrypt(token:string) {
        if (this.encryptionSecret.length<32) throw new BadRequestException('Защищённая оплата картой пока недоступна');
        const iv=randomBytes(12), cipher=createCipheriv('aes-256-gcm',this.key(),iv);
        return Buffer.concat([iv,cipher.update(token,'utf8'),cipher.final(),cipher.getAuthTag()]).toString('base64');
    }
    decrypt(encrypted:string) {
        const data=Buffer.from(encrypted,'base64');
        const cipher=createDecipheriv('aes-256-gcm',this.key(),data.subarray(0,12));cipher.setAuthTag(data.subarray(-16));
        return Buffer.concat([cipher.update(data.subarray(12,-16)),cipher.final()]).toString('utf8');
    }
    private webUrl() {
        const configured=process.env.PUBLIC_WEB_URL || process.env.WEB_APP_URL || process.env.FRONTEND_URL;
        if (configured) return configured.replace(/\/+$/,'');
        try {
            const api=new URL(process.env.BACKEND_PUBLIC_URL || process.env.PUBLIC_API_URL || '');
            if (api.protocol==='https:' && api.hostname.startsWith('api.')) {api.hostname=api.hostname.slice(4);return api.origin;}
        } catch(_) { }
        return '';
    }
    async configuration() {
        const rows=await this.prisma.appSettings.findMany({where:{key:{in:['kassa24SavedCardsEnabled','kassa24AcquiringId']}}});
        const acquiringId=Number(rows.find(r=>r.key==='kassa24AcquiringId')?.value ?? process.env.KASSA24_ACQUIRING_ID);
        const enabled=(rows.find(r=>r.key==='kassa24SavedCardsEnabled')?.value ?? process.env.KASSA24_SAVED_CARDS_ENABLED)==='true';
        const configured=enabled && !this.demo && !!this.login && !!process.env.KASSA24_PASSWORD && Number.isSafeInteger(acquiringId) && acquiringId>0 && this.encryptionSecret.length>=32 && this.webUrl().startsWith('https://') && (process.env.BACKEND_PUBLIC_URL || process.env.PUBLIC_API_URL || '').startsWith('https://');
        return {configured,acquiringId,demo:this.demo,currencies:['KZT'],message:configured ? null : 'Оплата сохранённой картой пока недоступна'};
    }
    private async customer(userId:string) {
        const user=await this.prisma.user.findUnique({where:{id:userId},select:{phone:true}});
        let phone=user?.phone.replace(/\D/g,'') ?? '';
        if (phone.length===10) phone=`7${phone}`;
        if (phone.length===11 && phone.startsWith('8')) phone=`7${phone.slice(1)}`;
        if (!/^7\d{10}$/.test(phone)) throw new BadRequestException('Укажите корректный номер телефона в профиле');
        return phone;
    }
    private callbackUrl() {
        const base=(process.env.BACKEND_PUBLIC_URL || process.env.PUBLIC_API_URL || '').replace(/\/+$/,'');
        if (!base.startsWith('https://')) throw new BadRequestException('Оплата картой пока недоступна');
        return `${base}/payments/callback`;
    }
    private publicCard(card:any) { return {id:card.id,last4:card.last4,isDefault:card.isDefault}; }
    async listCards(userId:string) {
        const config=await this.configuration();
        const cards=await this.prisma.savedPaymentCard.findMany({where:{userId,active:true,demo:this.demo},orderBy:{createdAt:'desc'}});
        return {configured:config.configured,currencies:config.currencies,message:config.message,cards:cards.map(c=>this.publicCard(c))};
    }
    async bind(userId:string) {
        const config=await this.configuration();
        if (!config.configured) throw new BadRequestException(config.message);
        const phone=await this.customer(userId);
        const pending=await this.prisma.cardBinding.findFirst({where:{userId,status:'PENDING',createdAt:{gte:new Date(Date.now()-60000)}}});
        if (pending) throw new BadRequestException('Привязка уже запущена. Вернитесь к форме Kassa24 или обновите список карт.');
        const binding=await this.prisma.cardBinding.create({data:{userId,phone,acquiringId:config.acquiringId,demo:this.demo}});
        try {
            const returnBase=this.webUrl();
            if (!returnBase.startsWith('https://')) throw new BadRequestException('Оплата картой пока недоступна');
            // Official tokenization contract permits binding without a fare amount.
            const response=await this.gateway.create({orderId:`bind:${binding.id}`,tokenization:true,customerData:{phone},callbackUrl:this.callbackUrl(),returnUrl:`${returnBase}/#/profile/payments`,description:'Привязка карты INTERCITY'});
            const url=new URL(response.url);
            const providerHost=new URL(process.env.KASSA24_API_URL || 'https://ecommerce.pult24.kz').hostname;
            if (url.protocol!=='https:' || url.hostname!==providerHost || !response.id) throw new BadRequestException('Не удалось открыть защищённую форму привязки карты');
            await this.prisma.cardBinding.update({where:{id:binding.id},data:{providerId:String(response.id)}});
            return {bindingId:binding.id,url:url.toString()};
        } catch(error) {
            // An ambiguous transport failure must remain reconcilable by its unique order ID.
            throw error;
        }
    }
    async syncCards(userId:string) {
        const config=await this.configuration();
        if (!config.configured) return this.listCards(userId);
        const phone=await this.customer(userId);
        const tokens=await this.gateway.tokens(phone);
        if (!Array.isArray(tokens)) throw new BadRequestException('Не удалось обновить список карт');
        await this.prisma.$transaction(async tx=>{
            await tx.$executeRaw`SELECT id FROM "User" WHERE id=${userId} FOR UPDATE`;
            const current=await tx.savedPaymentCard.findMany({where:{userId,active:true,demo:this.demo}});
            let hasDefault=current.some(c=>c.isDefault);
            const hashes:string[]=[];
            for (const token of tokens) {
                if (typeof token.ID!=='string' || !token.ID || typeof token.Pan!=='string') continue;
                const last4=token.Pan.replace(/\D/g,'').slice(-4);
                if (last4.length!==4) continue;
                const tokenHash=createHash('sha256').update(`${this.login}:${this.demo}:${token.ID}`).digest('hex');
                hashes.push(tokenHash);
                const existing=await tx.savedPaymentCard.findUnique({where:{tokenHash}});
                if (existing && existing.userId!==userId) continue;
                const card=await tx.savedPaymentCard.upsert({where:{tokenHash},update:{active:true,last4,phone},create:{userId,phone,tokenHash,tokenEncrypted:this.encrypt(token.ID),last4,acquiringId:config.acquiringId,demo:this.demo,isDefault:!hasDefault}});
                hasDefault=hasDefault || card.isDefault;
            }
            await tx.savedPaymentCard.updateMany({where:{userId,demo:this.demo,tokenHash:{notIn:hashes}},data:{active:false,isDefault:false}});
            const saved=await tx.savedPaymentCard.findMany({where:{userId,demo:this.demo,active:true}});
            if (saved.length && !saved.some(c=>c.isDefault)) await tx.savedPaymentCard.update({where:{id:saved[0].id},data:{isDefault:true}});
            if (saved.length) await tx.cardBinding.updateMany({where:{userId,status:'PENDING'},data:{status:'SYNCED'}});
        });
        return this.listCards(userId);
    }
    async selectCard(userId:string,id:string) {
        await this.prisma.$transaction(async tx=>{
            await tx.$executeRaw`SELECT id FROM "User" WHERE id=${userId} FOR UPDATE`;
            const card=await tx.savedPaymentCard.findFirst({where:{id,userId,active:true,demo:this.demo}});
            if (!card) throw new NotFoundException('Карта не найдена');
            await tx.savedPaymentCard.updateMany({where:{userId},data:{isDefault:false}});
            await tx.savedPaymentCard.update({where:{id},data:{isDefault:true}});
        });
        return this.listCards(userId);
    }
    async removeCard(userId:string,id:string) {
        const card=await this.prisma.savedPaymentCard.findFirst({where:{id,userId,active:true}});
        if (!card) throw new NotFoundException('Карта не найдена');
        const pending=await this.prisma.tripCardPayment.count({where:{cardId:id,status:{in:['PENDING','PROCESSING','CHECKING']}}});
        if (pending) throw new BadRequestException('Дождитесь завершения проверки текущего платежа');
        const result=await this.gateway.remove(this.decrypt(card.tokenEncrypted));
        if (result?.removed!==true) throw new BadRequestException('Не удалось отвязать карту');
        await this.prisma.savedPaymentCard.update({where:{id},data:{active:false,isDefault:false}});
        return this.listCards(userId);
    }
    async cardForOrder(userId:string,currency:string) {
        const config=await this.configuration();
        if (!config.configured || currency!=='KZT') throw new BadRequestException(currency==='RUB'?'Автосписание в рублях пока недоступно. Выберите наличные или перевод.':'Оплата картой пока недоступна');
        const card=await this.prisma.savedPaymentCard.findFirst({where:{userId,active:true,isDefault:true,demo:this.demo}});
        if (!card) throw new BadRequestException('Сначала добавьте банковскую карту в профиле → Способы оплаты');
        return card.id;
    }
    async schedule(tx:any,kind:string,trip:any,driverUserId:string) {
        if (trip.paymentMethod!=='CARD') return;
        if (!trip.paymentCardId || trip.currency!=='KZT' || !Number.isFinite(trip.price) || trip.price<=0) throw new BadRequestException('Не удалось подготовить оплату поездки');
        await tx.tripCardPayment.upsert({where:{id:`${kind}:${trip.id}`},update:{},create:{id:`${kind}:${trip.id}`,kind,tripId:trip.id,passengerId:trip.passengerId,driverUserId,cardId:trip.paymentCardId,amount:trip.price,currency:trip.currency}});
    }
    async callback(orderId:string) {
        if (orderId.startsWith('bind:')) {
            const binding=await this.prisma.cardBinding.findUnique({where:{id:orderId.slice(5)}});
            if (!binding || binding.status!=='PENDING') return;
            // Authenticated token listing, never accept caller-supplied cardToken or PAN.
            await this.syncCards(binding.userId);
            return;
        }
        if (!/^(CITY|INTERCITY):[a-zA-Z0-9-]+:[123]$/.test(orderId)) return;
        const attempt=await this.prisma.cardPaymentAttempt.findUnique({where:{id:orderId}});
        if (attempt) await this.prisma.tripCardPayment.updateMany({where:{id:attempt.paymentId,status:{in:['PENDING','CHECKING']}},data:{nextCheckAt:new Date()}});
    }
    async tick() {
        if (this.running) return;
        this.running=true;
        try {
            const pending=await this.prisma.tripCardPayment.findMany({where:{status:{in:['PENDING','PROCESSING','CHECKING','PAID','REFUND_PENDING']},nextCheckAt:{lte:new Date()},OR:[{leaseUntil:null},{leaseUntil:{lte:new Date()}}]},take:5,orderBy:{nextCheckAt:'asc'}});
            for (const payment of pending) await this.processPayment(payment.id);
        } finally {this.running=false;}
    }
    async processPayment(id:string) {
        const lease=new Date(Date.now()+60000);
        const claim=await this.prisma.tripCardPayment.updateMany({where:{id,status:{in:['PENDING','PROCESSING','CHECKING','PAID','REFUND_PENDING']},OR:[{leaseUntil:null},{leaseUntil:{lte:new Date()}}]},data:{leaseUntil:lease}});
        if (!claim.count) return;
        try {
            const payment=await this.prisma.tripCardPayment.findUniqueOrThrow({where:{id}});
            const trip=payment.kind==='CITY'?await this.prisma.order.findUnique({where:{id:payment.tripId}}):await this.prisma.intercityRequest.findUnique({where:{id:payment.tripId}});
            if (!trip) return;
            if (payment.status==='PAID' && trip.status==='COMPLETED') {await this.creditEarnings(payment);return;}
            if (trip.status==='CANCELLED') {await this.cancelPayment(payment);return;}
            if (payment.status==='PAID') return;
            const number=Math.max(1,payment.attempts);
            const attemptId=`${id}:${number}`;
            let attempt=await this.prisma.cardPaymentAttempt.findUnique({where:{id:attemptId}});
            if (!attempt) {
                attempt=await this.prisma.cardPaymentAttempt.create({data:{id:attemptId,paymentId:id,number}});
                await this.prisma.tripCardPayment.update({where:{id},data:{attempts:number,status:'PROCESSING'}});
            }
            let status=await this.gateway.status(attemptId);
            if (status?.notFound) {
                const card=await this.prisma.savedPaymentCard.findFirst({where:{id:payment.cardId,userId:payment.passengerId,active:true,demo:this.demo}});
                if (!card) {await this.failedAttempt(payment,number,'Сохранённая карта недоступна');return;}
                const phone=card.phone;
                let token:string;
                try { token=this.decrypt(card.tokenEncrypted); } catch(_) {await this.failedAttempt(payment,number,'Не удалось использовать сохранённую карту');return;}
                const response=await this.gateway.create({orderId:attemptId,amount:Math.round(payment.amount*100),customerData:{phone,cardToken:token},acquiringId:card.acquiringId,callbackUrl:this.callbackUrl(),description:`Поездка INTERCITY ${payment.tripId}`});
                if (response?.requestRejected || response?.notFound) {await this.failedAttempt(payment,number,'Платёж отклонён платёжным сервисом');return;}
                if (response?.id) await this.prisma.cardPaymentAttempt.update({where:{id:attemptId},data:{providerId:String(response.id)}});
                status=await this.gateway.status(attemptId);
            }
            if (!confirmedPayment(status,attemptId,payment.amount,this.login,this.demo)) throw new BadRequestException('Не удалось подтвердить состояние оплаты');
            if (Number(status.status)===1) {
                await this.prisma.$transaction(async tx=>{
                    await tx.cardPaymentAttempt.update({where:{id:attemptId},data:{status:'PAID',providerId:String(status.id)}});
                    await tx.tripCardPayment.update({where:{id},data:{status:'PAID',paidAt:new Date(),lastError:null}});
                });
                await this.publishPayment(payment,'PAID');
                const latest=payment.kind==='CITY'?await this.prisma.order.findUnique({where:{id:payment.tripId}}):await this.prisma.intercityRequest.findUnique({where:{id:payment.tripId}});
                if (latest?.status==='COMPLETED') await this.creditEarnings(payment);
                if (latest?.status==='CANCELLED') await this.cancelPayment({...payment,status:'PAID'});
            } else if ([0,3].includes(Number(status.status))) {await this.failedAttempt(payment,number,'Оплата отклонена банком');}
            else await this.prisma.tripCardPayment.update({where:{id},data:{status:'CHECKING'}});
        } catch(_) {
            // Unknown result is not a declined charge. Keep the SAME provider order ID.
            await this.prisma.tripCardPayment.updateMany({where:{id,status:{notIn:['PAID','REFUNDED','CASH','CANCELLED']}},data:{status:'CHECKING',lastError:'Проверяем состояние платежа. Повторное списание не запускается.'}});
        } finally {
            await this.prisma.tripCardPayment.update({where:{id},data:{leaseUntil:null,nextCheckAt:new Date(Date.now()+5000)}});
        }
    }
    private async failedAttempt(payment:any,number:number,reason:string) {
        await this.prisma.cardPaymentAttempt.update({where:{id:`${payment.id}:${number}`},data:{status:'FAILED'}});
        if (number<3) {await this.prisma.tripCardPayment.update({where:{id:payment.id},data:{status:'PENDING',attempts:number+1,lastError:reason}});return;}
        const fallback = await this.prisma.$transaction(async tx=>{
            if (payment.kind==='CITY') await tx.$executeRaw`SELECT id FROM "Order" WHERE id=${payment.tripId} FOR UPDATE`;
            else await tx.$executeRaw`SELECT id FROM "IntercityRequest" WHERE id=${payment.tripId} FOR UPDATE`;
            const currentTrip=payment.kind==='CITY'?await tx.order.findUnique({where:{id:payment.tripId}}):await tx.intercityRequest.findUnique({where:{id:payment.tripId}});
            if (!currentTrip || currentTrip.status==='CANCELLED') {await tx.tripCardPayment.update({where:{id:payment.id},data:{status:'CANCELLED'}});return false;}
            const claimed=await tx.tripCardPayment.updateMany({where:{id:payment.id,status:{notIn:['PAID','CASH','REFUNDED']}},data:{status:'CASH',lastError:reason}});
            if (!claimed.count) return false;
            if (payment.kind==='CITY') await tx.order.update({where:{id:payment.tripId},data:{paymentMethod:'CASH'}});
            else await tx.intercityRequest.update({where:{id:payment.tripId},data:{paymentMethod:'CASH'}});
            return true;
        });
        if (fallback) await this.publishPayment(payment,'CASH');
    }
    async settleCompletedTrip(kind:string,tripId:string) {
        const payment=await this.prisma.tripCardPayment.findUnique({where:{id:`${kind}:${tripId}`}});
        if (payment?.status==='PAID') await this.creditEarnings(payment);
    }
    private async creditEarnings(payment:any) {
        await this.prisma.$transaction(async tx=>{
            await tx.$executeRaw`SELECT id FROM "TripCardPayment" WHERE id=${payment.id} FOR UPDATE`;
            const current=await tx.tripCardPayment.findUniqueOrThrow({where:{id:payment.id}});
            if (current.status!=='PAID' || current.earningsCredited || current.refundedAt) return;
            const wallet=await tx.wallet.upsert({where:{userId:payment.driverUserId},create:{userId:payment.driverUserId},update:{}});
            const key=`card-earnings:${payment.id}`;
            if (!await tx.walletTransaction.findFirst({where:{idempotencyKey:key}})) {
                await tx.wallet.update({where:{id:wallet.id},data:{[moneyField(payment.currency)]:{increment:payment.amount}}});
                await tx.walletTransaction.create({data:{walletId:wallet.id,currency:payment.currency,type:'CARD_RIDE_EARNINGS',direction:'CREDIT',balanceSource:'MONEY',amount:payment.amount,idempotencyKey:key,orderId:payment.kind==='CITY'?payment.tripId:null,intercityRequestId:payment.kind==='INTERCITY'?payment.tripId:null,note:'Оплата поездки банковской картой'}});
            }
            await tx.tripCardPayment.update({where:{id:payment.id},data:{earningsCredited:true,status:'SETTLED'}});
        });
        await this.publishPayment(payment,'SETTLED');
    }
    private async cancelPayment(payment:any) {
        if (payment.earningsCredited) return;
        const attempts=await this.prisma.cardPaymentAttempt.findMany({where:{paymentId:payment.id}});
        if (!attempts.length) {await this.prisma.tripCardPayment.update({where:{id:payment.id},data:{status:'CANCELLED'}});return;}
        let refunded=false;
        for (const attempt of attempts) {
            let status=await this.gateway.status(attempt.id);
            if (status?.notFound) continue;
            if (!confirmedPayment(status,attempt.id,payment.amount,this.login,this.demo)) throw new BadRequestException('Проверка возврата оплаты');
            if ([0,3].includes(Number(status.status))) {refunded=refunded || Number(status.status)===3;continue;}
            await this.gateway.cancel(attempt.id);
            status=await this.gateway.status(attempt.id);
            if (!confirmedPayment(status,attempt.id,payment.amount,this.login,this.demo) || ![0,3].includes(Number(status.status))) {
                await this.prisma.tripCardPayment.update({where:{id:payment.id},data:{status:'REFUND_PENDING',lastError:'Возврат ожидает подтверждения платёжного сервиса'}});return;
            }
            refunded=refunded || Number(status.status)===3;
        }
        await this.prisma.tripCardPayment.update({where:{id:payment.id},data:{status:refunded?'REFUNDED':'CANCELLED',refundedAt:refunded?new Date():null,lastError:null}});
        await this.publishPayment(payment,refunded?'REFUNDED':'CANCELLED');
    }
    private async publishPayment(payment:any,status:string) {
        const profile=await this.prisma.driverProfile.findUnique({where:{userId:payment.driverUserId},select:{id:true}});
        const payload={paymentStatus:status,paymentMethod:status==='CASH'?'CASH':'CARD',driverId:profile?.id,driverUserId:payment.driverUserId,tripId:payment.tripId,kind:payment.kind};
        this.realtime.publish({type:'order.payment.changed',entity:'order',entityId:payment.tripId,at:new Date().toISOString(),payload});
        if (profile) this.realtime.publish({type:'driver.payment.changed',entity:'driver',entityId:profile.id,at:new Date().toISOString(),payload});
        if (status==='CASH') {
            const data={type:'PAYMENT_CASH_FALLBACK',orderId:payment.tripId,kind:payment.kind};
            await Promise.allSettled([payment.passengerId,payment.driverUserId].map(userId=>this.push.sendToUser(userId,{title:'Способ оплаты изменён',body:'Не удалось списать оплату с карты. Способ оплаты переведён на наличные.',data})));
        }
    }
    async state(kind:string,tripId:string) {
        return this.prisma.tripCardPayment.findUnique({where:{id:`${kind}:${tripId}`},select:{status:true,attempts:true,amount:true,currency:true,lastError:true,paidAt:true}});
    }
}
