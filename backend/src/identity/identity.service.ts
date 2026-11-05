import { normalizePlate } from './vehicle-document';
import { BadRequestException, ConflictException, ForbiddenException, Injectable, OnModuleDestroy, OnModuleInit, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { createHash, randomBytes, randomInt } from 'node:crypto';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../prisma.service';
import { IdentityVault } from './identity-vault';
import { IdentityEngine } from './identity-engine';
import { IdentityPushService } from './identity-push.service';
const hash=(s:string|Buffer)=>createHash('sha256').update(s).digest('hex');
const token=()=>randomBytes(32).toString('base64url');
export const IDENTITY_CONSENT='intercity-face-2026-11-v2';
export const identityFailure='Не удалось подтвердить владельца аккаунта. Восстановление не разрешено.';
export function similarity(a:number[],b:number[]) {
 if(a.length!==128||b.length!==128||!a.every(Number.isFinite)||!b.every(Number.isFinite))throw new Error('Invalid face template');
 const norms=Math.sqrt(a.reduce((s,v)=>s+v*v,0)*b.reduce((s,v)=>s+v*v,0));
 if(norms<0.01)throw new Error('Invalid face template');
 return a.reduce((s,v,i)=>s+v*b[i],0)/norms;
}
/** A single missed gesture may be tolerated only with a strong face match
 * and independently successful PAD, continuity and sharpness checks. */
export function confidentRecoveryMotion(result:any,score:number) {
 const c=result.checks;
 return result.verdict==='REVIEW'&&score>=.70&&c?.oneFace===true&&
  c.totalActions===3&&c.passedActions===2&&
  Array.isArray(c.issues)&&c.issues.length===1&&c.issues[0]==='ACTIONS'&&
  Number.isFinite(c.continuity)&&c.continuity>=.60&&c.continuity<=1&&Number.isFinite(c.sharpness)&&c.sharpness>=35&&
  Array.isArray(c.padMedian)&&c.padMedian.length===2&&c.padMedian.every((v:any)=>typeof v==='number'&&v>=.97&&v<=1)&&
  Array.isArray(c.padLower)&&c.padLower.length===2&&c.padLower.every((v:any)=>typeof v==='number'&&v>=.85&&v<=1);
}
/** Detect virtually identical temporal frames after common container re-encoding.
 * Scoped to this account; never used to search for people across accounts. */
export function repeatedVideo(a:string[],b:string[]) {
 if(a.length!==b.length||a.length<30)return false;
 let total=0,close=0;
 for(let i=0;i<a.length;i++){
  if(!/^[a-f0-9]{16}$/.test(a[i])||!/^[a-f0-9]{16}$/.test(b[i]))return false;
  let difference=BigInt('0x'+a[i])^BigInt('0x'+b[i]),bits=0;
  while(difference){difference&=difference-1n;bits++;}
  total+=bits;if(bits<=1)close++;
 }
 return total/a.length<=.5 && close>=Math.ceil(a.length*.98);
}
@Injectable()
export class IdentityService implements OnModuleInit,OnModuleDestroy {
 readonly vault=new IdentityVault();private timer?:ReturnType<typeof setInterval>;
 constructor(private readonly prisma:PrismaService,private readonly engine:IdentityEngine,private readonly push:IdentityPushService){}
 async onModuleInit(){await this.vault.init();if(process.env.NODE_ENV!=='test'){this.timer=setInterval(()=>void this.maintenance().catch(()=>{}),60000);this.timer.unref();}}
 onModuleDestroy(){if(this.timer)clearInterval(this.timer);}
 async enabled(){return (await this.prisma.appSettings.findUnique({where:{key:'identityVerificationEnabled'}}))?.value==='true';}
 async needsVerification(userId:string,role:string){if(role==='ADMIN'||!await this.enabled())return false;return (await this.prisma.biometricProfile.findUnique({where:{userId},select:{status:true}}))?.status!=='VERIFIED';}
 async driverDocumentsRequired(userId:string,db:any=this.prisma){
  if((await db.appSettings.findUnique({where:{key:'identityVerificationEnabled'}}))?.value!=='true')return false;
  const [bio,driver]=await Promise.all([db.biometricProfile.findUnique({where:{userId},select:{status:true,driverConsent:true,driverDocumentHash:true,vehicleDocumentHash:true,vehicleData:true}}),db.driverProfile.findUnique({where:{userId}})]);
  if(!driver)return false;
  if(!bio||bio.status!=='VERIFIED'||!bio.driverConsent||!bio.driverDocumentHash||!bio.vehicleDocumentHash||!bio.vehicleData)return true;
  const checksum=async(url:string|null)=>{
   const id=/^\/api\/driver\/docs\/files\/([a-f0-9]{32})$/.exec(url||'')?.[1];
   const file=id?await db.techFile.findUnique({where:{id},select:{userId:true,sha256:true,deletedAt:true,verdict:true}}):null;
   return file&&file.userId===userId&&!file.deletedAt&&file.verdict!=='REJECT'?file.sha256:null;
  };
  if(!await checksum(driver.driverLicenseUrl))return true;
  const passport=await checksum(driver.passportUrl),front=await checksum(driver.techPassportFrontUrl),back=driver.techPassportBackUrl?await checksum(driver.techPassportBackUrl):'';
  if(!passport||!front||back===null||bio.driverDocumentHash!==passport||bio.vehicleDocumentHash!==hash([front,back].join(':')))return true;
  const data=bio.vehicleData as any,vehicle=await db.vehicle.findFirst({where:{driverId:driver.id,isActive:true},orderBy:{updatedAt:'desc'}});
  const name=(v:string)=>String(v||'').trim().replace(/\s+/g,' ').toUpperCase();
  return normalizePlate(driver.carNumber||'')!==data.plateNumber||name(driver.carModel)!==name(data.brand+' '+data.model)||!vehicle||normalizePlate(vehicle.plateNumber)!==data.plateNumber||name(vehicle.brand)!==name(data.brand)||name(vehicle.model)!==name(data.model)||vehicle.year!==data.year;
 }
 async status(userId:string) {
  const [user,profile]=await Promise.all([this.prisma.user.findUnique({where:{id:userId},select:{role:true,driverProfile:{select:{id:true}}}}),this.prisma.biometricProfile.findUnique({where:{userId},select:{status:true,enrolledAt:true,driverConsent:true}})]);
  if(!user)throw new UnauthorizedException();

  return {driver:!!user.driverProfile||user.role==='DRIVER',pendingEnrollment:false,enabled:await this.enabled(),required:await this.needsVerification(userId,user.role),enrolled:profile?.status==='VERIFIED',driverConsent:profile?.driverConsent??false,engineReady:await this.engine.ready(),consentVersion:IDENTITY_CONSENT};
 }
 async challenge(input:{userId?:string;phone?:string;password?:string;consentVersion:string;driverConsent?:boolean;ip:string}) {
  if(input.consentVersion!==IDENTITY_CONSENT)throw new BadRequestException('Подтвердите согласие на обработку биометрических данных');
  if(!await this.enabled()||!await this.engine.ready())throw new ServiceUnavailableException('Видеопроверка временно недоступна. Повторите позже.');
  const enrollment=!!input.userId;
  let user=await this.prisma.user.findUnique({where:enrollment?{id:input.userId}:{phone:input.phone},include:{biometricProfile:true}});
  const subjectHash=this.vault.digest('phone:'+(input.phone||user?.phone||'')),ipHash=this.vault.digest('ip:'+input.ip);
  const since=new Date(Date.now()-3600000);
  if(!enrollment){
  const [perUser,perIp]=await Promise.all([this.prisma.biometricChallenge.count({where:{purpose:'RECOVERY',subjectHash,createdAt:{gte:since}}}),this.prisma.biometricChallenge.count({where:{purpose:'RECOVERY',ipHash,createdAt:{gte:since}}})]);
  if(perUser>=5||perIp>=15)throw new ForbiddenException('Слишком много проверок. Повторите через час.');
  }
  if(enrollment){
   if(!user||user.blockedAt||user.role==='ADMIN'||!await bcrypt.compare(input.password||'',user.password))throw new UnauthorizedException('Неверный пароль аккаунта');
   if(user.role==='DRIVER' && input.driverConsent!==true)throw new BadRequestException('Подтвердите согласие на сверку с удостоверением личности');
   if(user.biometricProfile)throw new ConflictException('Видеопроверка уже пройдена. Эталон нельзя заменить через первичную регистрацию.');
  } else if(!user||user.blockedAt||user.role==='ADMIN'||user.phone.startsWith('erased:')||user.biometricProfile?.status!=='VERIFIED')user=null;
  const pool=['TURN_LEFT','TURN_RIGHT','LOOK_UP','OPEN_MOUTH','BLINK'];
  for(let i=pool.length-1;i>0;i--){const j=randomInt(i+1);[pool[i],pool[j]]=[pool[j],pool[i]];}
  const actions=pool.slice(0,enrollment?2:3),secret=token();
  const row=await this.prisma.biometricChallenge.create({data:{userId:user?.id||null,subjectHash,ipHash,purpose:enrollment?'ENROLL':'RECOVERY',secretHash:hash(secret),authVersion:user?.authVersion??0,actions,expiresAt:new Date(Date.now()+5*60000),consentVersion:IDENTITY_CONSENT,driverConsent:enrollment&&input.driverConsent===true}});
  return {challengeId:row.id,challengeToken:secret,actions,phaseSeconds:4,neutralSeconds:2,recordingSeconds:2+actions.length*6,expiresAt:row.expiresAt,consentVersion:IDENTITY_CONSENT};
 }
 private async getChallenge(id:string,secret:string){
  if(!/^[a-f0-9-]{36}$/i.test(id)||typeof secret!=='string'||secret.length>100)throw new UnauthorizedException(identityFailure);
  const c=await this.prisma.biometricChallenge.findFirst({where:{id,secretHash:hash(secret)}});
  if(!c||c.createdAt.getTime()<Date.now()-86400000)throw new UnauthorizedException(identityFailure);
  return c;
 }
 async submit(id:string,secret:string,video:Buffer,userId?:string) {
  const c=await this.getChallenge(id,secret);
  if(c.purpose==='ENROLL'&&c.userId!==userId)throw new UnauthorizedException();
  if(c.purpose==='ENROLL'&&c.consentVersion!==IDENTITY_CONSENT)throw new BadRequestException('Условия хранения первичной записи обновлены. Начните новую проверку и подтвердите согласие.');
  if(c.expiresAt<new Date()||c.status!=='READY')throw new ConflictException('Проверка истекла или уже использована. Начните новую запись.');
  if(!video||video.length<10000||video.length>16*1024*1024)throw new BadRequestException('Запишите видео с камеры, не более 16 МБ');
  let claimed;
  try { claimed=await this.prisma.biometricChallenge.updateMany({where:{id,status:'READY',expiresAt:{gt:new Date()}},data:{status:'PROCESSING',claimedAt:new Date(),videoDigest:this.vault.digest('video:'+hash(video)),attempts:{increment:1}}});
  } catch(error:any) { if(error.code==='P2002')throw new ForbiddenException('Эта запись уже использовалась. Снимите новое видео.');throw error; }
  if(claimed.count!==1)throw new ConflictException('Эта запись уже обрабатывается');
  let result;
  try{result=await this.engine.verify(video,c.actions as string[]);}catch(error){await this.prisma.biometricChallenge.update({where:{id},data:{status:'FAILED',reason:'Сервис проверки недоступен'}});throw error;}
  const user=c.userId?await this.prisma.user.findUnique({where:{id:c.userId},include:{biometricProfile:true}}):null;
  if(!user||user.blockedAt||user.authVersion!==c.authVersion||result.verdict==='REJECT'){
   await this.prisma.biometricChallenge.update({where:{id},data:{status:'REJECTED',reason:!user?'Проверка недоступна для аккаунта':result.reason}});return {status:'REJECTED',message:c.purpose==='ENROLL'&&user?result.reason:identityFailure};
  }
  if(result.videoSignature){
   const previous=await this.prisma.biometricChallenge.findMany({where:{userId:user.id,id:{not:id},videoSignature:{not:null},createdAt:{gte:new Date(Date.now()-7*86400000)}},select:{videoSignature:true},take:100});
   if(previous.some(p=>repeatedVideo(result.videoSignature!,JSON.parse(this.vault.open(Buffer.from(p.videoSignature!,'base64'),user.id).toString())))){
    await this.prisma.biometricChallenge.update({where:{id},data:{status:'REJECTED',reason:'Повтор ранее использованной записи'}});return {status:'REJECTED',message:c.purpose==='ENROLL'?'Эта запись уже использовалась. Запишите новое видео.':identityFailure};
   }
  }
  let verdict=result.verdict;let reviewReason=result.reason||'';
  if(c.purpose==='RECOVERY'){
   const profile=user.biometricProfile;
   if(!profile||profile.model!==result.model){verdict='REVIEW';reviewReason='Нужно уточнить совместимость эталона лица. Можно повторить запись или дождаться проверки.';}
   else{
    const reference=JSON.parse(this.vault.open(Buffer.from(profile.template,'base64'),user.id).toString()) as number[];
    const score=similarity(reference,result.embedding!);
    if(score<0.45){await this.prisma.biometricChallenge.update({where:{id},data:{status:'REJECTED',reason:'Лицо не совпадает с эталоном'}});return {status:'REJECTED',message:identityFailure};}
    if(score<0.60){verdict='REVIEW';reviewReason='Сходство с эталоном недостаточно уверенное. Смотрите прямо в камеру и повторите запись при ровном освещении.';}
    else if(confidentRecoveryMotion(result,score)){verdict='PASS';}
    else if(verdict==='REVIEW'){reviewReason='Лицо совпало с эталоном. '+(result.reason||'Не удалось уверенно проверить качество видеозаписи.');}
   }
  }
  if(c.purpose==='ENROLL'&&verdict==='REVIEW'){
   const reason=(result.reason||'Не удалось уверенно выполнить проверку')+'. Повторите запись: лицо в овале, ровный свет, выполняйте голосовые подсказки.';
   await this.prisma.biometricChallenge.update({where:{id},data:{status:'REJECTED',reason}});
   return {status:'REJECTED',message:reason,retryAllowed:true};
  }
  const referencePath=await this.vault.write(user.id,Buffer.from(result.reference!,'base64'));
  const candidate=this.vault.seal(Buffer.from(JSON.stringify(result.embedding)),user.id).toString('base64');
  let videoPath:string|null=null;
  try {
  videoPath=verdict==='REVIEW'||c.purpose==='ENROLL'?await this.vault.write(user.id,video):null;
  await this.prisma.$transaction(async tx=>{
   await tx.$executeRaw`SELECT id FROM "User" WHERE id=${user.id} FOR UPDATE`;
   const current=await tx.user.findUnique({where:{id:user.id}});
   if(!current||current.blockedAt||current.authVersion!==c.authVersion)throw new UnauthorizedException(identityFailure);
   if(c.purpose==='ENROLL'&&verdict==='PASS' && await tx.biometricProfile.findUnique({where:{userId:user.id}}))throw new ConflictException('Эталон уже создан. Повторная привязка не разрешена');
   if(c.purpose==='ENROLL'&&verdict==='PASS')await tx.biometricProfile.create({data:{userId:user.id,template:candidate,referencePath,referenceVideoPath:videoPath,model:result.model,consentVersion:c.consentVersion,driverConsent:c.driverConsent}});
   await tx.biometricChallenge.update({where:{id},data:{status:verdict==='PASS'?'VERIFIED':'REVIEW',videoSignature:result.videoSignature?this.vault.seal(Buffer.from(JSON.stringify(result.videoSignature)),user.id).toString('base64'):null,candidate:verdict==='REVIEW'?candidate:null,referencePath:c.purpose==='ENROLL'&&verdict==='PASS'?null:referencePath,videoPath:c.purpose==='ENROLL'&&verdict==='PASS'?null:videoPath,model:result.model,reason:verdict==='REVIEW'?reviewReason||'Нужна ручная проверка':null}});
  });
  } catch(error) {
   await Promise.allSettled([this.vault.remove(user.id,referencePath),...(videoPath?[this.vault.remove(user.id,videoPath)]:[])]);
   throw error;
  }
  if(verdict==='REVIEW')void this.push.notifyReviews().catch(()=>{});
  return this.challengeStatus(id,secret);
 }
 async challengeStatus(id:string,secret:string) {
  let c=await this.getChallenge(id,secret);
  if(c.status==='VERIFIED'&&c.purpose==='RECOVERY'){
   const user=c.userId?await this.prisma.user.findUnique({where:{id:c.userId}}):null;
   if(!user||user.blockedAt||user.authVersion!==c.authVersion||c.consumedAt)throw new UnauthorizedException(identityFailure);
   // A proof is derived from the secret only held by this camera session, never returned to admins.
   const proof=this.vault.digest('reset:'+c.id+':'+secret);
   if(!c.resetHash){const expires=new Date(Date.now()+10*60000);await this.prisma.biometricChallenge.updateMany({where:{id,resetHash:null,status:'VERIFIED'},data:{resetHash:hash(proof),resetExpiresAt:expires}});c=(await this.prisma.biometricChallenge.findUnique({where:{id}}))!;}
   if(!c.resetExpiresAt||c.resetExpiresAt<new Date())throw new UnauthorizedException('Разрешение на смену пароля истекло. Повторите видео.');
   return {status:'VERIFIED',resetToken:proof,message:'Личность подтверждена. Придумайте новый пароль.'};
  }
  return {status:c.status,message:c.status==='FAILED'?'Обработка прервана. Запишите новое видео.':c.status==='EXPIRED'?'Срок проверки истёк. Запишите новое видео.':c.status==='REVIEW'?(c.reason||'Не удалось уверенно завершить автоматическую проверку.')+' Можно записать новое видео или дождаться решения администратора.':c.status==='VERIFIED'?'Видеопроверка пройдена.':c.status==='REJECTED'?(c.purpose==='ENROLL'?c.reason||'Видеопроверка не пройдена':identityFailure):undefined};
 }
 async resetPassword(proof:string,password:string){
  if(!proof||proof.length!==64||!password||password.length<12||Buffer.byteLength(password)>72)throw new BadRequestException('Укажите разрешение проверки и новый пароль от 12 символов, не более 72 байт');
  const hashed=await bcrypt.hash(password,12);
  await this.prisma.$transaction(async tx=>{
   const c=await tx.biometricChallenge.findUnique({where:{resetHash:hash(proof)}});
   if(!c||!c.userId||c.purpose!=='RECOVERY'||c.status!=='VERIFIED'||c.consumedAt||!c.resetExpiresAt||c.resetExpiresAt<new Date())throw new UnauthorizedException(identityFailure);
   await tx.$executeRaw`SELECT id FROM "User" WHERE id=${c.userId} FOR UPDATE`;
   const user=await tx.user.findUnique({where:{id:c.userId}});
   if(!user||user.blockedAt||user.role==='ADMIN'||user.authVersion!==c.authVersion)throw new UnauthorizedException(identityFailure);
   const used=await tx.biometricChallenge.updateMany({where:{id:c.id,consumedAt:null,resetExpiresAt:{gt:new Date()}},data:{consumedAt:new Date(),status:'CONSUMED'}});
   if(used.count!==1)throw new UnauthorizedException(identityFailure);
   await tx.user.update({where:{id:user.id},data:{password:hashed,authVersion:{increment:1},mustChangePassword:false}});
   await tx.refreshToken.deleteMany({where:{userId:user.id}});
   await tx.biometricChallenge.updateMany({where:{userId:user.id,id:{not:c.id},status:{in:['READY','PROCESSING','REVIEW','VERIFIED']}},data:{status:'EXPIRED'}});
  });
  return {success:true};
 }
 async auditRead(id:string,adminId:string,kind:string){await this.prisma.adminAuditLog.create({data:{adminId,action:'identity.media.read',targetType:'BiometricChallenge',targetId:id,details:{kind}}});}
 async reviews(){return this.prisma.biometricChallenge.findMany({where:{status:'REVIEW',purpose:{not:'ENROLL'}},select:{id:true,purpose:true,reason:true,createdAt:true,actions:true,documentInfo:true,driverConsent:true,user:{select:{id:true,name:true,phone:true}}},orderBy:{createdAt:'asc'},take:100});}
 async reviewPurpose(id:string){return (await this.prisma.biometricChallenge.findUnique({where:{id},select:{purpose:true}}))?.purpose;}
 async reviewMedia(id:string,kind:string){
  const c=await this.prisma.biometricChallenge.findUnique({where:{id}});if(!c?.userId||c.status!=='REVIEW')throw new BadRequestException('Проверка не найдена');
  const file=kind==='video'?c.videoPath:kind==='back'?c.secondaryPath:kind==='candidate'?c.referencePath:(await this.prisma.biometricProfile.findUnique({where:{userId:c.userId}}))?.referencePath;
  if(!file)throw new BadRequestException('Эталон недоступен');
  return this.vault.read(c.userId,file);
 }
 async review(id:string,adminId:string,approve:boolean,reason:string){
  if(!reason||reason.trim().length<10||reason.length>1000)throw new BadRequestException('Опишите основание решения, от 10 символов');
  await this.prisma.$transaction(async tx=>{
   const c=await tx.biometricChallenge.findUnique({where:{id}});
   if(c?.purpose==='ENROLL')throw new ConflictException('Первичная проверка проходит автоматически. Запишите новое видео.');
   if(!c?.userId||c.status!=='REVIEW'||!c.candidate||!c.referencePath||!c.model||c.createdAt.getTime()<Date.now()-86400000)throw new ConflictException('Проверка недоступна или уже рассмотрена');
   await tx.$executeRaw`SELECT id FROM "User" WHERE id=${c.userId} FOR UPDATE`;
   const user=await tx.user.findUnique({where:{id:c.userId}});
   if(!user||user.blockedAt||user.authVersion!==c.authVersion)throw new ConflictException('Учётные данные изменились. Нужна новая запись');
   const changed=await tx.biometricChallenge.updateMany({where:{id,status:'REVIEW'},data:{status:approve?'VERIFIED':'REJECTED',reviewedBy:adminId,reviewedAt:new Date(),reason:reason.trim()}});
   if(changed.count!==1)throw new ConflictException('Проверка уже рассмотрена');
   await tx.adminAuditLog.create({data:{adminId,action:approve?'identity.review.approve':'identity.review.reject',targetType:'BiometricChallenge',targetId:id,details:{reason:reason.trim()}}});
  });
  return {success:true};
 }
 async maintenance(){
  await this.prisma.biometricChallenge.updateMany({where:{status:'PROCESSING',claimedAt:{lt:new Date(Date.now()-3*60000)}},data:{status:'FAILED',reason:'Обработка прервана. Нужна новая запись'}});
  await this.prisma.biometricChallenge.updateMany({where:{status:'REVIEW',createdAt:{lt:new Date(Date.now()-86400000)}},data:{status:'EXPIRED'}});
  const old=await this.prisma.biometricChallenge.findMany({where:{createdAt:{lt:new Date(Date.now()-7*86400000)}},take:100});
  for(const c of old){if(c.userId){for(const file of [c.videoPath,c.referencePath,c.secondaryPath])if(file)await this.vault.remove(c.userId,file);}await this.prisma.biometricChallenge.delete({where:{id:c.id}});}
  await this.push.notifyReviews();
 }
}
