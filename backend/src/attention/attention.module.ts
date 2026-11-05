import {Global,Module} from '@nestjs/common';import {PrismaModule} from '../prisma.module';import {IdentityModule} from '../identity/identity.module';import {AttentionService} from './attention.service';
@Global() @Module({imports:[PrismaModule,IdentityModule],providers:[AttentionService],exports:[AttentionService]})export class AttentionModule{}
