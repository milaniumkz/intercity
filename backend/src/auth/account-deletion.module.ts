import {Module} from '@nestjs/common';
import {PrismaModule} from '../prisma.module';
import {AccountDeletionService} from './account-deletion.service';
@Module({imports:[PrismaModule],providers:[AccountDeletionService],exports:[AccountDeletionService]})
export class AccountDeletionModule {}
