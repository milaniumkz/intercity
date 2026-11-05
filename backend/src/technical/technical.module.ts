import {AccountDeletionModule} from '../auth/account-deletion.module';
import {IdentityModule} from '../identity/identity.module';
import { APP_INTERCEPTOR } from '@nestjs/core';
import { TechnicalEvidenceInterceptor } from './technical.interceptor';
import { Global, Module } from '@nestjs/common';
import { PrismaModule } from '../prisma.module';
import { TechnicalService } from './technical.service';
import {
    TechnicalController,
    TechnicalGuard,
    TechnicalPublicController,
    TechnicalClientController,
} from './technical.controller';
@Global()
@Module({
    imports: [PrismaModule, AccountDeletionModule, IdentityModule],
    controllers: [
        TechnicalPublicController,
        TechnicalController,
        TechnicalClientController,
    ],
    providers: [
        TechnicalService,
        TechnicalGuard,
        { provide: APP_INTERCEPTOR, useClass: TechnicalEvidenceInterceptor },
    ],
    exports: [TechnicalService],
})
export class TechnicalModule {}
