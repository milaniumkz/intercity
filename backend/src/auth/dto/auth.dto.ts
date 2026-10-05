import { IsString, IsNotEmpty, MinLength, Matches, IsOptional, IsNumber } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class RegisterDto {
    @ApiProperty({ example: '+7 999 123 45 67' })
    @Matches(/^\+7\d{10}$/, { message: 'Phone must be in format +7XXXXXXXXXX' })
    phone: string;

    @ApiProperty({ example: 'password123' })
    @IsString()
    @MinLength(6)
    password: string;

    @ApiProperty({ example: 'John' })
    @IsString()
    @IsNotEmpty()
    name: string;

    @ApiPropertyOptional({ example: 'ABC123' })
    @IsOptional()
    @IsString()
    referralCode?: string;

    @ApiPropertyOptional({ example: 43.2220, description: 'Current user latitude for city detection' })
    @IsOptional()
    @IsNumber()
    lat?: number;

    @ApiPropertyOptional({ example: 76.8512, description: 'Current user longitude for city detection' })
    @IsOptional()
    @IsNumber()
    lng?: number;
}

export class LoginDto {
    @ApiProperty({ example: '+7 999 123 45 67' })
    @Matches(/^\+7\d{10}$/, { message: 'Phone must be in format +7XXXXXXXXXX' })
    phone: string;

    @ApiProperty({ example: 'password123' })
    @IsString()
    @IsNotEmpty()
    password: string;
}

export class RefreshTokenDto {
    @ApiProperty()
    @IsString()
    @IsNotEmpty()
    refreshToken: string;
}

export class ResetPasswordDto {
    @ApiProperty({ example: '+7 999 123 45 67' })
    @Matches(/^\+7\d{10}$/, { message: 'Phone must be in format +7XXXXXXXXXX' })
    phone: string;

    @ApiProperty({ example: 'newPassword123' })
    @IsString()
    @MinLength(6)
    password: string;
}

export class SavePushTokenDto {
    @ApiProperty()
    @IsString()
    @IsNotEmpty()
    token: string;

    @ApiPropertyOptional({ example: 'ANDROID' })
    @IsOptional()
    @IsString()
    platform?: string;
}

export class UpdateMyCityDto {
    @ApiPropertyOptional({ example: 'city_uuid', nullable: true })
    @IsOptional()
    @IsString()
    cityId?: string | null;
}
