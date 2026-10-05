import { Controller, Get, Post, Body, Param, UseGuards, Request, Query } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { RidesharingService } from './ridesharing.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

@ApiTags('ridesharing')
@Controller('ridesharing')
export class RidesharingController {
    constructor(private ridesharingService: RidesharingService) { }

    @Post('trips')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Create ride sharing trip' })
    async createTrip(@Request() req, @Body() body: any) {
        return this.ridesharingService.createTrip(req.user.sub, body);
    }

    @Get('trips/my')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Get my ride sharing trips' })
    async getMyTrips(@Request() req) {
        return this.ridesharingService.getDriverTrips(req.user.sub);
    }

    @Post('trips/:id/promote')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Promote my ride sharing trip to top' })
    async promoteTrip(@Request() req, @Param('id') id: string) {
        return this.ridesharingService.promoteTripToTop(req.user.sub, id);
    }

    @Get('trips/search')
    @ApiOperation({ summary: 'Search trips' })
    async searchTrips(
        @Query('fromCity') fromCity?: string,
        @Query('toCity') toCity?: string,
        @Query('date') date?: string,
    ) {
        return this.ridesharingService.searchTrips({
            fromCity,
            toCity,
            date: date ? new Date(date) : undefined,
        });
    }

    @Post('trips/:id/book')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Book trip' })
    async bookTrip(@Request() req, @Param('id') id: string, @Body() body: { seats: number }) {
        return this.ridesharingService.bookTrip(req.user.sub, id, body.seats);
    }
}
