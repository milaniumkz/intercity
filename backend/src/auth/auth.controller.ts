import { AccountDeletionService } from './account-deletion.service';
import { IsString, MinLength, MaxLength } from 'class-validator';
class ChangePasswordDto { @IsString() @MinLength(1) @MaxLength(72) currentPassword: string; @IsString() @MinLength(12) @MaxLength(72) newPassword: string; }
class DeleteOwnAccountDto { @IsString() @MinLength(1) password: string; }
import { Controller, Query, Post, Body, Get, UseGuards, Request, Patch } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { AuthService } from './auth.service';
import { RegisterDto, LoginDto, RefreshTokenDto, ResetPasswordDto, SavePushTokenDto, UpdateMyCityDto } from './dto/auth.dto';
import { JwtAuthGuard } from './jwt-auth.guard';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
    constructor(private authService: AuthService, private accountDeletion: AccountDeletionService) { }

    @Post('register')
    @ApiOperation({ summary: 'Register new user' })
    async register(@Body() dto: RegisterDto) {
        return this.authService.register(dto);
    }

    @Post('login')
    @ApiOperation({ summary: 'Login user' })
    async login(@Body() dto: LoginDto, @Request() req) {
        const result = await this.authService.login(dto);
        req.techUserId=result.user.id;
        return result;
    }

    @Post('refresh')
    @ApiOperation({ summary: 'Refresh access token' })
    async refresh(@Body() dto: RefreshTokenDto) {
        return this.authService.refreshToken(dto.refreshToken);
    }

    @UseGuards(JwtAuthGuard)
    @Get('recovery/links')
    listRecoveryLinks(@Request() req) { return this.authService.recoveryLinks(req.user.sub); }

    @Post('recovery/admin-request')
    requestRecoveryHelp(@Body('phone') phone: string) {
        return this.authService.requestRecoveryHelp(phone);
    }

    @Post('recovery/provider/start')
    startRecovery(@Body('provider') provider:string) { return this.authService.startProvider(provider); }

    @Post('recovery/provider/verify')
    verifyRecovery(@Body() b:any) { return this.authService.finishProvider(b.provider,b.nonce,b.idToken); }

    @UseGuards(JwtAuthGuard)
    @Post('recovery/link/start')
    startLink(@Request() req,@Body('provider') provider:string) { return this.authService.startProvider(provider,req.user.sub); }

    @UseGuards(JwtAuthGuard)
    @Post('recovery/link/verify')
    verifyLink(@Request() req,@Body() b:any) { return this.authService.finishProvider(b.provider,b.nonce,b.idToken,req.user.sub,b.password); }

    @Post('recovery/password')
    completeRecovery(@Body() b:any) { return this.authService.completeRecovery(b.grant,b.password); }

    @Post('reset-password')
    @ApiOperation({ summary: 'Reset password by phone' })
    async resetPassword(@Body() dto: ResetPasswordDto) {
        return this.authService.resetPassword(dto);
    }

    @Post('change-password')
    @UseGuards(JwtAuthGuard)
    changePassword(@Request() req, @Body() dto: ChangePasswordDto) { return this.authService.changePassword(req.user.sub,dto.currentPassword,dto.newPassword); }

    @Post('delete-account')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    async deleteAccount(@Request() req, @Body() dto: DeleteOwnAccountDto) {
        return this.accountDeletion.deleteOwnAccount(req.user.sub, dto.password);
    }

    @Get('me')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Get current user' })
    async me(@Request() req) {
        return this.authService.validateUser(req.user.sub);
    }

    @Get('referral-validity')
    async referralValidity(@Query('code') code:string){return this.authService.referralValidity(String(code||''));}

    @Get('referral')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    async referral(@Request() req) { return this.authService.getReferralSummary(req.user.sub); }

    @Post('push-token')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Save/update user push token' })
    async savePushToken(@Request() req, @Body() dto: SavePushTokenDto) {
        return this.authService.savePushToken(req.user.sub, dto.token, dto.platform);
    }

    @Patch('me/city')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Update current user city' })
    async updateMyCity(@Request() req, @Body() dto: UpdateMyCityDto) {
        return this.authService.updateCurrentUserCity(req.user.sub, dto.cityId);
    }
}
