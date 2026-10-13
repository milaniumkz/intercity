import { Global, Module } from '@nestjs/common';
import { TaxController } from './tax.controller';
import { TaxService } from './tax.service';

@Global()
@Module({ controllers: [TaxController], providers: [TaxService], exports: [TaxService] })
export class TaxModule {}
