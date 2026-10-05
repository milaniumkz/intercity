import { Module } from '@nestjs/common';
import { AdminService } from './admin.service';
import { AdminController } from './admin.controller';
import { RealtimeModule } from '../realtime/realtime.module';
import { NotificationDispatchService } from './notification-dispatch.service';

@Module({
    imports: [RealtimeModule],
    controllers: [AdminController],
    providers: [AdminService, NotificationDispatchService],
})
export class AdminModule { }
