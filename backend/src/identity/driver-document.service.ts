import { BadRequestException, Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { TechnicalService } from '../technical/technical.service';
import { IdentityService, IDENTITY_CONSENT, similarity } from './identity.service';
import { IdentityEngine } from './identity-engine';
import { IdentityPushService } from './identity-push.service';
import { randomBytes, createHash } from 'node:crypto';
import sharp from 'sharp';
import { parseVehicleDocument, validateVehicleData, VehicleData } from './vehicle-document';
const hash=(s:string)=>createHash('sha256').update(s).digest('hex');
@Injectable()
export class DriverDocumentService {
 constructor(private readonly prisma:PrismaService,private readonly identity:IdentityService,private readonly engine:IdentityEngine,private readonly technical:TechnicalService,private readonly push:IdentityPushService){}
 async consent(userId:string,password:string,consentVersion=IDENTITY_CONSENT){
  const bcrypt=await import('bcrypt');const user=await this.prisma.user.findUnique({where:{id:userId}});
  if(!user||user.blockedAt||!await bcrypt.compare(password,user.password))throw new BadRequestException('Неверный пароль');
  await this.prisma.biometricProfile.update({where:{userId},data:{driverConsent:true,consentVersion}});return {success:true};
 }
 private async source(userId:string,url:string|null|undefined){
  const id=/^\/api\/driver\/docs\/files\/([a-f0-9]{32})$/.exec(url||'')?.[1];
  if(!id)throw new BadRequestException('Загрузите документы через закрытое хранилище приложения');
  const file=await this.technical.fileBytes(id);
  if(file.row.userId!==userId||file.row.verdict==='REJECT')throw new BadRequestException('Недопустимый документ');
  return file;
 }
 async check(userId:string){
  if(!await this.identity.enabled())return {enabled:false};
  const bio=await this.prisma.biometricProfile.findUnique({where:{userId}}),driver=await this.prisma.driverProfile.findUnique({where:{userId}});
  if(!bio||bio.status!=='VERIFIED')throw new BadRequestException('Сначала пройдите видеопроверку личности');
  if(!bio.driverConsent)throw new BadRequestException('Подтвердите согласие на сверку лица с удостоверением личности');
  if(!driver)throw new BadRequestException('Профиль водителя не найден');
  await this.source(userId,driver.driverLicenseUrl);
  const passport=await this.source(userId,driver.passportUrl),front=await this.source(userId,driver.techPassportFrontUrl),back=driver.techPassportBackUrl?await this.source(userId,driver.techPassportBackUrl):null;
  const vehicleHash=hash([front.row.sha256,back?.row.sha256||''].join(':'));
  let identityStatus=bio.driverDocumentHash===passport.row.sha256?'VERIFIED':'REVIEW',vehicleStatus=bio.vehicleDocumentHash===vehicleHash&&bio.vehicleData?'VERIFIED':'REVIEW';
  if(identityStatus!=='VERIFIED'){
   const previous=await this.existing(userId,'DRIVER_IDENTITY',passport.row.sha256);
   if(previous)identityStatus=previous.status;
   else {
    let doc:any;try{doc=await this.engine.document(passport.buffer,'face');}catch{doc={model:bio.model,reference:(await sharp(passport.buffer).rotate().resize({width:1400,height:1400,fit:'inside',withoutEnlargement:true}).jpeg({quality:85}).toBuffer()).toString('base64')};}
    const template=JSON.parse(this.identity.vault.open(Buffer.from(bio.template,'base64'),userId).toString());
    const score=doc.embedding&&doc.model===bio.model?similarity(template,doc.embedding):null;
    identityStatus=score!==null&&score<.45?'REJECTED':score!==null&&score>=.60&&doc.quality===true?'VERIFIED':'REVIEW';
    await this.store(userId,'DRIVER_IDENTITY',passport.row.sha256,identityStatus,doc.reference,doc.model,{sources:[{docType:'passport',id:passport.row.id,sha:passport.row.sha256}]},identityStatus==='REJECTED'?'Лицо в удостоверении не совпадает с видеоэталоном':identityStatus==='REVIEW'?'Не удалось уверенно сверить лицо в удостоверении':'');
   }
  }
  let vehicle:VehicleData|null=vehicleStatus==='VERIFIED'?validateVehicleData(bio.vehicleData):null;
  if(vehicleStatus!=='VERIFIED'){
   const previous=await this.existing(userId,'VEHICLE',vehicleHash);
   if(previous)vehicleStatus=previous.status;
   else {
    const catalogue=await this.prisma.carMake.findMany({include:{models:{select:{name:true}}}});
    const read=async(buffer:Buffer)=>{try{return await this.engine.document(buffer,'vehicle');}catch{return {lines:[],model:'tesseract-local-rus-kaz-eng-v1',reference:(await sharp(buffer).rotate().resize({width:1400,height:1400,fit:'inside',withoutEnlargement:true}).jpeg({quality:85}).toBuffer()).toString('base64')};}};
    const frontResult=await read(front.buffer),backResult=back?await read(back.buffer):null;
    const first=parseVehicleDocument(frontResult.lines||[],catalogue),second=backResult?parseVehicleDocument(backResult.lines||[],catalogue):null;
    // Conflicting sides are never guessed. A complete, high-confidence side is required.
    vehicle=first&&second&&JSON.stringify(first)!==JSON.stringify(second)?null:first||second;
    vehicleStatus=vehicle?'VERIFIED':'REVIEW';
    await this.store(userId,'VEHICLE',vehicleHash,vehicleStatus,frontResult.reference,frontResult.model,{sources:[{docType:'techPassportFront',id:front.row.id,sha:front.row.sha256},...(back?[{docType:'techPassportBack',id:back.row.id,sha:back.row.sha256}]:[])],...(vehicle?{vehicle}:{})},vehicle?'':'Не удалось уверенно прочитать госномер, марку, модель или год. Нужна ручная проверка.',backResult?.reference);
   }
  }
  if(vehicle)await this.applyVehicle(this.prisma,userId,vehicleHash,vehicle,{front:driver.techPassportFrontUrl,back:driver.techPassportBackUrl});
  return {enabled:true,identityStatus,vehicleStatus,vehicle,message:identityStatus==='REJECTED'?'Лицо не совпадает с удостоверением. Доступ водителя не подтверждён.':identityStatus==='REVIEW'||vehicleStatus==='REVIEW'?'Документы направлены на ручную проверку.':'Лицо сверено с удостоверением, данные автомобиля прочитаны из техпаспорта. Подлинность документов рассматривает администратор.'};
 }
 private async existing(userId:string,purpose:string,documentHash:string){
  const row=await this.prisma.biometricChallenge.findFirst({where:{userId,purpose,status:{in:['REVIEW','REJECTED','VERIFIED']},documentInfo:{path:['hash'],equals:documentHash}},orderBy:{createdAt:'desc'}});return row;
 }
 private async store(userId:string,purpose:string,documentHash:string,status:string,reference:string,model:string,info:any,reason:string,secondary?:string){
  const user=await this.prisma.user.findUnique({where:{id:userId}});if(!user)throw new BadRequestException('Аккаунт недоступен');
  const referencePath=status==='REVIEW'?await this.identity.vault.write(userId,Buffer.from(reference,'base64')):null;
  const secondaryPath=status==='REVIEW'&&secondary?await this.identity.vault.write(userId,Buffer.from(secondary,'base64')):null;
  await this.prisma.$transaction(async tx=>{
   await tx.$executeRaw`SELECT id FROM "User" WHERE id=${userId} FOR UPDATE`;
   if(status==='VERIFIED'&&purpose==='DRIVER_IDENTITY')await tx.biometricProfile.update({where:{userId},data:{driverDocumentHash:documentHash}});
   await tx.biometricChallenge.create({data:{userId,subjectHash:this.identity.vault.digest('user:'+userId),ipHash:'internal-document-check',purpose,secretHash:hash(randomBytes(32).toString('hex')),actions:[],authVersion:user.authVersion,expiresAt:new Date(Date.now()+86400000),status,referencePath,secondaryPath,model,reason:reason||null,consentVersion:IDENTITY_CONSENT,driverConsent:true,documentInfo:{...info,hash:documentHash}}});
  });
  if(status==='REVIEW')void this.push.notifyReviews().catch(()=>{});
 }
 async assertVerified(userId:string,db:any=this.prisma){if(await this.identity.driverDocumentsRequired(userId,db))throw new BadRequestException('Пройдите сверку лица с удостоверением и проверку автомобиля в разделе документов');}
 async applyVehicle(db:any,userId:string,documentHash:string,data:VehicleData,expected?:{front:string|null;back:string|null}){
  const apply=async(tx:any)=>{
   await tx.$executeRaw`SELECT id FROM "User" WHERE id=${userId} FOR UPDATE`;
   const driver=await tx.driverProfile.findUnique({where:{userId}});if(!driver)throw new BadRequestException('Профиль водителя не найден');
   if(expected&&(driver.techPassportFrontUrl!==expected.front||driver.techPassportBackUrl!==expected.back))throw new BadRequestException('Документ изменился. Повторите проверку');
   await tx.driverProfile.update({where:{userId},data:{carModel:`${data.brand} ${data.model}`,carNumber:data.plateNumber}});
   await tx.vehicle.updateMany({where:{driverId:driver.id,plateNumber:{not:data.plateNumber}},data:{isActive:false}});
   await tx.vehicle.upsert({where:{driverId_plateNumber:{driverId:driver.id,plateNumber:data.plateNumber}},create:{driverId:driver.id,...data,isActive:true,verificationStatus:'PENDING'},update:{...data,isActive:true,verificationStatus:'PENDING'}});
   await tx.biometricProfile.update({where:{userId},data:{vehicleDocumentHash:documentHash,vehicleData:data}});
  };
  if(db.$transaction)await db.$transaction(apply);else await apply(db);
 }
 private validated(value:unknown){try{return validateVehicleData(value);}catch(e:any){throw new BadRequestException(e.message);}}
 async review(id:string,adminId:string,approve:boolean,reason:string,vehicle?:unknown){
  if(!reason||reason.trim().length<10||reason.length>1000)throw new BadRequestException('Укажите основание решения');
  await this.prisma.$transaction(async tx=>{
   const c=await tx.biometricChallenge.findUnique({where:{id}});
   if(!c?.userId||!['DRIVER_IDENTITY','VEHICLE'].includes(c.purpose)||c.status!=='REVIEW'||c.createdAt.getTime()<Date.now()-86400000)throw new BadRequestException('Проверка недоступна');
   await tx.$executeRaw`SELECT id FROM "User" WHERE id=${c.userId} FOR UPDATE`;
   const user=await tx.user.findUnique({where:{id:c.userId}});if(!user||user.blockedAt)throw new BadRequestException('Аккаунт недоступен');
   const info=c.documentInfo as any,driver=await tx.driverProfile.findUnique({where:{userId:c.userId}});
   if(!driver)throw new BadRequestException('Профиль водителя не найден');
   for(const source of info.sources){const current=driver[source.docType==='passport'?'passportUrl':source.docType==='techPassportFront'?'techPassportFrontUrl':'techPassportBackUrl'];if(current!==`/api/driver/docs/files/${source.id}`)throw new BadRequestException('Документ изменился. Запустите новую проверку');}
   const changed=await tx.biometricChallenge.updateMany({where:{id,status:'REVIEW'},data:{status:approve?'VERIFIED':'REJECTED',reviewedBy:adminId,reviewedAt:new Date(),reason:reason.trim()}});if(changed.count!==1)throw new BadRequestException('Проверка уже рассмотрена');
   if(approve){if(c.purpose==='VEHICLE')await this.applyVehicle(tx,c.userId,info.hash,this.validated(vehicle));else await tx.biometricProfile.update({where:{userId:c.userId},data:{driverDocumentHash:info.hash}});}
   await tx.adminAuditLog.create({data:{adminId,action:approve?'identity.document.approve':'identity.document.reject',targetType:'BiometricChallenge',targetId:id,details:{reason:reason.trim()}}});
  });return {success:true};
 }
}
