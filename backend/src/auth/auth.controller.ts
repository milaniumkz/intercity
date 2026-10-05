import { Controller, Post, Body, Get, UseGuards, Request, Patch } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { AuthService } from './auth.service';
import { RegisterDto, LoginDto, RefreshTokenDto, ResetPasswordDto, SavePushTokenDto, UpdateMyCityDto } from './dto/auth.dto';
import { JwtAuthGuard } from './jwt-auth.guard';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
    constructor(private authService: AuthService) { }

    @Post('register')
    @ApiOperation({ summary: 'Register new user' })
    async register(@Body() dto: RegisterDto) {
        return this.authService.register(dto);
    }

    @Post('login')
    @ApiOperation({ summary: 'Login user' })
    async login(@Body() dto: LoginDto) {
        return this.authService.login(dto);
    }

    @Post('refresh')
    @ApiOperation({ summary: 'Refresh access token' })
    async refresh(@Body() dto: RefreshTokenDto) {
        return this.authService.refreshToken(dto.refreshToken);
    }

    @Post('reset-password')
    @ApiOperation({ summary: 'Reset password by phone' })
    async resetPassword(@Body() dto: ResetPasswordDto) {
        return this.authService.resetPassword(dto);
    }

    @Get('me')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Get current user' })
    async me(@Request() req) {
        return this.authService.validateUser(req.user.sub);
    }

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
