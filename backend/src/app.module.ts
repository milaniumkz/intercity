import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { GeoModule } from './geo/geo.module';
import { OrdersModule } from './orders/orders.module';
import { DriverModule } from './driver/driver.module';
import { IntercityModule } from './intercity/intercity.module';
import { RidesharingModule } from './ridesharing/ridesharing.module';
import { WalletModule } from './wallet/wallet.module';
import { AdminModule } from './admin/admin.module';
import { RealtimeModule } from './realtime/realtime.module';
import { PrismaModule } from './prisma.module';
import { RealtimeController } from './realtime/realtime.controller';
import { NotificationsModule } from './notifications/notifications.module';
import { AppRuntimeController } from './app-runtime.controller';
import { VehicleCatalogModule } from './vehicle-catalog/vehicle-catalog.module';

@Module({
    imports: [
        ConfigModule.forRoot({
            isGlobal: true,
        }),
        ThrottlerModule.forRoot([{
            ttl: parseInt(process.env.THROTTLE_TTL_MS || '60000', 10),
            limit: parseInt(process.env.THROTTLE_LIMIT || '1500', 10),
        }]),
        AuthModule,
        UsersModule,
        GeoModule,
        OrdersModule,
        DriverModule,
        IntercityModule,
        RidesharingModule,
        WalletModule,
        AdminModule,
        RealtimeModule,
        PrismaModule,
        NotificationsModule,
        VehicleCatalogModule,
    ],
    controllers: [RealtimeController, AppRuntimeController],
})
export class AppModule { }
