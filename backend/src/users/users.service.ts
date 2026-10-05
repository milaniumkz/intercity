import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

@Injectable()
export class UsersService {
    constructor(private prisma: PrismaService) { }

    async findById(id: string) {
        return this.prisma.user.findUnique({
            where: { id },
            include: { wallet: true, driverProfile: true },
        });
    }

    async findByPhone(phone: string) {
        return this.prisma.user.findUnique({
            where: { phone },
        });
    }

    async updateCity(userId: string, cityId: string) {
        return this.prisma.user.update({
            where: { id: userId },
            data: { cityId },
        });
    }

    async getRefCode(userId: string) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            select: { refCode: true, refLink: true },
        });
        return user;
    }
}
