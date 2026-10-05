import { Module } from '@nestjs/common';
import { IntercityService } from './intercity.service';
import { IntercityController } from './intercity.controller';

@Module({
    controllers: [IntercityController],
    providers: [IntercityService],
})
export class IntercityModule { }
