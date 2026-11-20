import { Body, Controller, Get, HttpCode, Param, Post, Query, Redirect, Request, UseGuards } from '@nestjs/common';
import { IsIn, IsNumber, IsOptional, IsString, Matches } from 'class-validator';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { VtbSandboxService } from './vtb-sandbox.service';

export class VtbSandboxPaymentDto {
    @ApiProperty({ example: 100 }) @IsNumber() amount: number;
    @ApiProperty({ enum: ['RUB'] }) @IsIn(['RUB']) currency: 'RUB';
    @ApiPropertyOptional({ enum: ['TOPUP', 'TRIP_TEST'] }) @IsOptional() @IsIn(['TOPUP', 'TRIP_TEST']) purpose?: string;
    @ApiPropertyOptional() @IsOptional() @IsString() @Matches(/^[A-Za-z0-9_-]{1,80}$/) requestKey?: string;
}

@ApiTags('vtb-sandbox')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('wallet/vtb/sandbox')
export class VtbSandboxWalletController {
    constructor(private readonly service: VtbSandboxService) {}
    @Get() instructions(@Request() req) { return this.service.instructions(req.user.sub); }
    @Post('payments') create(@Request() req, @Body() body: VtbSandboxPaymentDto) { return this.service.create(req.user.sub, body); }
    @Post('payments/:id/check') check(@Request() req, @Param('id') id: string) { return this.service.check(req.user.sub, id); }
}

@ApiTags('vtb-sandbox')
@Controller('payments/vtb/sandbox')
export class VtbSandboxBankController {
    constructor(private readonly service: VtbSandboxService) {}
    @Get('return') @Redirect() async returnToApp(@Query('paymentId') id: string) { return { url: await this.service.returnTarget(id || ''), statusCode: 302 }; }
    @Get('callback') callbackGet(@Query() query: Record<string, any>) { return this.service.callback(query); }
    @Post('callback') @HttpCode(200) callbackPost(@Body() body: Record<string, any>) { return this.service.callback(body || {}); }
}
