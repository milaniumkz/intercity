import { DriverDocumentService } from '../identity/driver-document.service';
import { BadRequestException, Body, Controller, ForbiddenException, Get, Header, Param, Post, Request, Res, UseGuards } from '@nestjs/common';
import { IsBoolean, IsOptional, IsObject, IsString, MaxLength, MinLength } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { IdentityService } from '../identity/identity.service';
import { IdentityPushService } from '../identity/identity-push.service';
import { AdminService } from './admin.service';
class DecisionDto { @IsOptional() @IsObject() vehicle?:object; @IsBoolean() approve:boolean; @IsString() @MinLength(10) @MaxLength(1000) reason:string; }
@Controller('admin/identity') @UseGuards(JwtAuthGuard)
export class AdminIdentityController {
 constructor(private readonly identity:IdentityService,private readonly push:IdentityPushService,private readonly admin:AdminService,private readonly documents:DriverDocumentService){}
 private async permit(req:any){if(!await this.admin.adminHasPermission(req.user.sub,'identity.review',true))throw new ForbiddenException('Нет доступа к проверкам личности');}
 @Get('reviews') @Header('Cache-Control','no-store') async reviews(@Request() req){await this.permit(req);return this.identity.reviews();}
 @Get('reviews/:id/:kind') @Header('Cache-Control','no-store') async media(@Request() req,@Param('id') id:string,@Param('kind') kind:string,@Res() res:any){
  await this.permit(req);if(!['reference','candidate','video','back'].includes(kind))throw new BadRequestException();
  const bytes=await this.identity.reviewMedia(id,kind);
  await this.identity.auditRead(id,req.user.sub,kind);
  res.setHeader('X-Content-Type-Options','nosniff');res.type(kind==='video'?(bytes[0]===0x1a?'video/webm':'video/mp4'):'image/jpeg');res.send(bytes);
 }
 @Post('reviews/:id/decision') async decide(@Request() req,@Param('id') id:string,@Body() b:DecisionDto){await this.permit(req);const purpose=await this.identity.reviewPurpose(id);return purpose==='VEHICLE'||purpose==='DRIVER_IDENTITY'?this.documents.review(id,req.user.sub,b.approve,b.reason,b.vehicle):this.identity.review(id,req.user.sub,b.approve,b.reason);}
 @Get('push/key') async key(@Request() req){await this.permit(req);return {publicKey:this.push.publicKey()};}
 @Post('push/subscribe') async subscribe(@Request() req,@Body() body:any){await this.permit(req);try{return await this.push.subscribe(req.user.sub,body);}catch{throw new BadRequestException('Не удалось подключить push-уведомления');}}
}
