import { OrdersModule } from '../orders/orders.module';
import { Module } from '@nestjs/common';
import { DriverService } from './driver.service';
import { DriverController } from './driver.controller';
import { GeoModule } from '../geo/geo.module';
import { RealtimeModule } from '../realtime/realtime.module';

@Module({
    imports: [GeoModule, RealtimeModule, OrdersModule],
    controllers: [DriverController],
    providers: [DriverService],
    exports: [DriverService],
})
export class DriverModule { }
