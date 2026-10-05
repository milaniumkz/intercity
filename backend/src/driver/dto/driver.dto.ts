import { IsString, IsNumber, IsOptional, IsBoolean, IsInt, Min } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class CreateDriverProfileDto {
    @ApiProperty()
    @IsString()
    carModel: string;

    @ApiProperty()
    @IsString()
    carNumber: string;

    @ApiPropertyOptional()
    @IsOptional()
    @IsBoolean()
    acceptCityFixed?: boolean;

    @ApiPropertyOptional()
    @IsOptional()
    @IsBoolean()
    acceptCityAuction?: boolean;

    @ApiPropertyOptional()
    @IsOptional()
    @IsBoolean()
    acceptIntercity?: boolean;

    @ApiPropertyOptional()
    @IsOptional()
    @IsBoolean()
    acceptDelivery?: boolean;

    @ApiPropertyOptional()
    @IsOptional()
    @IsBoolean()
    acceptCargo?: boolean;
}

export class UpdateLocationDto {
    @ApiProperty()
    @IsNumber()
    lat: number;

    @ApiProperty()
    @IsNumber()
    lng: number;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    cityId?: string;
}

export class SetOnlineDto {
    @ApiProperty()
    @IsBoolean()
    isOnline: boolean;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    cityId?: string;
}

export class DriverDocsUploadUrlDto {
    @ApiPropertyOptional({ description: 'Document type: selfie, techPassportFront, techPassportBack, driverLicense, passport' })
    @IsOptional()
    @IsString()
    docType?: string;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    fileName?: string;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    mimeType?: string;
}

export class CompleteDriverDocsDto {
    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    selfieUrl?: string;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    techPassportFrontUrl?: string;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    techPassportBackUrl?: string;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    driverLicenseUrl?: string;

    @ApiPropertyOptional()
    @IsOptional()
    @IsString()
    passportUrl?: string;
}

export class DriverIntercityRouteDto {
    @ApiProperty()
    @IsString()
    fromCity: string;

    @ApiProperty()
    @IsString()
    toCity: string;

    @ApiPropertyOptional({ example: 4 })
    @IsOptional()
    @IsInt()
    @Min(1)
    seatsAvailable?: number;
}
