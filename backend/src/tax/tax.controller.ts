import { Body, Controller, Get, Post, Request, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { DeclareTaxProfileDto } from './tax.dto';
import { TaxService } from './tax.service';

@Controller('tax')
@UseGuards(JwtAuthGuard)
export class TaxController {
    constructor(private readonly tax: TaxService) {}
    @Get('me') summary(@Request() req) { return this.tax.summary(req.user.sub); }
    @Post('profile') declare(@Request() req, @Body() dto: DeclareTaxProfileDto) { return this.tax.declare(req.user.sub, dto); }
    @Post('release') release(@Request() req) { return this.tax.release(req.user.sub); }
    @Post('collect-debt') collect(@Request() req) { return this.tax.collectDebt(req.user.sub); }
}
