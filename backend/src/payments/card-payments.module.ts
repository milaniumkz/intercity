import { VtbTripPaymentsService } from './vtb-trip-payments.service';
import { VtbTripPaymentsController } from './vtb-trip-payments.controller';
import { Global, Module } from '@nestjs/common';
import { CardPaymentsService } from './card-payments.service';
import { CardPaymentsController } from './card-payments.controller';
import { RealtimeModule } from '../realtime/realtime.module';
@Global()
@Module({imports:[RealtimeModule],controllers:[CardPaymentsController,VtbTripPaymentsController],providers:[CardPaymentsService,VtbTripPaymentsService],exports:[CardPaymentsService]})
export class CardPaymentsModule { }
