import {MapTilesService} from './map-tiles';
import { Module } from '@nestjs/common';
import { KazakhstanAddressIndex } from './kz-address-index';
import { GeoService } from './geo.service';
import { GeoController } from './geo.controller';
import { RouteController } from './route.controller';

@Module({
    controllers: [GeoController, RouteController],
    providers: [GeoService, KazakhstanAddressIndex, MapTilesService],
    exports: [GeoService],
})
export class GeoModule { }
