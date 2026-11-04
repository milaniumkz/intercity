import { Injectable, OnModuleInit } from '@nestjs/common';
import { promises as fs } from 'node:fs';
import { join } from 'node:path';
import * as webpush from 'web-push';
import { PrismaService } from '../prisma.service';
@Injectable()
export class IdentityPushService implements OnModuleInit {
 private keys:{publicKey:string;privateKey:string};private running=false;
 constructor(private readonly prisma:PrismaService){}
 async onModuleInit(){
  const root=process.env.TECH_STORAGE_DIR||join(process.cwd(),'technical-data');await fs.mkdir(root,{recursive:true,mode:0o700});const path=join(root,'admin-webpush.json');
  try{await fs.writeFile(path,JSON.stringify(webpush.generateVAPIDKeys()),{flag:'wx',mode:0o600});}catch(e:any){if(e.code!=='EEXIST')throw e;}
  this.keys=JSON.parse(await fs.readFile(path,'utf8'));
 }
 publicKey(){return this.keys.publicKey;}
 async subscribe(userId:string,subscription:any){
  if(!subscription || JSON.stringify(subscription).length>8192)throw new Error('Некорректная подписка');
  let url:URL;try{url=new URL(subscription.endpoint);}catch{throw new Error('Некорректная подписка уведомлений');}
  if(url.protocol!=='https:'||url.username||url.password||url.port||!['fcm.googleapis.com','updates.push.services.mozilla.com','web.push.apple.com'].some(host=>url.hostname===host||url.hostname.endsWith('.'+host)) || !/^[A-Za-z0-9_-]{80,200}$/.test(subscription.keys?.p256dh||'')||!/^[A-Za-z0-9_-]{16,100}$/.test(subscription.keys?.auth||''))throw new Error('Некорректная подписка уведомлений');
  await this.prisma.adminWebPushSubscription.upsert({where:{endpoint:url.href},create:{userId,endpoint:url.href,subscription},update:{userId,subscription}});return {success:true};
 }
 async notifyReviews(){
  if(this.running||!this.keys)return;this.running=true;
  try{
   const pending=await this.prisma.biometricChallenge.findMany({where:{status:'REVIEW',notifiedAt:null,pushAttempts:{lt:1440}},select:{id:true},take:10});
   if(!pending.length)return;
   const devices=await this.prisma.adminWebPushSubscription.findMany({where:{user:{role:'ADMIN',blockedAt:null}}});
   if(!devices.length)return;
   for(const review of pending){
    let delivered=false;
    for(const d of devices){try{await webpush.sendNotification(d.subscription as any,JSON.stringify({title:'Нужна проверка личности',body:'Поступила новая запись. Откройте очередь проверок в админке.',url:'/#/identity-reviews',tag:'identity-'+review.id}),{vapidDetails:{subject:'https://admin.intercity.89-207-255-27.sslip.io',...this.keys},TTL:3600,urgency:'high',timeout:10000});delivered=true;}catch(e:any){if([404,410].includes(e.statusCode))await this.prisma.adminWebPushSubscription.deleteMany({where:{id:d.id}});}}
    await this.prisma.biometricChallenge.update({where:{id:review.id},data:{...(delivered?{notifiedAt:new Date()}:{}),pushAttempts:{increment:1}}});
   }
  }finally{this.running=false;}
 }
}
