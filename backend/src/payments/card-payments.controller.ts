import { Controller, Get, Post, Patch, Delete, Param, Body, Request, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CardPaymentsService } from './card-payments.service';
@Controller('payments')
export class CardPaymentsController {
    constructor(private readonly payments:CardPaymentsService) { }
    @Get('cards') @UseGuards(JwtAuthGuard)
    cards(@Request() req) { return this.payments.listCards(req.user.sub); }
    @Post('cards/bind') @UseGuards(JwtAuthGuard)
    bind(@Request() req) { return this.payments.bind(req.user.sub); }
    @Post('cards/sync') @UseGuards(JwtAuthGuard)
    sync(@Request() req) { return this.payments.syncCards(req.user.sub); }
    @Patch('cards/:id/default') @UseGuards(JwtAuthGuard)
    select(@Request() req,@Param('id') id:string) { return this.payments.selectCard(req.user.sub,id); }
    @Delete('cards/:id') @UseGuards(JwtAuthGuard)
    remove(@Request() req,@Param('id') id:string) { return this.payments.removeCard(req.user.sub,id); }
    @Post('callback')
    // Callback is only a wake-up hint. Every decision uses authenticated provider status.
    async callback(@Body() body:any) { await this.payments.callback(String(body?.orderId ?? '')); return {ok:true}; }
}
