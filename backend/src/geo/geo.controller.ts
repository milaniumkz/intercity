import { Body, Controller, Get, Post, Query } from '@nestjs/common';
import { ApiTags, ApiOperation } from '@nestjs/swagger';
import { GeoService } from './geo.service';

@ApiTags('geo')
@Controller('geo')
export class GeoController {
    constructor(private geoService: GeoService) { }

    @Get('reverse')
    @ApiOperation({ summary: 'Reverse geocode coordinates to address' })
    async reverse(@Query('lat') lat: string, @Query('lng') lng: string) {
        return this.geoService.reverseGeocode(parseFloat(lat), parseFloat(lng));
    }

    @Get('search')
    @ApiOperation({ summary: 'Search locations by query' })
    async search(
        @Query('q') query: string,
        @Query('lat') lat?: string,
        @Query('lng') lng?: string,
        @Query('cityId') cityId?: string,
        @Query('type') type?: string,
    ) {
        const nearLat = lat ? parseFloat(lat) : undefined;
        const nearLng = lng ? parseFloat(lng) : undefined;
        const hasNear = Number.isFinite(nearLat) && Number.isFinite(nearLng);
        if ((type || '').trim().toLowerCase() === 'city') {
            return this.geoService.searchCities(query);
        }
        return this.geoService.searchLocations(
            query,
            hasNear ? nearLat : undefined,
            hasNear ? nearLng : undefined,
            cityId?.trim() || undefined,
        );
    }

    @Post('search')
    @ApiOperation({ summary: 'Search locations by query' })
    async searchPost(@Body() body: any) {
        const query = (body?.q ?? body?.query ?? '').toString();
        const lat = body?.lat ?? body?.latitude;
        const lng = body?.lng ?? body?.longitude;
        const cityId = (body?.cityId ?? '').toString().trim();
        const type = (body?.type ?? '').toString().trim().toLowerCase();
        const nearLat = lat !== undefined ? parseFloat(lat) : undefined;
        const nearLng = lng !== undefined ? parseFloat(lng) : undefined;
        const hasNear = Number.isFinite(nearLat) && Number.isFinite(nearLng);
        if (type === 'city') {
            return this.geoService.searchCities(query);
        }
        return this.geoService.searchLocations(
            query,
            hasNear ? nearLat : undefined,
            hasNear ? nearLng : undefined,
            cityId || undefined,
        );
    }

    @Get('cities')
    @ApiOperation({ summary: 'List active cities for user selection' })
    async cities() {
        return this.geoService.listActiveCities();
    }
}
