import { Controller, Get, Query, Request, Response, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { KASPI_IPS, KaspiService } from './kaspi.service';
@ApiTags('kaspi')
@Controller()
export class KaspiController {
    constructor(private readonly kaspi:KaspiService) {}
    @Get('payments/kaspi')
    @ApiOperation({summary:'Kaspi.kz provider protocol: check / pay; bank IP allowlist'})
    async callback(@Query() query:Record<string,unknown>,@Request() req,@Response() res) {
        res.setHeader('Cache-Control','no-store, no-cache, max-age=0');res.setHeader('Pragma','no-cache');
        // Only req.ip from the trusted single Caddy hop, never raw forwarded headers.
        const ip=(req.ip||'').replace(/^::ffff:/,'');
        if(!KASPI_IPS.includes(ip))return res.status(403).json({txn_id:typeof query.txn_id==='string'?query.txn_id:'',result:5,comment:'Доступ запрещён'});
        return res.status(200).json(await this.kaspi.process(query));
    }
    @Get('wallet/kaspi/instructions')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    async instructions(@Request() req){return this.kaspi.instructions(req.user.sub);}
}
