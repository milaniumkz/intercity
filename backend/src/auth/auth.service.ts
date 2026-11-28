import {sendRecoveryCode} from '../attention/whatsapp.channel';
import {randomInt, createHmac, timingSafeEqual} from 'crypto';
import { createHash, randomBytes } from 'crypto';
import { providerConfig, verifiedSubject } from './recovery-provider';
import { IdentityService } from '../identity/identity.service';
import {
    BadRequestException,
    ConflictException,
    ForbiddenException,
    Injectable,
    NotFoundException,
    ServiceUnavailableException,
    UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../prisma.service';
import { RegisterDto, LoginDto, ResetPasswordDto } from './dto/auth.dto';
import { GeoService } from '../geo/geo.service';
import { v4 as uuidv4 } from 'uuid';
import { Prisma, RefreshToken } from '@prisma/client';

type SessionAccount = { id: string; phone: string; role: string; authVersion: number };
const REFRESH_RETRY_GRACE_MS = 30_000;

@Injectable()
export class AuthService {
    constructor(
        private prisma: PrismaService,
        private jwtService: JwtService,
        private geoService: GeoService,
        private configService: ConfigService,
        private identity: IdentityService,
    ) { }

    async referralValidity(raw:string) {
        const code=this.normalizeReferralCode(raw);
        if(!code||code.length>64)return {valid:false};
        const user=await this.prisma.user.findUnique({where:{refCode:code},select:{phone:true}});
        return {valid:!!user&&!user.phone.startsWith('erased:')};
    }
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
            // A stale invitation must never block a new account. Preserve the
            // attribution only while its owner still exists.
            if (referrer && !referrer.phone.startsWith('erased:')) {
                referredBy = referrer.refCode;
                cityId = referrer.cityId;
            }
        }

        const user = await this.prisma.$transaction(async tx => {
            const created = await tx.user.create({
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
            await tx.wallet.create({
                data: {
                    userId: created.id,
                },
            });

            return created;
        });

        const tokens = await this.generateTokens(user.id, user.phone, user.role);

        return {
            user: {
                id: user.id,
                publicId: user.publicId,
                phone: user.phone,
                name: user.name,
                role: user.role,
                mustChangePassword: user.mustChangePassword,
                identityRequired: await this.identity?.needsVerification(user.id,user.role) ?? false,
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

        if (user.blockedAt || user.phone.startsWith('erased:')) throw new UnauthorizedException('Account unavailable');

        const isPasswordValid = await bcrypt.compare(dto.password, user.password);
        if (!isPasswordValid) {
            throw new UnauthorizedException('Invalid credentials');
        }

        const tokens = await this.generateTokens(user.id, user.phone, user.role);

        return {
            user: {
                id: user.id,
                publicId: user.publicId,
                phone: user.phone,
                name: user.name,
                role: user.role,
                mustChangePassword: user.mustChangePassword,
                identityRequired: await this.identity?.needsVerification(user.id,user.role) ?? false,
                refCode: user.refCode,
            },
            ...tokens,
        };
    }

    async refreshToken(refreshToken: string) {
        let payload: any;
        try {
            payload = this.jwtService.verify(refreshToken, {
                secret: this.getRequiredSecret('JWT_REFRESH_SECRET'),
            });
        } catch {
            throw new UnauthorizedException('Invalid refresh token');
        }
        if (payload.type !== 'refresh' || typeof payload.sub !== 'string') {
            throw new UnauthorizedException('Invalid refresh token');
        }
        try {
            return await this.prisma.$transaction(async tx => {
                const now = new Date();
                const record = await tx.refreshToken.findUnique({ where: { token: refreshToken } });
                if (!record || record.userId !== payload.sub || record.expiresAt <= now) {
                    throw new UnauthorizedException('Invalid refresh token');
                }
                const user = await tx.user.findUnique({ where: { id: payload.sub } });
                if (!user || user.blockedAt || user.phone.startsWith('erased:') ||
                    (payload.ver ?? 0) !== user.authVersion) {
                    throw new UnauthorizedException('Invalid refresh token');
                }
                if (record.rotatedAt) return this.reuseRotatedSession(tx, record, user);

                const replacementId = uuidv4();
                const claimed = await tx.refreshToken.updateMany({
                    where: { id: record.id, userId: user.id, rotatedAt: null, expiresAt: { gt: now } },
                    data: { rotatedAt: now, replacementId },
                });
                if (claimed.count !== 1) {
                    const winner = await tx.refreshToken.findUnique({ where: { id: record.id } });
                    if (!winner) throw new UnauthorizedException('Invalid refresh token');
                    return this.reuseRotatedSession(tx, winner, user);
                }

                const tokens = this.sessionTokens(user);
                await tx.refreshToken.create({ data: {
                    id: replacementId, userId: user.id, token: tokens.refreshToken,
                    expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
                } });
                await tx.refreshToken.deleteMany({ where: { userId: user.id, expiresAt: { lte: now } } });
                return tokens;
            });
        } catch (error) {
            if (error instanceof UnauthorizedException) throw error;
            throw new ServiceUnavailableException('Не удалось обновить сессию. Повторите запрос.');
        }
    }

    private async reuseRotatedSession(tx: Prisma.TransactionClient, record: RefreshToken, user: SessionAccount) {
        let current: RefreshToken | null = record;
        // Old native clients can refresh through several API instances at once.
        // Briefly return the same replacement instead of invalidating another request.
        for (let depth = 0; depth < 8; depth++) {
            const now = Date.now();
            if (!current || current.userId !== user.id || current.expiresAt.getTime() <= now) {
                throw new UnauthorizedException('Invalid refresh token');
            }
            if (!current.rotatedAt) return this.sessionTokens(user, current.token);
            if (!current.replacementId || now - current.rotatedAt.getTime() > REFRESH_RETRY_GRACE_MS) {
                throw new UnauthorizedException('Invalid refresh token');
            }
            current = await tx.refreshToken.findUnique({ where: { id: current.replacementId } });
        }
        throw new UnauthorizedException('Invalid refresh token');
    }

    async requestWhatsappCode(input:string) {
        if (typeof input !== 'string' || !/^\+?7\d{10}$/.test(input)) throw new BadRequestException('Введите номер полностью');
        const digits=input.replace(/^\+/,'');
        const nonce=randomBytes(32).toString('hex');
        const code=randomInt(100000,1000000).toString();
        const digest=createHmac('sha256',this.getRequiredSecret('JWT_SECRET')).update(nonce+code).digest('hex');
        const send=await this.prisma.$transaction(async tx=>{
            const user=await tx.user.findFirst({where:{phone:{in:[digits,'+'+digits]},blockedAt:null,role:{not:'ADMIN'}}});
            if(!user)return false;
            await tx.$executeRaw`SELECT id FROM "User" WHERE id=${user.id} FOR UPDATE`;
            if(await tx.recoveryIdentity.count({where:{userId:user.id}}))return false;
            const now=Date.now();
            const recent=await tx.whatsappCode.count({where:{userId:user.id,createdAt:{gt:new Date(now-3600000)}}});
            if(recent>=5 || await tx.whatsappCode.count({where:{userId:user.id,createdAt:{gt:new Date(now-60000)}}}))return false;
            await tx.whatsappCode.updateMany({where:{userId:user.id},data:{used:true}});
            await tx.whatsappCode.create({data:{id:nonce,userId:user.id,digest,authVersion:user.authVersion,expiresAt:new Date(now+300000)}});
            return true;
        });
        if(send) {
            try { await sendRecoveryCode(this.prisma,digits,code,nonce); }
            catch(e) {await this.prisma.whatsappCode.update({where:{id:nonce},data:{used:true}});throw e;}
        }
        return {challenge:nonce};
    }

    async verifyWhatsappCode(id:string,code:string) {
        if(typeof id!=='string'||!/^[a-f0-9]{64}$/.test(id)||typeof code!=='string'||!/^\d{6}$/.test(code))throw new BadRequestException('Проверьте код');
        const grant=await this.prisma.$transaction(async tx=>{
            await tx.$executeRaw`SELECT id FROM "WhatsappCode" WHERE id=${id} FOR UPDATE`;
            const row=await tx.whatsappCode.findUnique({where:{id}});
            if(!row||row.used||row.attempts>=5||row.expiresAt<=new Date())return null;
            const digest=createHmac('sha256',this.getRequiredSecret('JWT_SECRET')).update(id+code).digest();
            if(!timingSafeEqual(digest,Buffer.from(row.digest,'hex'))){
                await tx.whatsappCode.update({where:{id},data:{attempts:{increment:1}}});
                return null;
            }
            if(await tx.recoveryIdentity.count({where:{userId:row.userId}}))return null;
            await tx.whatsappCode.update({where:{id},data:{used:true}});
            const token=randomBytes(32).toString('hex');
            await tx.recoveryProof.create({data:{id:createHash('sha256').update(token).digest('hex'),userId:row.userId,authVersion:row.authVersion,provider:'WHATSAPP',purpose:'PASSWORD',expiresAt:new Date(Date.now()+300000)}});
            return token;
        });
        if(!grant)throw new UnauthorizedException('Код неверен или истёк');
        return {grant};
    }

    async requestRecoveryHelp(input: string) {
        if (typeof input !== 'string' || !/^\+?7\d{10}$/.test(input)) {
            throw new BadRequestException('Введите номер телефона полностью');
        }
        const digits = input.replace(/^\+/, '');
        const accepted = { message: 'Если аккаунт найден, обращение передано администратору.' };
        await this.prisma.$transaction(async tx => {
            const user = await tx.user.findFirst({
                where: { phone: { in: [digits, '+' + digits] }, blockedAt: null, role: { not: 'ADMIN' } },
                select: { id: true },
            });
            if (!user) return;
            await tx.$executeRaw`SELECT id FROM "User" WHERE id = ${user.id} FOR UPDATE`;
            const type = 'ACCOUNT_RECOVERY';
            const recent = await tx.complaint.findFirst({
                where: { userId: user.id, type, OR: [{status: 'NEW'}, {createdAt: {gte: new Date(Date.now() - 86400000)}}] },
                select: { id: true },
            });
            if (!recent) await tx.complaint.create({data: {
                userId: user.id, type, text: 'Запрошено восстановление доступа. Проверьте владельца перед выдачей временного пароля.',
            }});
        });
        return accepted;
    }

    async recoveryLinks(userId: string) {
        const rows = await this.prisma.recoveryIdentity.findMany({where:{userId},select:{provider:true}});
        return { providers: rows.map(row => row.provider) };
    }

    async startProvider(provider: string, userId?: string) {
        providerConfig(provider);
        const nonce = randomBytes(32).toString('hex');
        const user = userId ? await this.prisma.user.findUniqueOrThrow({where:{id:userId}}) : null;
        await this.prisma.recoveryProof.deleteMany({where:{expiresAt:{lt:new Date()}}});
        await this.prisma.recoveryProof.create({data:{id:nonce,provider,userId,purpose:userId?'LINK':'RECOVER',authVersion:user?.authVersion,expiresAt:new Date(Date.now()+300000)}});
        return { nonce };
    }

    async finishProvider(provider: string, nonce: string, token: string, userId?: string, password?: string) {
        if (typeof nonce !== 'string' || !/^[a-f0-9]{64}$/.test(nonce)) throw new BadRequestException('Некорректный запрос');
        const subject = await verifiedSubject(provider, token, nonce);
        return this.prisma.$transaction(async tx => {
            const proof = await tx.recoveryProof.findUnique({where:{id:nonce}});
            if (!proof || proof.purpose !== (userId?'LINK':'RECOVER') || proof.userId !== (userId || null) || proof.provider !== provider ||
                !(await tx.recoveryProof.deleteMany({where:{id:nonce,expiresAt:{gt:new Date()}}})).count)
                throw new UnauthorizedException('Начните подтверждение заново');
            if (userId) {
                const user = await tx.user.findUniqueOrThrow({where:{id:userId}});
                if (user.blockedAt || user.authVersion !== proof.authVersion || typeof password !== 'string' || !await bcrypt.compare(password,user.password))
                    throw new UnauthorizedException('Подтвердите текущий пароль');
                await tx.recoveryIdentity.create({data:{userId,provider,subject}});
                return { linked:true };
            }
            const identity = await tx.recoveryIdentity.findUnique({where:{provider_subject:{provider,subject}}});
            const user = identity && await tx.user.findUnique({where:{id:identity.userId}});
            if (!user || user.blockedAt || user.role === 'ADMIN' || user.phone.startsWith('erased:')) throw new UnauthorizedException('Этот способ восстановления недоступен');
            const grant = randomBytes(32).toString('hex');
            await tx.recoveryProof.create({data:{id:createHash('sha256').update(grant).digest('hex'),provider,purpose:'PASSWORD',userId:user.id,authVersion:user.authVersion,expiresAt:new Date(Date.now()+300000)}});
            return { grant };
        });
    }

    async completeRecovery(grant: string, password: string) {
        if (typeof grant!=='string' || !/^[0-9a-f]{64}$/.test(grant) || typeof password!=='string' || password.length<12 || Buffer.byteLength(password)>72)
            throw new BadRequestException('Проверьте ссылку восстановления и новый пароль');
        const id=createHash('sha256').update(grant).digest('hex');
        return this.prisma.$transaction(async tx=>{
            const proof=await tx.recoveryProof.findUnique({where:{id}});
            if (!proof?.userId || proof.authVersion===null || proof.purpose!=='PASSWORD' || !(await tx.recoveryProof.deleteMany({where:{id,expiresAt:{gt:new Date()}}})).count)
                throw new UnauthorizedException('Начните восстановление заново');
            const passwordHash=await bcrypt.hash(password,12);
            const change=await tx.user.updateMany({where:{id:proof.userId,authVersion:proof.authVersion,blockedAt:null,role:{not:'ADMIN'},NOT:{phone:{startsWith:'erased:'}}},data:{password:passwordHash,authVersion:{increment:1},mustChangePassword:false}});
            if (!change.count) throw new UnauthorizedException('Начните восстановление заново');
            const user=await tx.user.findUniqueOrThrow({where:{id:proof.userId}});
            await tx.refreshToken.deleteMany({where:{userId:user.id}});
            const tokens=this.sessionTokens(user);
            await tx.refreshToken.create({data:{userId:user.id,token:tokens.refreshToken,expiresAt:new Date(Date.now()+604800000)}});
            return {...tokens,user:{id:user.id,phone:user.phone,role:user.role}};
        });
    }

    async resetPassword(dto: ResetPasswordDto) {
        throw new ForbiddenException('Для восстановления пароля пройдите видеопроверку личности');
    }

    async changePassword(userId: string, current: string, next: string) {
        const user = await this.prisma.user.findUnique({where:{id:userId}});
        if (!user || !await bcrypt.compare(current, user.password)) throw new UnauthorizedException('Неверный текущий пароль');
        if (next === current) throw new ForbiddenException('Новый пароль должен отличаться');
        await this.prisma.$transaction([
            this.prisma.user.update({where:{id:userId},data:{password:await bcrypt.hash(next,12),mustChangePassword:false,authVersion:{increment:1}}}),
            this.prisma.refreshToken.deleteMany({where:{userId}}),
        ]);
        return this.generateTokens(user.id,user.phone,user.role);
    }

    async validateUser(userId: string) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            include: { wallet: true, city: true, driverProfile: true },
        });
        if (!user || user.blockedAt || user.phone.startsWith('erased:')) return null;
        const { password, ...safeUser } = user;
        return { ...safeUser, driverDocumentsRequired: !!user.driverProfile && (await this.identity?.driverDocumentsRequired(user.id) ?? false), identityRequired: await this.identity?.needsVerification(user.id,user.role) ?? false, refLink: this.buildReferralLink(user.refCode) };
    }

    async getReferralSummary(userId: string) {
        const user = await this.prisma.user.findUnique({ where: { id: userId }, select: { refCode: true } });
        if (!user) throw new UnauthorizedException('User not found');
        const invitedCount = await this.prisma.user.count({ where: { referredBy: user.refCode } });
        const amounts = await this.prisma.walletTransaction.groupBy({
            by: ['currency'], where: { wallet: { userId }, type: { in: ['REFERRAL_ORDER_BONUS','REFERRAL_INCOME'] }, direction: 'CREDIT' },
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

    private sessionTokens(account: SessionAccount, existingRefreshToken?: string) {
        const accessToken = this.jwtService.sign(
            { sub: account.id, phone: account.phone, role: account.role, ver: account.authVersion },
            { secret: this.getRequiredSecret('JWT_SECRET'), expiresIn: '1d' }
        );
        const refreshToken = existingRefreshToken ?? this.jwtService.sign(
            { sub: account.id, type: 'refresh', jti: uuidv4(), ver: account.authVersion },
            { secret: this.getRequiredSecret('JWT_REFRESH_SECRET'), expiresIn: '7d' }
        );
        return { accessToken, refreshToken };
    }

    private async generateTokens(userId: string, phone: string, role: string) {
        const account = await this.prisma.user.findUnique({ where: { id: userId }, select: { authVersion: true } });
        if (!account) throw new UnauthorizedException('Invalid account');
        const tokens = this.sessionTokens({ id: userId, phone, role, authVersion: account.authVersion });
        await this.prisma.$transaction([
            this.prisma.refreshToken.deleteMany({ where: { userId, expiresAt: { lte: new Date() } } }),
            this.prisma.refreshToken.create({ data: {
                userId, token: tokens.refreshToken,
                expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
            } }),
        ]);
        return tokens;
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
