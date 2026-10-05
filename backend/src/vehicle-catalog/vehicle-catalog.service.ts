import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

@Injectable()
export class VehicleCatalogService {
    constructor(private readonly prisma: PrismaService) { }

    async getMakes() {
        return (this.prisma as any).carMake.findMany({
            orderBy: { name: 'asc' },
            select: { id: true, name: true },
        });
    }

    async getModels(make: string) {
        const trimmed = make.trim();
        if (!trimmed) return [];

        const makeRecord = await (this.prisma as any).carMake.findFirst({
            where: { name: { equals: trimmed, mode: 'insensitive' } },
            select: { id: true },
        });
        if (!makeRecord) return [];

        const models = await (this.prisma as any).carModel.findMany({
            where: { makeId: makeRecord.id },
            orderBy: { name: 'asc' },
            select: { name: true },
        });
        return models.map((item: { name: string }) => item.name);
    }
}
