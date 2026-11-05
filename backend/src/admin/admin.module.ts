import {AccountDeletionModule} from '../auth/account-deletion.module';
import {OrdersModule} from '../orders/orders.module';
import {AdminPeopleController} from './admin-people.controller';
import {IntercityModule} from '../intercity/intercity.module';
import { IdentityModule } from '../identity/identity.module';
import { AdminIdentityController } from './admin-identity.controller';
import { Module } from '@nestjs/common';
import { AdminService } from './admin.service';
import { AdminController } from './admin.controller';
import { RealtimeModule } from '../realtime/realtime.module';
import { NotificationDispatchService } from './notification-dispatch.service';

@Module({
    imports: [RealtimeModule, IdentityModule, IntercityModule, OrdersModule, AccountDeletionModule],
    controllers: [AdminController, AdminIdentityController, AdminPeopleController],
    providers: [AdminService, NotificationDispatchService],
})
export class AdminModule { }
