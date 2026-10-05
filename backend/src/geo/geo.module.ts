import { Module } from '@nestjs/common';
import { GeoService } from './geo.service';
import { GeoController } from './geo.controller';
import { RouteController } from './route.controller';

@Module({
    controllers: [GeoController, RouteController],
    providers: [GeoService],
    exports: [GeoService],
})
export class GeoModule { }
