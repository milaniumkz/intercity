import { Controller, Post, Get, Body, Param, UseGuards, Request, UploadedFile, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { DriverService } from './driver.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import {
    CreateDriverProfileDto,
    UpdateLocationDto,
    SetOnlineDto,
    DriverDocsUploadUrlDto,
    CompleteDriverDocsDto,
    DriverIntercityRouteDto,
} from './dto/driver.dto';

@ApiTags('driver')
@Controller('driver')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class DriverController {
    constructor(private driverService: DriverService) { }

    @Post('profile')
    @ApiOperation({ summary: 'Create/update driver profile' })
    async createProfile(@Request() req, @Body() dto: CreateDriverProfileDto) {
        return this.driverService.createProfile(req.user.sub, dto);
    }

    @Post('location')
    @ApiOperation({ summary: 'Update driver location' })
    async updateLocation(@Request() req, @Body() dto: UpdateLocationDto) {
        return this.driverService.updateLocation(req.user.sub, dto);
    }

    @Post('online')
    @ApiOperation({ summary: 'Set driver online status' })
    async setOnline(@Request() req, @Body() dto: SetOnlineDto) {
        return this.driverService.setOnline(req.user.sub, dto);
    }

    @Get('profile')
    @ApiOperation({ summary: 'Get my driver profile' })
    async getMyProfile(@Request() req) {
        return this.driverService.getMyProfile(req.user.sub);
    }

    @Get('runtime-settings')
    @ApiOperation({ summary: 'Get runtime settings for driver app' })
    async getRuntimeSettings(@Request() req) {
        await this.driverService.getMyProfile(req.user.sub);
        return this.driverService.getRuntimeSettings();
    }

    @Get('orders/nearby')
    @ApiOperation({ summary: 'Get nearby orders' })
    async getNearbyOrders(@Request() req) {
        return this.driverService.getNearbyOrders(req.user.sub);
    }

    @Get('intercity/active')
    @ApiOperation({ summary: 'Get active intercity work for driver' })
    async getActiveIntercity(@Request() req) {
        return this.driverService.getActiveIntercity(req.user.sub);
    }

    @Get('intercity/routes')
    @ApiOperation({ summary: 'Get driver intercity route applications' })
    async getIntercityRoutes(@Request() req) {
        return this.driverService.getIntercityRoutes(req.user.sub);
    }

    @Post('intercity/routes')
    @ApiOperation({ summary: 'Apply for an intercity route' })
    async addIntercityRoute(@Request() req, @Body() dto: DriverIntercityRouteDto) {
        return this.driverService.addIntercityRoute(req.user.sub, dto);
    }

    @Post('intercity/routes/:id/delete')
    @ApiOperation({ summary: 'Disable driver intercity route application' })
    async deleteIntercityRoute(@Request() req, @Param('id') id: string) {
        return this.driverService.deleteIntercityRoute(req.user.sub, id);
    }

    @Post('orders/:id/accept')
    @ApiOperation({ summary: 'Accept order' })
    async acceptOrder(@Request() req, @Param('id') id: string) {
        return this.driverService.acceptOrder(req.user.sub, id);
    }

    @Post('orders/:id/reject')
    @ApiOperation({ summary: 'Reject order (with activity penalty)' })
    async rejectOrder(@Request() req, @Param('id') id: string) {
        return this.driverService.rejectOrder(req.user.sub, id);
    }

    @Post('docs/upload-url')
    @ApiOperation({ summary: 'Get document upload URL' })
    async getUploadUrl(@Request() req, @Body() body: DriverDocsUploadUrlDto) {
        return this.driverService.getUploadUrl(req.user.sub, body);
    }

    @Post('docs/upload')
    @UseInterceptors(FileInterceptor('file'))
    @ApiOperation({ summary: 'Upload driver document' })
    async uploadDoc(@Request() req, @Body() body: DriverDocsUploadUrlDto, @UploadedFile() file: any) {
        return this.driverService.uploadDoc(req.user.sub, body?.docType, file);
    }

    @Post('docs/complete')
    @ApiOperation({ summary: 'Complete document upload' })
    async completeDocs(@Request() req, @Body() body: CompleteDriverDocsDto) {
        return this.driverService.completeDocs(req.user.sub, body);
    }
}
