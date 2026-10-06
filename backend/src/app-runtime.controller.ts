import { Controller, Get } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { PrismaService } from './prisma.service';

@ApiTags('app')
@Controller('app')
export class AppRuntimeController {
    constructor(private prisma: PrismaService) { }

    private storeUrl(value: string | undefined, host: string) {
        try { const url = new URL(value); return url.protocol === 'https:' && url.hostname === host ? url.toString() : null; }
        catch { return null; }
    }

    @Get('runtime-settings')
    @ApiOperation({ summary: 'Get public runtime settings for mobile apps' })
    async getRuntimeSettings() {
        const keys = ['passengerMapHomeEnabled', 'appStoreUrl', 'googlePlayUrl'];
        const settings = await this.prisma.appSettings.findMany({
            where: { key: { in: keys } },
        });
        const byKey = new Map(settings.map((item) => [item.key, item.value]));
        return {
            appStoreUrl: this.storeUrl(byKey.get('appStoreUrl'), 'apps.apple.com'),
            googlePlayUrl: this.storeUrl(byKey.get('googlePlayUrl'), 'play.google.com'),
            passengerMapHomeEnabled: (byKey.get('passengerMapHomeEnabled') ?? 'true').toLowerCase() !== 'false',
        };
    }
}
