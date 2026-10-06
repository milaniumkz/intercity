import { Module } from '@nestjs/common';
import { GeoModule } from '../geo/geo.module';
import { RidesharingService } from './ridesharing.service';
import { RidesharingController } from './ridesharing.controller';

@Module({
    imports: [GeoModule],
    controllers: [RidesharingController],
    providers: [RidesharingService],
})
export class RidesharingModule { }
