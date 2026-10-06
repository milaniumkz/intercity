import { Controller, Get, Post, Body, UseGuards, Request, Query } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { WalletService } from './wallet.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import {
    TopupRequestDto,
    PayoutRequestDto,
    BonusTransferDto,
    BonusTransferRecipientQueryDto,
} from './dto/wallet.dto';

@ApiTags('wallet')
@Controller('wallet')
export class WalletController {
    constructor(private walletService: WalletService) { }

    @Get()
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Get my wallet' })
    async getWallet(@Request() req, @Query('currency') currency?: string) {
        return this.walletService.getWallet(req.user.sub, currency);
    }

    @Post('topup-request')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Create topup request' })
    async createTopup(@Request() req, @Body() dto: TopupRequestDto) {
        return this.walletService.createTopupRequest(req.user.sub, dto, req.user.role);
    }

    @Post('topup/callback')
    @ApiOperation({ summary: 'Online topup payment callback' })
    async topupCallback(@Body() body: Record<string, any>) {
        return this.walletService.handleTopupPaymentCallback(body ?? {});
    }

    @Post('payout-request')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Create payout request' })
    async createPayout(@Request() req, @Body() dto: PayoutRequestDto) {
        return this.walletService.createPayoutRequest(req.user.sub, dto, req.user.role);
    }

    @Post('bonus-transfer')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Transfer bonus to another user by phone' })
    async transferBonus(@Request() req, @Body() dto: BonusTransferDto) {
        return this.walletService.transferBonusByPhone(req.user.sub, dto.phone, dto.amount, dto.currency);
    }

    @Get('bonus-transfer/recipient')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Preview bonus transfer recipient by phone' })
    async previewTransferRecipient(
        @Request() req,
        @Query() dto: BonusTransferRecipientQueryDto,
    ) {
        return this.walletService.previewBonusRecipient(req.user.sub, dto.phone);
    }
}
