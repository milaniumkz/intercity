import { Controller, Get, Request, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from './jwt-auth.guard';
import { AuthService } from './auth.service';

@ApiTags('auth')
@Controller()
export class MeController {
    constructor(private authService: AuthService) { }

    @Get('me')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Get current user (root endpoint)' })
    async me(@Request() req) {
        return this.authService.validateUser(req.user.sub);
    }
}
