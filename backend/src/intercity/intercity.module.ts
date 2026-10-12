import { RealtimeModule } from '../realtime/realtime.module';
import { Module } from '@nestjs/common';
import { GeoModule } from '../geo/geo.module';
import { IntercityService } from './intercity.service';
import { IntercityController } from './intercity.controller';

@Module({
    imports: [GeoModule, RealtimeModule],
    controllers: [IntercityController],
    providers: [IntercityService],
})
export class IntercityModule { }
