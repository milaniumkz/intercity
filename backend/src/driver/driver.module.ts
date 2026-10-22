import { OrdersModule } from '../orders/orders.module';
import { Module } from '@nestjs/common';
import { DriverService } from './driver.service';
import { DriverEarningsService } from './driver-earnings.service';
import { DriverController } from './driver.controller';
import { GeoModule } from '../geo/geo.module';
import { RealtimeModule } from '../realtime/realtime.module';

@Module({
    imports: [GeoModule, RealtimeModule, OrdersModule],
    controllers: [DriverController],
    providers: [DriverService, DriverEarningsService],
    exports: [DriverService],
})
export class DriverModule { }
