import { Controller, Get, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { VehicleCatalogService } from './vehicle-catalog.service';

@ApiTags('vehicle-catalog')
@Controller('vehicle-catalog')
export class VehicleCatalogController {
    constructor(private readonly service: VehicleCatalogService) { }

    @Get('makes')
    @ApiOperation({ summary: 'Get car makes' })
    getMakes() {
        return this.service.getMakes();
    }

    @Get('models')
    @ApiOperation({ summary: 'Get car models by make' })
    getModels(@Query('make') make = '') {
        return this.service.getModels(make);
    }
}
