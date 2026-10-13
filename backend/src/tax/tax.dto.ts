import { IsArray, IsBoolean, IsIn, IsNumber, IsOptional, IsString, Matches, MaxLength, Min, IsISO8601 } from 'class-validator';

export class DeclareTaxProfileDto {
    @IsIn(['KZ']) countryCode: string;
    @IsIn(['SELF_EMPLOYED', 'IE']) kind: string;
    @IsString() @Matches(/^\d{12}$/) iin: string;
    @IsArray() @IsIn(['49320', '82990'], { each: true }) activities: string[];
    @IsBoolean() consent: boolean;
}
export class VerifyTaxProfileDto {
    @IsOptional() @IsISO8601() birthDate?: string;
    @IsOptional() @IsISO8601() effectiveFrom?: string;
    @IsIn(['VERIFIED', 'REJECTED']) status: string;
    @IsString() @MaxLength(500) reference: string;
    @IsArray() @IsIn(['OPV', 'OPVR', 'SO', 'OSMS'], { each: true }) exemptions: string[];
}
export class MonthlyBasisDto {
    @IsString() @Matches(/^20\d{2}-(0[1-9]|1[0-2])$/) period: string;
    @IsNumber() @Min(0) externalGross: number;
    @IsString() @MaxLength(500) reference: string;
}
export class RemittanceDto {
    @IsString() @Matches(/^20\d{2}-(0[1-9]|1[0-2])$/) period: string;
    @IsString() ownerKey: string;
    @IsIn(['OPV', 'OPVR', 'SO', 'OSMS']) component: string;
    @IsNumber() @Min(0.01) amount: number;
    @IsString() @MaxLength(200) reference: string;
    @IsString() paidAt: string;
    @IsString() @MaxLength(1000) note: string;
}
export class TaxSettingsDto {
    @IsBoolean() enabled: boolean;
    @IsString() @MaxLength(500) operatorReference: string;
    @IsString() @MaxLength(500) referralContractReference: string;
    @IsNumber() @Min(1) minPayout: number;
    @IsString() @Matches(/^20\d{2}$/) year: string;
    @IsNumber() @Min(1) mrp: number;
    @IsNumber() @Min(1) mzp: number;
    @IsString() @MaxLength(500) policyReference: string;
}
