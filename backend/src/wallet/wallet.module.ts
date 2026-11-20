import { VtbSandboxService } from './vtb-sandbox.service';
import { VtbSandboxBankController, VtbSandboxWalletController } from './vtb-sandbox.controller';
import { KaspiController } from './kaspi.controller';
import { KaspiService } from './kaspi.service';
import { Module } from '@nestjs/common';
import { WalletService } from './wallet.service';
import { WalletController } from './wallet.controller';

@Module({
    controllers: [WalletController, KaspiController, VtbSandboxWalletController, VtbSandboxBankController],
    providers: [WalletService, KaspiService, VtbSandboxService],
    exports: [WalletService],
})
export class WalletModule { }
