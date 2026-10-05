import { Module } from '@nestjs/common';
import { VehicleCatalogController } from './vehicle-catalog.controller';
import { VehicleCatalogService } from './vehicle-catalog.service';

@Module({
    controllers: [VehicleCatalogController],
    providers: [VehicleCatalogService],
})
export class VehicleCatalogModule { }
