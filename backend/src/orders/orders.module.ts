import { Module } from '@nestjs/common';
import { OrdersService } from './orders.service';
import { OrdersController } from './orders.controller';
import { AutoDispatchService } from './auto-dispatch.service';
import { GeoModule } from '../geo/geo.module';
import { WalletModule } from '../wallet/wallet.module';
import { RealtimeModule } from '../realtime/realtime.module';

@Module({
    imports: [GeoModule, WalletModule, RealtimeModule],
    controllers: [OrdersController],
    providers: [OrdersService, AutoDispatchService],
    exports: [OrdersService],
})
export class OrdersModule { }
