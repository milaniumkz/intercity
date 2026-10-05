import { IsNumber, IsOptional, IsString } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class TopupRequestDto {
    @ApiProperty()
    @IsNumber()
    amount: number;
}

export class PayoutRequestDto {
    @ApiProperty()
    @IsNumber()
    amount: number;

    @ApiPropertyOptional({ example: '4400430154321098' })
    @IsOptional()
    @IsString()
    cardNumber?: string;
}

export class BonusTransferDto {
    @ApiProperty({ example: '+77001234567' })
    @IsString()
    phone: string;

    @ApiProperty({ example: 500 })
    @IsNumber()
    amount: number;
}

export class BonusTransferRecipientQueryDto {
    @ApiProperty({ example: '+77001234567' })
    @IsString()
    phone: string;
}
