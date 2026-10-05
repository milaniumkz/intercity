import { BadRequestException } from '@nestjs/common';

const ISO_WITHOUT_TIMEZONE_RE =
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?$/;

export function normalizeClientDateTime(value: unknown, fieldName: string): Date {
    if (value instanceof Date) {
        if (Number.isNaN(value.getTime())) {
            throw new BadRequestException(`Invalid ${fieldName}`);
        }
        return value;
    }

    if (typeof value !== 'string') {
        throw new BadRequestException(`Invalid ${fieldName}`);
    }

    const trimmed = value.trim();
    if (!trimmed) {
        throw new BadRequestException(`Invalid ${fieldName}`);
    }

    // Legacy Flutter clients may send local ISO strings without a timezone suffix.
    // Coerce them to explicit UTC so Prisma accepts the payload instead of raising
    // a validation error and returning a 500.
    const normalized = ISO_WITHOUT_TIMEZONE_RE.test(trimmed)
        ? `${trimmed}Z`
        : trimmed;

    const parsed = new Date(normalized);
    if (Number.isNaN(parsed.getTime())) {
        throw new BadRequestException(`Invalid ${fieldName}`);
    }

    return parsed;
}
