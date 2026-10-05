import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
    private readonly logger = new Logger(PrismaService.name);

    async onModuleInit() {
        try {
            await this.$connect();
            this.logger.log('Prisma connected');
        } catch (error) {
            this.logger.error(
                'Prisma connection failed during bootstrap. Service will start and retry on next DB operation.',
                error instanceof Error ? error.stack : String(error),
            );
        }
    }

    async onModuleDestroy() {
        await this.$disconnect();
    }
}
