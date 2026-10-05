import { Module } from '@nestjs/common';
import { RidesharingService } from './ridesharing.service';
import { RidesharingController } from './ridesharing.controller';

@Module({
    controllers: [RidesharingController],
    providers: [RidesharingService],
})
export class RidesharingModule { }
