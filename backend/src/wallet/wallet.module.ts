import { KaspiController } from './kaspi.controller';
import { KaspiService } from './kaspi.service';
import { Module } from '@nestjs/common';
import { WalletService } from './wallet.service';
import { WalletController } from './wallet.controller';

@Module({
    controllers: [WalletController, KaspiController],
    providers: [WalletService, KaspiService],
    exports: [WalletService],
})
export class WalletModule { }
