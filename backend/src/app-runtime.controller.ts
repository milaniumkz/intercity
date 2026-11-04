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

    private testFlightUrl(value?: string) {
        const url = this.storeUrl(value, 'testflight.apple.com');
        return url && /^\/join\/[A-Za-z0-9]+\/?$/.test(new URL(url).pathname) ? url : null;
    }

    @Get('runtime-settings')
    @ApiOperation({ summary: 'Get public runtime settings for mobile apps' })
    async getRuntimeSettings() {
        const keys = ['passengerMapHomeEnabled', 'appStoreUrl', 'googlePlayUrl', 'testFlightUrl', 'iosDistributionMode', 'driverTaxIntegrationPaused'];
        const settings = await this.prisma.appSettings.findMany({
            where: { key: { in: keys } },
        });
        const byKey = new Map(settings.map((item) => [item.key, item.value]));
        return {
            driverTaxIntegrationPaused: byKey.get('driverTaxIntegrationPaused') === 'true',
            iosDistributionMode: ['web','testflight','appstore'].includes(byKey.get('iosDistributionMode')) ? byKey.get('iosDistributionMode') : 'web',
            appStoreUrl: this.storeUrl(byKey.get('appStoreUrl'), 'apps.apple.com'),
            testFlightUrl: this.testFlightUrl(byKey.get('testFlightUrl')),
            googlePlayUrl: this.storeUrl(byKey.get('googlePlayUrl'), 'play.google.com'),
            passengerMapHomeEnabled: (byKey.get('passengerMapHomeEnabled') ?? 'true').toLowerCase() !== 'false',
        };
    }
}
