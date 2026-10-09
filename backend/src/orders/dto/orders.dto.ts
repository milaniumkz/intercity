import {
    IsString,
    IsInt,
    MaxLength,
    IsNumber,
    IsOptional,
    IsBoolean,
    IsEnum,
    Max,
    Min,
    IsIn,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class CreateOrderDto {
    @ApiProperty()
    @IsNumber()
    fromLat: number;

    @ApiProperty()
    @IsNumber()
    fromLng: number;

    @ApiProperty()
    @IsString()
    fromAddress: string;

    @ApiProperty()
    @IsNumber()
    toLat: number;

    @ApiProperty()
    @IsNumber()
    toLng: number;

    @ApiProperty()
    @IsString()
    toAddress: string;

    @ApiPropertyOptional({ enum: ['CITY', 'INTERCITY', 'CARGO', 'DELIVERY'] })
    @IsOptional()
    @IsEnum(['CITY', 'INTERCITY', 'CARGO', 'DELIVERY'])
    mode?: 'CITY' | 'INTERCITY' | 'CARGO' | 'DELIVERY';

    @ApiPropertyOptional({
        enum: [
            'CITY_FIXED',
            'CITY_AUCTION',
            'INTERCITY',
            'DELIVERY_CITY',
            'DELIVERY_INTERCITY',
            'DELIVERY_RF',
        ],
    })
    @IsOptional()
    @IsIn([
        'CITY_FIXED',
        'CITY_AUCTION',
        'INTERCITY',
        'DELIVERY_CITY',
        'DELIVERY_INTERCITY',
        'DELIVERY_RF',
    ])
    requestType?: string;

    @ApiPropertyOptional()
    @IsOptional()
    @IsBoolean()
    doorToDoor?: boolean;

    @ApiPropertyOptional({ description: 'Use wallet bonus balance for payment' })
    @IsOptional()
    @IsBoolean()
    useBonus?: boolean;

    @ApiPropertyOptional({ enum: ['CASH', 'CARD_TRANSFER', 'BONUSES'] })
    @IsOptional()
    @IsIn(['CASH', 'CARD_TRANSFER', 'BONUSES'])
    paymentMethod?: string;

    @ApiPropertyOptional({ enum: ['ECONOMY', 'OPTIMAL', 'COMFORT', 'BUSINESS'] })
    @IsOptional()
    @IsIn(['ECONOMY', 'OPTIMAL', 'COMFORT', 'BUSINESS'])
    vehicleClass?: string;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    comment?: string;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    tariffId?: string;
}

export class PreviewOrderDto {
    @ApiProperty()
    @IsNumber()
    fromLat: number;

    @ApiProperty()
    @IsNumber()
    fromLng: number;

    @ApiProperty()
    @IsNumber()
    toLat: number;

    @ApiProperty()
    @IsNumber()
    toLng: number;

    @ApiPropertyOptional({ enum: ['CITY', 'INTERCITY', 'CARGO', 'DELIVERY'] })
    @IsOptional()
    @IsEnum(['CITY', 'INTERCITY', 'CARGO', 'DELIVERY'])
    mode?: 'CITY' | 'INTERCITY' | 'CARGO' | 'DELIVERY';

    @ApiPropertyOptional({
        enum: [
            'CITY_FIXED',
            'CITY_AUCTION',
            'INTERCITY',
            'DELIVERY_CITY',
            'DELIVERY_INTERCITY',
            'DELIVERY_RF',
        ],
    })
    @IsOptional()
    @IsIn([
        'CITY_FIXED',
        'CITY_AUCTION',
        'INTERCITY',
        'DELIVERY_CITY',
        'DELIVERY_INTERCITY',
        'DELIVERY_RF',
    ])
    requestType?: string;

    @ApiPropertyOptional()
    @IsOptional()
    @IsBoolean()
    doorToDoor?: boolean;

    @ApiPropertyOptional({ description: 'Use wallet bonus balance for payment' })
    @IsOptional()
    @IsBoolean()
    useBonus?: boolean;

    @ApiPropertyOptional({ enum: ['ECONOMY', 'OPTIMAL', 'COMFORT', 'BUSINESS'] })
    @IsOptional()
    @IsIn(['ECONOMY', 'OPTIMAL', 'COMFORT', 'BUSINESS'])
    vehicleClass?: string;
}

export class UpdateOrderStatusDto {
    @ApiProperty({ enum: ['CREATED', 'SEARCHING_DRIVER', 'DRIVER_ASSIGNED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'] })
    @IsEnum(['CREATED', 'SEARCHING_DRIVER', 'DRIVER_ASSIGNED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'])
    status: any;
}

export class RateOrderDto {
    @ApiProperty()
    @IsInt()
    @Min(1)
    @Max(5)
    rating: number;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    @MaxLength(2000)
    reason?: string;
}

export class CreateOrderOfferDto {
    @ApiProperty()
    @IsNumber()
    @Min(1)
    price: number;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    comment?: string;
}
