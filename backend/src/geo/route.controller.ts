import { Controller, Get, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { GeoService } from './geo.service';

@ApiTags('geo')
@Controller()
export class RouteController {
    constructor(private geoService: GeoService) { }

    @Get('route')
    @ApiOperation({ summary: 'Build route between two points' })
    async getRoute(
        @Query('fromLat') fromLat: string,
        @Query('fromLng') fromLng: string,
        @Query('toLat') toLat: string,
        @Query('toLng') toLng: string,
    ) {
        return this.geoService.getRoute(
            parseFloat(fromLat),
            parseFloat(fromLng),
            parseFloat(toLat),
            parseFloat(toLng),
        );
    }
}
