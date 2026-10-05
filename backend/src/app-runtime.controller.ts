import { Controller, Get } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { PrismaService } from './prisma.service';

@ApiTags('app')
@Controller('app')
export class AppRuntimeController {
    constructor(private prisma: PrismaService) { }

    @Get('runtime-settings')
    @ApiOperation({ summary: 'Get public runtime settings for mobile apps' })
    async getRuntimeSettings() {
        const keys = ['passengerMapHomeEnabled'];
        const settings = await this.prisma.appSettings.findMany({
            where: { key: { in: keys } },
        });
        const byKey = new Map(settings.map((item) => [item.key, item.value]));
        return {
            passengerMapHomeEnabled: (byKey.get('passengerMapHomeEnabled') ?? 'true').toLowerCase() !== 'false',
        };
    }
}
