import {
    ConflictException,
    ForbiddenException,
    Injectable,
    NotFoundException,
    UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../prisma.service';
import { RegisterDto, LoginDto, ResetPasswordDto } from './dto/auth.dto';
import { GeoService } from '../geo/geo.service';
import { v4 as uuidv4 } from 'uuid';

@Injectable()
export class AuthService {
    constructor(
        private prisma: PrismaService,
        private jwtService: JwtService,
        private geoService: GeoService,
        private configService: ConfigService,
    ) { }

    async register(dto: RegisterDto) {
        const existingUser = await this.prisma.user.findUnique({
            where: { phone: dto.phone },
        });

        if (existingUser) {
            throw new ConflictException('Phone already registered');
        }

        const hashedPassword = await bcrypt.hash(dto.password, 10);
        const publicId = await this.generateUniquePublicId();
        const refCode = await this.generateUniqueRefCode();
        const refLink = this.buildReferralLink(refCode);
        const normalizedReferralCode = this.normalizeReferralCode(dto.referralCode);

        let cityId = null;
        let referredBy: string | null = null;

        if (dto.lat !== undefined && dto.lng !== undefined) {
            const reverse = await this.geoService.reverseGeocode(dto.lat, dto.lng);
            cityId = reverse.cityId;
        }

        // Handle referral
        if (normalizedReferralCode) {
            const referrer = await this.prisma.user.findUnique({
                where: { refCode: normalizedReferralCode },
            });
            if (referrer) {
                referredBy = referrer.refCode;
                cityId = referrer.cityId;
            }
        }

        const user = await this.prisma.user.create({
            data: {
                phone: dto.phone,
                publicId,
                password: hashedPassword,
                name: dto.name,
                refCode,
                refLink,
                referredBy,
                cityId,
                role: 'PASSENGER',
            },
        });

        // Create wallet
        await this.prisma.wallet.create({
            data: {
                userId: user.id,
            },
        });

        const tokens = await this.generateTokens(user.id, user.phone, user.role);

        return {
            user: {
                publicId: user.publicId,
                phone: user.phone,
                name: user.name,
                role: user.role,
                refCode: user.refCode,
                refLink: this.buildReferralLink(user.refCode),
            },
            ...tokens,
        };
    }

    async login(dto: LoginDto) {
        const user = await this.prisma.user.findUnique({
            where: { phone: dto.phone },
        });

        if (!user) {
            throw new UnauthorizedException('Invalid credentials');
        }

        const isPasswordValid = await bcrypt.compare(dto.password, user.password);
        if (!isPasswordValid) {
            throw new UnauthorizedException('Invalid credentials');
        }

        const tokens = await this.generateTokens(user.id, user.phone, user.role);

        return {
            user: {
                publicId: user.publicId,
                phone: user.phone,
                name: user.name,
                role: user.role,
                refCode: user.refCode,
            },
            ...tokens,
        };
    }

    async refreshToken(refreshToken: string) {
        try {
            const tokenRecord = await this.prisma.refreshToken.findUnique({
                where: { token: refreshToken },
            });
            if (!tokenRecord || tokenRecord.expiresAt < new Date()) {
                throw new UnauthorizedException('Invalid refresh token');
            }

            const payload = this.jwtService.verify(refreshToken, {
                secret: this.getRequiredSecret('JWT_REFRESH_SECRET'),
            });

            const user = await this.prisma.user.findUnique({
                where: { id: payload.sub },
            });

            if (!user) {
                throw new UnauthorizedException('Invalid token');
            }

            const tokens = await this.generateTokens(user.id, user.phone, user.role);

            await this.prisma.refreshToken.delete({
                where: { token: refreshToken },
            });

            return tokens;
        } catch {
            throw new UnauthorizedException('Invalid refresh token');
        }
    }

    async resetPassword(dto: ResetPasswordDto) {
        if (!this.isUnsafePasswordResetAllowed()) {
            throw new ForbiddenException(
                'Password reset is disabled until a verified recovery flow is configured',
            );
        }

        const user = await this.prisma.user.findUnique({
            where: { phone: dto.phone },
            select: { id: true },
        });

        if (!user) {
            throw new UnauthorizedException('User with this phone was not found');
        }

        const hashedPassword = await bcrypt.hash(dto.password, 10);

        await this.prisma.$transaction([
            this.prisma.user.update({
                where: { id: user.id },
                data: { password: hashedPassword },
            }),
            this.prisma.refreshToken.deleteMany({
                where: { userId: user.id },
            }),
        ]);

        return { success: true };
    }

    private isUnsafePasswordResetAllowed(): boolean {
        return process.env.ALLOW_UNVERIFIED_PASSWORD_RESET === 'true';
    }

    async validateUser(userId: string) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            include: { wallet: true, city: true, driverProfile: true },
        });
        if (!user) return null;
        const { password, ...safeUser } = user;
        return { ...safeUser, refLink: this.buildReferralLink(user.refCode) };
    }

    async getReferralSummary(userId: string) {
        const user = await this.prisma.user.findUnique({ where: { id: userId }, select: { refCode: true } });
        if (!user) throw new UnauthorizedException('User not found');
        const invitedCount = await this.prisma.user.count({ where: { referredBy: user.refCode } });
        const amounts = await this.prisma.walletTransaction.groupBy({
            by: ['currency'], where: { wallet: { userId }, type: 'REFERRAL_ORDER_BONUS', direction: 'CREDIT' },
            _sum: { amount: true },
        });
        return { refCode: user.refCode, refLink: this.buildReferralLink(user.refCode), invitedCount,
            earned: { KZT: amounts.find(x => x.currency === 'KZT')?._sum.amount ?? 0,
                      RUB: amounts.find(x => x.currency === 'RUB')?._sum.amount ?? 0 } };
    }

    async savePushToken(userId: string, token: string, platform?: string) {
        await this.prisma.user.update({
            where: { id: userId },
            data: {
                pushToken: token,
                pushPlatform: platform || null,
                pushTokenUpdatedAt: new Date(),
            },
        });
        return { ok: true };
    }

    async updateCurrentUserCity(userId: string, cityId?: string | null) {
        const normalizedCityId = cityId?.trim() || null;
        if (normalizedCityId) {
            const city = await this.prisma.city.findFirst({
                where: { id: normalizedCityId, isActive: true },
                select: { id: true },
            });
            if (!city) {
                throw new NotFoundException('City not found');
            }
        }

        await this.prisma.user.update({
            where: { id: userId },
            data: { cityId: normalizedCityId },
        });

        return this.validateUser(userId);
    }

    private async generateTokens(userId: string, phone: string, role: string) {
        const jwtSecret = this.getRequiredSecret('JWT_SECRET');
        const refreshSecret = this.getRequiredSecret('JWT_REFRESH_SECRET');
        const accessToken = this.jwtService.sign(
            { sub: userId, phone, role },
            { secret: jwtSecret, expiresIn: '1d' }
        );

        const refreshToken = this.jwtService.sign(
            { sub: userId, type: 'refresh', jti: uuidv4() },
            { secret: refreshSecret, expiresIn: '7d' }
        );

        await this.prisma.$transaction([
            this.prisma.refreshToken.deleteMany({ where: { userId } }),
            this.prisma.refreshToken.create({
                data: {
                    userId,
                    token: refreshToken,
                    expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
                },
            }),
        ]);

        return { accessToken, refreshToken };
    }

    private getRequiredSecret(key: 'JWT_SECRET' | 'JWT_REFRESH_SECRET'): string {
        const value = this.configService.get<string>(key) || process.env[key];
        if (!value) {
            throw new UnauthorizedException(`${key} is not configured`);
        }
        return value;
    }

    private generateRefCode(): string {
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
        let code = '';
        for (let i = 0; i < 6; i++) {
            code += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        return code;
    }

    private async generateUniqueRefCode(): Promise<string> {
        for (let attempt = 0; attempt < 8; attempt++) {
            const code = this.generateRefCode();
            const existing = await this.prisma.user.findUnique({
                where: { refCode: code },
                select: { id: true },
            });
            if (!existing) return code;
        }
        return uuidv4().replace(/-/g, '').slice(0, 8).toUpperCase();
    }

    private generatePublicId(): string {
        return String(10000000 + Math.floor(Math.random() * 90000000));
    }

    private async generateUniquePublicId(): Promise<string> {
        for (let attempt = 0; attempt < 12; attempt++) {
            const publicId = this.generatePublicId();
            const existing = await this.prisma.user.findUnique({
                where: { publicId },
                select: { id: true },
            });
            if (!existing) return publicId;
        }
        return `${Date.now()}${Math.floor(Math.random() * 1000)}`;
    }

    private normalizeReferralCode(raw?: string | null): string | null {
        const value = (raw || '').trim();
        if (!value) return null;
        const queryRef = value.match(/[?&](?:ref|referral|referralCode)=([A-Za-z0-9]+)/i)?.[1];
        const pathRef = value.match(/\/ref\/([A-Za-z0-9]+)/i)?.[1];
        const normalized = (queryRef || pathRef || value).replace(/[^A-Za-z0-9]/g, '').toUpperCase();
        return normalized.length > 0 ? normalized : null;
    }

    private buildReferralLink(refCode: string): string {
        let baseUrl = (
            this.configService.get<string>('PUBLIC_WEB_URL') ||
            process.env.PUBLIC_WEB_URL ||
            'https://intercity.89-207-255-27.sslip.io'
        ).replace(/\/+$/, '');
        if (baseUrl === 'https://inter-city-pkzpps.web.app') baseUrl = 'https://intercity.89-207-255-27.sslip.io';
        return `${baseUrl}/#/ref/${refCode}`;
    }
}
