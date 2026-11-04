import { DriverDocumentService } from './driver-document.service';
import { Module } from '@nestjs/common';
import { IdentityService } from './identity.service';
import { IdentityEngine } from './identity-engine';
import { IdentityPushService } from './identity-push.service';
import { IdentityController } from './identity.controller';
import { PrismaModule } from '../prisma.module';
@Module({imports:[PrismaModule],providers:[IdentityService,IdentityEngine,IdentityPushService,DriverDocumentService],controllers:[IdentityController],exports:[IdentityService,IdentityPushService,DriverDocumentService]})
export class IdentityModule {}
