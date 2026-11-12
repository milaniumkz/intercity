import { Injectable } from '@nestjs/common';
import { randomInt } from 'crypto';
import { PrismaService } from '../prisma.service';
export const KASPI_IPS = ['194.187.247.152','194.187.245.108','197.187.244.108'];
export const KASPI_TEST_PHONE = '70000000001';
const reply = (txn_id:string,result:number,comment:string,extra={}) => ({txn_id,result,comment,...extra});
const scalar = (v:unknown):string => typeof v === 'string' ? v : '';
export function kaspiAmount(raw:string):number|null {
    if (!/^(?:0|[1-9]\d{0,7})\.\d{2}$/.test(raw)) return null;
    const cents=Number(raw.replace('.',''));
    return cents>=1 && cents<=1000000000 ? cents : null;
}
export function kaspiDate(raw:string):boolean {
    if (!/^\d{14}$/.test(raw)) return false;
    const [y,m,d,h,i,s]=[raw.slice(0,4),raw.slice(4,6),raw.slice(6,8),raw.slice(8,10),raw.slice(10,12),raw.slice(12,14)].map(Number);
    const date=new Date(Date.UTC(y,m-1,d,h,i,s));
    return y>=2000 && date.getUTCFullYear()===y && date.getUTCMonth()===m-1 && date.getUTCDate()===d && h<24 && i<60 && s<60;
}
@Injectable()
export class KaspiService {
    constructor(private readonly prisma:PrismaService) {}
    async instructions(userId:string) {
        const user=await this.prisma.user.findUnique({where:{id:userId},include:{driverProfile:true}});
        if (!user?.driverProfile || user.blockedAt) return {available:false,message:'Пополнение Kaspi доступно водителям с действующим счётом.'};
        const setting=await this.prisma.appSettings.findUnique({where:{key:'kaspiPaymentUrl'}});
        let paymentUrl:string|null=null;
        try {const url=new URL(setting?.value||'');if(url.protocol==='https:' && ['kaspi.kz','pay.kaspi.kz'].includes(url.hostname) && !url.username && !url.password) paymentUrl=url.toString();}catch(_){}
        return {available:true,account:user.phone.replace(/\D/g,''),currency:'KZT',paymentUrl,bankConnectionReady:!!paymentUrl,
            message:paymentUrl ? 'Откройте Kaspi.kz, проверьте услугу InterCity и укажите номер счёта. После оплаты обновите баланс.' : 'Оплата Kaspi находится на подключении у банка. После появления услуги InterCity в Kaspi.kz → Платежи укажите этот номер счёта. До подключения используйте онлайн-оплату картой.'};
    }
    async process(query:Record<string,unknown>) {
        const txnId=scalar(query.txn_id),command=scalar(query.command),account=scalar(query.account);
        if(!/^\d{1,18}$/.test(txnId)||!/^7\d{10}$/.test(account)||!['check','pay'].includes(command))return reply(txnId,5,'Некорректные параметры');
        if(command==='check') {
            try {const user=await this.prisma.user.findUnique({where:{phone:'+'+account},include:{driverProfile:true,wallet:true}});
                if(!user?.driverProfile||!user.wallet||user.blockedAt)return reply(txnId,1,'Счёт не найден или недоступен');
                return reply(txnId,0,'Счёт доступен для пополнения',{fields:{field1:{'@name':'account','#text':account},field2:{'@name':'service','#text':'InterCity — баланс водителя'}}});
            }catch(_){return reply(txnId,5,'Временная ошибка провайдера');}
        }
        const cents=kaspiAmount(scalar(query.sum)),txnDate=scalar(query.txn_date);
        if(cents===null||!kaspiDate(txnDate))return reply(txnId,5,'Некорректная сумма или дата');
        const key=`kaspi:${txnId}`;
        try {return await this.prisma.$transaction(async tx=>{
            await tx.$executeRaw`SET LOCAL lock_timeout = '5s'`;
            await tx.$executeRaw`SET LOCAL statement_timeout = '8s'`;
            await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${key}))`;
            const prior=await tx.topupRequest.findUnique({where:{externalOrderId:key},include:{wallet:{include:{user:true}}}});
            if(prior) {
                if(prior.wallet.user.phone.replace(/\D/g,'')!==account||Math.round(prior.amount*100)!==cents||prior.provider!=='KASPI')return reply(txnId,5,'Идентификатор платежа уже использован с другими реквизитами');
                return reply(txnId,prior.status==='APPROVED'?0:4,prior.status==='APPROVED'?'OK':'Платёж в обработке',{prv_txn_id:prior.id,sum:(cents/100).toFixed(2)});
            }
            const user=await tx.user.findUnique({where:{phone:'+'+account},include:{wallet:true,driverProfile:true}});
            if(!user?.wallet||!user.driverProfile||user.blockedAt)return reply(txnId,1,'Счёт не найден или недоступен');
            const amount=cents/100,id=`${Date.now()}${randomInt(100000,1000000)}`;
            const topup=await tx.topupRequest.create({data:{id,walletId:user.wallet.id,amount,currency:'KZT',provider:'KASPI',externalOrderId:key,status:'APPROVED'}});
            await tx.wallet.update({where:{id:user.wallet.id},data:{money:{increment:amount}}});
            await tx.walletTransaction.create({data:{walletId:user.wallet.id,type:'TOPUP_KASPI',direction:'CREDIT',balanceSource:'MONEY',currency:'KZT',amount,topupRequestId:topup.id,idempotencyKey:key,
                note:JSON.stringify({provider:'KASPI',txn_id:txnId,txn_date:txnDate,timezone:'Asia/Almaty',account,testAccount:account===KASPI_TEST_PHONE})}});
            return reply(txnId,0,'OK',{prv_txn_id:topup.id,sum:amount.toFixed(2)});
        },{maxWait:2000,timeout:10000});}catch(_){return reply(txnId,5,'Временная ошибка провайдера. Повторите запрос с тем же txn_id');}
    }
}
