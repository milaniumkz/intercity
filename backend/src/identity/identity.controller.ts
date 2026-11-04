import { DriverDocumentService } from './driver-document.service';
import { BadRequestException, Body, Controller, Get, Header, Param, Post, Request, UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { IsBoolean, IsOptional, IsString, IsUUID, Matches, MaxLength, MinLength } from 'class-validator';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { IdentityService } from './identity.service';
class ConsentDto { @IsString() @MaxLength(60) consentVersion:string; }
class EnrollDto extends ConsentDto { @IsString() @MinLength(1) @MaxLength(72) password:string; @IsOptional() @IsBoolean() driverConsent?:boolean; }
class RecoveryDto extends ConsentDto { @Matches(/^\+7\d{10}$/) phone:string; }
class ProofDto { @IsUUID() challengeId:string; @IsString() @MinLength(40) @MaxLength(100) challengeToken:string; }
class VideoProofDto { @IsString() @MinLength(40) @MaxLength(100) challengeToken:string; }
class ResetDto { @Matches(/^[a-f0-9]{64}$/) resetToken:string; @IsString() @MinLength(12) @MaxLength(72) password:string; }
@Controller('auth/identity')
@UseGuards(ThrottlerGuard)
export class IdentityController {
 constructor(private readonly identity:IdentityService,private readonly documents:DriverDocumentService){}
 @Get('status') @UseGuards(JwtAuthGuard) status(@Request() req){return this.identity.status(req.user.sub);}
 @Post('driver-consent') @UseGuards(JwtAuthGuard) @Throttle({default:{limit:5,ttl:60000}}) driverConsent(@Request() req,@Body() b:EnrollDto){if(b.consentVersion!=='intercity-face-2026-11-v1'||b.driverConsent!==true)throw new BadRequestException('Подтвердите согласие');return this.documents.consent(req.user.sub,b.password);}
 @Post('enroll') @UseGuards(JwtAuthGuard) @Throttle({default:{limit:5,ttl:60000}})
 enroll(@Request() req,@Body() b:EnrollDto){return this.identity.challenge({...b,userId:req.user.sub,ip:req.ip});}
 @Post('recovery') @Throttle({default:{limit:5,ttl:60000}})
 recovery(@Request() req,@Body() b:RecoveryDto){return this.identity.challenge({...b,ip:req.ip});}
 @Post('enroll/:id/video') @UseGuards(JwtAuthGuard) @Throttle({default:{limit:3,ttl:60000}})
 @UseInterceptors(FileInterceptor('video',{limits:{fileSize:16*1024*1024,files:1,fields:1}}))
 enrollVideo(@Request() req,@Param('id') id:string,@Body() b:VideoProofDto,@UploadedFile() file:any){return this.identity.submit(id,b.challengeToken,file?.buffer,req.user.sub);}
 @Post('recovery/:id/video') @Throttle({default:{limit:3,ttl:60000}})
 @UseInterceptors(FileInterceptor('video',{limits:{fileSize:16*1024*1024,files:1,fields:1}}))
 recoveryVideo(@Param('id') id:string,@Body() b:VideoProofDto,@UploadedFile() file:any){return this.identity.submit(id,b.challengeToken,file?.buffer);}
 @Post('challenge-status') @Throttle({default:{limit:30,ttl:60000}})
 challengeStatus(@Body() b:ProofDto){return this.identity.challengeStatus(b.challengeId,b.challengeToken);}
 @Post('reset-password') @Throttle({default:{limit:5,ttl:60000}})
 reset(@Body() b:ResetDto){return this.identity.resetPassword(b.resetToken,b.password);}
}
