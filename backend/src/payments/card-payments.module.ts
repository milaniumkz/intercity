import { Global, Module } from '@nestjs/common';
import { CardPaymentsService } from './card-payments.service';
import { CardPaymentsController } from './card-payments.controller';
import { RealtimeModule } from '../realtime/realtime.module';
@Global()
@Module({imports:[RealtimeModule],controllers:[CardPaymentsController],providers:[CardPaymentsService],exports:[CardPaymentsService]})
export class CardPaymentsModule { }
