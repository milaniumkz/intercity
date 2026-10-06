import { IsIn, IsNumber, IsOptional, IsString } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

class CurrencyDto {
    @ApiPropertyOptional({ enum: ['KZT', 'RUB'], default: 'KZT' })
    @IsOptional()
    @IsIn(['KZT', 'RUB'])
    currency?: string;
}

export class TopupRequestDto extends CurrencyDto {
    @ApiProperty()
    @IsNumber()
    amount: number;
}

export class PayoutRequestDto extends CurrencyDto {
    @ApiProperty()
    @IsNumber()
    amount: number;

    @ApiPropertyOptional({ example: '4400430154321098' })
    @IsOptional()
    @IsString()
    cardNumber?: string;
}

export class BonusTransferDto extends CurrencyDto {
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
