import {OrdersService} from '../orders/orders.service';
import {IntercityService} from '../intercity/intercity.service';
import {AttentionService} from '../attention/attention.service';
import {issueExplanation} from './issue-explanation';
import {recordDates} from '../admin/customer-records';
import {dataCatalog,dataList,dataRecord} from './data-management';
import {userActivity} from './activity-feed';
import {IdentityService} from '../identity/identity.service';
import {customerTrips} from '../admin/customer-records';
import {
    Body,
    CanActivate,
    Controller,
    ExecutionContext,
    Get,
    Injectable,
    Param,
    Post,
    Query,
    Req,
    Res,
    UseGuards,
    BadRequestException,
    ForbiddenException,
    UnauthorizedException,
} from '@nestjs/common';
import { TechnicalService } from './technical.service';
import {
    digest,
    pageArgs,
    PERMISSIONS,
    safeId,
    safeMessage,
    RULE_DEFAULTS,
} from './technical-utils';
import { join, resolve } from 'path';
import { promises as fs } from 'fs';
import sharp from 'sharp';
import * as bcrypt from 'bcrypt';
import { isIP } from 'net';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

function checkOrigin(req: any) {
    if (['GET', 'HEAD', 'OPTIONS'].includes(req.method)) return;
    if (req.headers['x-tech-request'] !== '1')
        throw new ForbiddenException('Требуется запрос технической панели');
    if (
        req.headers.origin &&
        new URL(req.headers.origin).host !== req.headers.host
    )
        throw new ForbiddenException('Недопустимый источник запроса');
    if (req.headers['sec-fetch-site'] === 'cross-site')
        throw new ForbiddenException('Недопустимый источник запроса');
}
@Injectable()
export class TechnicalGuard implements CanActivate {
    constructor(private tech: TechnicalService) {}
    async canActivate(ctx: ExecutionContext) {
        const req = ctx.switchToHttp().getRequest();
        checkOrigin(req);
        const cookie = String(req.headers.cookie ?? '')
            .split(';')
            .map((x) => x.trim())
            .find((x) => x.startsWith('tech_session='));
        const account = await this.tech.session(
            cookie?.slice('tech_session='.length) ?? '',
        );
        if (!account)
            throw new UnauthorizedException('Войдите в техническую панель');
        req.tech = account;
        await this.tech.audit(
            account.id,
            'http.access',
            req.params?.id ?? null,
            {
                method: req.method,
                route: String(req.route?.path ?? '').slice(0, 200),
            },
        );
        return true;
    }
}
function allow(req: any, permission: string) {
    if (!req.tech.permissions.includes(permission))
        throw new ForbiddenException(
            'Нет технического разрешения: ' + permission,
        );
}
function paging(q: any) {
    try {
        return pageArgs(q);
    } catch {
        throw new BadRequestException('Некорректная пагинация');
    }
}
function whereEvents(q: any) {
    const where: any = {};
    for (const key of [
        'userId',
        'sessionId',
        'requestId',
        'objectId',
        'result',
        'issueId',
        'actorId',
    ])
        if (q[key]) {
            if (!safeId(q[key]))
                throw new BadRequestException('Некорректный фильтр');
            where[key] = q[key];
        }
    if (q.from || q.to) {
        where.at = {};
        for (const [key, v] of [
            ['gte', q.from],
            ['lte', q.to],
        ])
            if (v) {
                const d = new Date(v);
                if (!Number.isFinite(d.getTime()))
                    throw new BadRequestException('Некорректная дата');
                where.at[key] = d;
            }
    }
    if(q.platform)where.AND=[{client:{path:['platform'],equals:String(q.platform)}}];
    if(q.stage)where.stage=String(q.stage);
    if(q.statusMin)where.status={gte:Math.max(100,Math.min(599,Number(q.statusMin)||500))};
    if (q.version)
        where.client = {
            path: ['version'],
            equals: String(q.version).slice(0, 120),
        };
    if (q.search)
        where.action = {
            contains: String(q.search).slice(0, 100),
            mode: 'insensitive',
        };
    return where;
}
@Controller('technical')
export class TechnicalPublicController {
    constructor(private tech: TechnicalService) {}
    @Get('panel') panel(@Res() res: any) {
        this.headers(res);
        res.sendFile(join(process.cwd(), 'technical-web', 'index.html'));
    }
    @Get('panel/:asset') asset(@Param('asset') asset: string, @Res() res: any) {
        if (!['app.js', 'data-management.js', 'style.css', 'sw.js'].includes(asset))
            throw new BadRequestException();
        this.headers(res);
        if (asset === 'sw.js')
            res.setHeader('Service-Worker-Allowed', '/api/technical/');
        res.sendFile(join(process.cwd(), 'technical-web', asset));
    }
    private headers(res: any) {
        res.setHeader('Cache-Control', 'no-store');
        res.setHeader('X-Content-Type-Options', 'nosniff');
        res.setHeader('Referrer-Policy', 'no-referrer');
        res.setHeader(
            'Content-Security-Policy',
            "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' blob:; media-src 'self' blob:; connect-src 'self'; worker-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
        );
    }
    @Post('login') async login(
        @Req() req: any,
        @Body() b: any,
        @Res() res: any,
    ) {
        checkOrigin(req);
        if (
            typeof b.login !== 'string' ||
            typeof b.password !== 'string' ||
            b.login.length > 80 ||
            b.password.length > 72
        )
            throw new BadRequestException('Некорректные данные');
        const result = await this.tech.login(
            b.login,
            b.password,
            req.ip ?? req.socket.remoteAddress ?? 'unknown',
        );
        res.setHeader(
            'Set-Cookie',
            `tech_session=${result.token}; HttpOnly; SameSite=Strict; Path=/api/technical; Max-Age=28800${process.env.NODE_ENV === 'production' ? '; Secure' : ''}`,
        );
        res.setHeader('Cache-Control', 'no-store');
        return res.json(result.account);
    }
}
@Controller('technical')
@UseGuards(TechnicalGuard)
export class TechnicalController {
    constructor(private tech: TechnicalService, private identity:IdentityService,private readonly attention:AttentionService,private readonly orders:OrdersService,private readonly intercity:IntercityService) {}
    @Get('identity-attempts') async identityHistory(@Req()req:any,@Query()q:any){allow(req,'personal');return this.identity.history(q);}
    @Get('identity-attempts/:id/video') async identityVideo(@Req()req:any,@Param('id')id:string,@Res()res:any){
        allow(req,'personal');allow(req,'originals');
        const bytes=await this.identity.reviewMedia(safeId(id),'video');
        await this.tech.audit(req.tech.id,'identity.video.read',id,{});
        res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');res.type(bytes[0]===0x1a?'video/webm':'video/mp4');res.send(bytes);
    }
    @Get('users/:id/trips') async userTrips(@Req()req:any,@Param('id')id:string,@Query()q:any){allow(req,'personal');return customerTrips(this.tech.prisma,{...q,userId:safeId(id)});}
    @Get('cities') async cities(@Req()req:any,@Query('search')search:string){allow(req,'personal');return this.tech.prisma.city.findMany({where:{isActive:true,name:{contains:String(search||'').slice(0,100),mode:'insensitive'}},take:30,select:{id:true,name:true,countryCode:true,region:true},orderBy:{name:'asc'}});}
    @Get('data') catalog(@Req()req:any){allow(req,'personal');return dataCatalog();}
    @Get('data-lookups/:model') async lookups(@Req()req:any,@Param('model')model:string,@Query('search')search:string){
        allow(req,'personal');const value=String(search||'').slice(0,100);
        if(model==='User'){const rows=await this.tech.prisma.user.findMany({where:{NOT:{phone:{startsWith:'erased:'}},OR:[{name:{contains:value,mode:'insensitive'}},{phone:{contains:value}}]},take:40,select:{id:true,name:true,phone:true}});return rows.map(r=>({id:r.id,label:r.name+' · '+r.phone}));}
        if(model==='DriverProfile'){const rows=await this.tech.prisma.driverProfile.findMany({where:{OR:[{carNumber:{contains:value,mode:'insensitive'}},{carModel:{contains:value,mode:'insensitive'}},{user:{is:{OR:[{name:{contains:value,mode:'insensitive'}},{phone:{contains:value}}]}}}]},take:40,select:{id:true,carNumber:true,user:{select:{name:true,phone:true}}}});return rows.map(r=>({id:r.id,label:r.user.name+' · '+r.user.phone+' · '+(r.carNumber||'')}));}
        if(model==='City'){const rows=await this.tech.prisma.city.findMany({where:{name:{contains:value,mode:'insensitive'}},take:40,select:{id:true,name:true,countryCode:true}});return rows.map(r=>({id:r.id,label:r.name+' · '+r.countryCode}));}
        if(model==='Wallet'){const rows=await this.tech.prisma.wallet.findMany({where:{user:{is:{OR:[{name:{contains:value,mode:'insensitive'}},{phone:{contains:value}}]}}},take:40,select:{id:true,user:{select:{name:true,phone:true}}}});return rows.map(r=>({id:r.id,label:r.user.name+' · '+r.user.phone}));}
        throw new BadRequestException('Список выбора недоступен');
    }
    @Get('data/:model') records(@Req()req:any,@Param('model')model:string,@Query()q:any){allow(req,'personal');return dataList(this.tech.prisma,model,q);}
    @Get('data/:model/:id') record(@Req()req:any,@Param('model')model:string,@Param('id')id:string){allow(req,'personal');return dataRecord(this.tech.prisma,model,id);}
    @Post('data/:model/:id/cancel') async cancelRecord(@Req()req:any,@Param('model')model:string,@Param('id')id:string,@Body()body:any){allow(req,'users');allow(req,'danger');await this.tech.confirmManagement(req.tech,body);if(!['Order','IntercityRequest'].includes(model))throw new BadRequestException('Отмена доступна только для заказов');const record=model==='Order'?await this.tech.prisma.order.findUnique({where:{id},select:{passengerId:true}}):await this.tech.prisma.intercityRequest.findUnique({where:{id},select:{passengerId:true}});if(!record)throw new BadRequestException('Заказ не найден');await this.tech.audit(req.tech.id,'order.cancel.requested',id,{model,reason:body.reason});const result=model==='Order'?await this.orders.cancelOrder(id,record.passengerId):await this.intercity.cancelRequest(record.passengerId,id);await this.tech.audit(req.tech.id,'order.cancel.completed',id,{model,reason:body.reason});return{ok:true,status:result.status};}
    @Post('data/:model/:id') recordEdit(@Req()req:any,@Param('model')model:string,@Param('id')id:string,@Body()body:any){allow(req,'personal');allow(req,'users');allow(req,'danger');return this.tech.changeData(req.tech,model,id,body);}
    @Get('users/:id/wallet') async wallet(@Req()req:any,@Param('id')id:string){allow(req,'personal');allow(req,'users');return {wallet:await this.tech.prisma.wallet.findUnique({where:{userId:id},select:{id:true,money:true,bonus:true,moneyRub:true,bonusRub:true,lockedBonus:true,lockedBonusRub:true,referralMoney:true,updatedAt:true}}),transactions:await this.tech.prisma.walletTransaction.findMany({where:{wallet:{userId:id}},orderBy:{createdAt:'desc'},take:30,select:{id:true,type:true,direction:true,amount:true,currency:true,balanceSource:true,note:true,createdAt:true}})};}
    @Post('users/:id/wallet-adjustment') walletAdjustment(@Req()req:any,@Param('id')id:string,@Body()body:any){allow(req,'personal');allow(req,'users');allow(req,'danger');return this.tech.correctWallet(req.tech,id,body);}
    @Get('me') me(@Req() req: any) {
        return {
            id: req.tech.id,
            login: req.tech.login,
            permissions: req.tech.permissions,
        };
    }
    @Post('me/password') async ownPassword(@Req() req: any, @Body() b: any) {
        await this.tech.reauth(req.tech, b.currentPassword);
        if (
            typeof b.newPassword !== 'string' ||
            b.newPassword.length < 14 ||
            Buffer.byteLength(b.newPassword) > 72 ||
            b.newPassword === b.currentPassword
        )
            throw new BadRequestException(
                'Новый пароль: 14–72 байта, должен отличаться',
            );
        await this.tech.audit(
            req.tech.id,
            'account.password.change',
            req.tech.id,
        );
        await this.tech.prisma.$transaction([
            this.tech.prisma.techAccount.update({
                where: { id: req.tech.id },
                data: { passwordHash: await bcrypt.hash(b.newPassword, 12) },
            }),
            this.tech.prisma.techSession.updateMany({
                where: { accountId: req.tech.id },
                data: { revokedAt: new Date() },
            }),
        ]);
        return { ok: true };
    }
    @Post('logout') async logout(@Req() req: any, @Res() res: any) {
        await this.tech.prisma.techSession.update({
            where: { id: req.tech.sessionId },
            data: { revokedAt: new Date() },
        });
        res.setHeader(
            'Set-Cookie',
            'tech_session=; HttpOnly; SameSite=Strict; Path=/api/technical; Max-Age=0',
        );
        res.json({ ok: true });
    }
    @Get('attention') attentionList(@Req()req:any,@Query()q:any){allow(req,'events');return this.attention.list('TECHNICAL',req.tech.id,q);}
    @Post('attention/:id/read') attentionRead(@Req()req:any,@Param('id')id:string){allow(req,'events');return this.attention.acknowledge('TECHNICAL',req.tech.id,id);}
    @Get('filter-options') async filterOptions(@Req()req:any){allow(req,'events');const [versions,documents]=await Promise.all([this.tech.prisma.techEvent.findMany({distinct:['client'],take:200,select:{client:true},orderBy:{at:'desc'}}),this.tech.prisma.techFile.findMany({distinct:['docType'],select:{docType:true},take:50})]);return{versions:[...new Set(versions.map((x:any)=>x.client?.version).filter(Boolean))],docTypes:documents.map(x=>x.docType)};}
    @Get('activity') async activity(@Req()req:any,@Query()q:any){allow(req,'events');return userActivity(this.tech.prisma,q,req.tech.permissions.includes('personal'));}
    @Get('overview') overview(@Req() req: any) {
        allow(req, 'events');
        return this.tech.overview();
    }
    @Get('events') async events(@Req() req: any, @Query() q: any) {
        allow(req, 'events');
        const where = whereEvents(q),
            args = paging(q);
        const [items, total] = await Promise.all([
            this.tech.prisma.techEvent.findMany({
                where,
                ...args,
                orderBy: [
                    { at: q.order === 'asc' ? 'asc' : 'desc' },
                    { id: 'asc' },
                ],
            }),
            this.tech.prisma.techEvent.count({ where }),
        ]);
        return {
            items: items.map((e) => this.visibleEvent(req, e)),
            total,
            scope: {
                userId: q.userId ?? null,
                sessionId: q.sessionId ?? null,
                requestId: q.requestId ?? null,
                objectId: q.objectId ?? null,
            },
            gaps: 'История начинается с внедрения сбора. Действия без обращения к серверу могли не фиксироваться. Отсутствие событий не доказывает прекращение работы.',
        };
    }
    private visibleEvent(req: any, e: any) {
        if (req.tech.permissions.includes('personal')) return e;
        return {
            ...e,
            details: e.details ? { ...e.details, identity: null } : null,
            ip: null,
            sessionId: null,
            client: e.client
                ? { platform: e.client.platform, version: e.client.version }
                : null,
        };
    }
    @Get('events/:id') async event(@Req() req: any, @Param('id') id: string) {
        allow(req, 'events');
        const e = await this.tech.prisma.techEvent.findUnique({
            where: { id },
        });
        if (!e) throw new BadRequestException('Событие не найдено');
        const files = await this.tech.prisma.techFile.findMany({
            where: { requestId: e.requestId },
            select: {
                id: true,
                docType: true,
                verdict: true,
                reason: true,
                createdAt: true,
                userId: true,
            },
        });
        return {
            event: this.visibleEvent(req, e),
            actionFiles: files,
            otherObjectFiles: e.objectId
                ? await this.tech.prisma.techFile.findMany({
                      where: {
                          objectId: e.objectId,
                          requestId: { not: e.requestId },
                      },
                      take: 50,
                      orderBy: { createdAt: 'desc' },
                      select: {
                          id: true,
                          docType: true,
                          createdAt: true,
                          userId: true,
                      },
                  })
                : [],
        };
    }
    @Get('issues') async issues(@Req() req: any, @Query() q: any) {
        allow(req, 'events');
        const where: any = {};
        if (q.kind) where.kind = String(q.kind);
        if(q.severity)where.severity=String(q.severity);
        const dates=recordDates(q);if(dates)where.lastAt=dates;
        if(q.userId||q.platform){const matching=await this.tech.prisma.techEvent.findMany({where:{...(q.userId?{userId:String(q.userId)}:{}),...(q.platform?{client:{path:['platform'],equals:String(q.platform)}}:{})},distinct:['issueId'],select:{issueId:true}});where.id={in:matching.map(e=>e.issueId).filter(Boolean)};}
        if (q.status) where.status = String(q.status);
        if (q.search)
            where.title = {
                contains: String(q.search).slice(0, 100),
                mode: 'insensitive',
            };
        return {
            items: await this.tech.prisma.techIssue.findMany({
                where,
                ...paging(q),
                orderBy: { lastAt: 'desc' },
            }),
            total: await this.tech.prisma.techIssue.count({ where }),
        };
    }
    @Get('issues/:id') async issue(@Req() req: any, @Param('id') id: string) {
        allow(req, 'events');
        const issue = await this.tech.prisma.techIssue.findUnique({
            where: { id },
        });
        if (!issue) throw new BadRequestException('Проблема не найдена');
        const users = await this.tech.prisma.techEvent.groupBy({
            by: ['userId'],
            where: { issueId: id, userId: { not: null } },
        });
        const events = await this.tech.prisma.techEvent.findMany({
            where: { issueId: id },
            take: 30,
            orderBy: { at: 'desc' },
        });
        return {
            issue,
            explanation:issueExplanation(issue,events),
            affectedUsers: users.map((x) => x.userId),
            events: events.map((e) => this.visibleEvent(req, e)),
            comments: await this.tech.prisma.techComment.findMany({
                where: { issueId: id },
                take: 100,
                orderBy: { createdAt: 'asc' },
            }),
            recommendation:
                'Проверьте ответ сервиса, повторяемость, версию приложения и последовательность событий. Совпадение правила само по себе не доказывает нарушение или причину.',
        };
    }
    @Post('issues/:id') async updateIssue(
        @Req() req: any,
        @Param('id') id: string,
        @Body() b: any,
    ) {
        allow(req, 'events');
        const data: any = {};
        if (b.status) {
            if (
                ![
                    'NEW',
                    'IN_REVIEW',
                    'CONFIRMED',
                    'NOT_CONFIRMED',
                    'RESOLVED',
                ].includes(b.status)
            )
                throw new BadRequestException();
            if (b.status === 'RESOLVED' && (!b.verification || !b.fixedVersion))
                throw new BadRequestException(
                    'Нужны результат проверки и исправляющая версия',
                );
            data.status = b.status;
        }
        for (const k of [
            'confirmedCause',
            'hypothesis',
            'verification',
            'fixedVersion',
        ])
            if (typeof b[k] === 'string') data[k] = safeMessage(b[k]);
        if (b.assignedTo !== undefined) {
            if (
                b.assignedTo &&
                !(await this.tech.prisma.techAccount.findFirst({
                    where: { id: b.assignedTo, disabled: false },
                }))
            )
                throw new BadRequestException('Ответственный не найден');
            data.assignedTo = b.assignedTo || null;
        }
        if (b.mutedMinutes !== undefined) {
            const minutes = Number(b.mutedMinutes);
            if (!Number.isInteger(minutes) || minutes < 0 || minutes > 1440)
                throw new BadRequestException();
            data.mutedUntil = new Date(Date.now() + minutes * 60000);
        }
        await this.tech.audit(req.tech.id, 'issue.update', id, data);
        const issue = await this.tech.prisma.techIssue.update({
            where: { id },
            data,
        });
        if (b.comment)
            await this.tech.prisma.techComment.create({
                data: {
                    issueId: id,
                    actorId: req.tech.id,
                    text: safeMessage(b.comment),
                },
            });
        return issue;
    }
    @Get('users') async users(@Req() req: any, @Query() q: any) {
        allow(req, 'personal');
        const where: any = {NOT:{phone:{startsWith:'erased:'}}};
        const dates=recordDates(q);if(dates)where.createdAt=dates;
        if(q.role){if(!['PASSENGER','DRIVER','ADMIN'].includes(q.role))throw new BadRequestException('Выберите роль');where.role=q.role;}
        if(q.blocked)where.blockedAt=q.blocked==='true'?{not:null}:null;
        if(q.platform)where.pushPlatform=String(q.platform);
        if (q.search)
            where.OR = [
                {
                    name: {
                        contains: String(q.search).slice(0, 100),
                        mode: 'insensitive',
                    },
                },
                { phone: { contains: String(q.search).slice(0, 100) } },
                { id: String(q.search) },
            ];
        return {
            items: await this.tech.prisma.user.findMany({
                where,
                ...paging(q),
                orderBy: { createdAt: 'desc' },
                select: {
                    id: true,
                    publicId: true,
                    name: true,
                    phone: true,
                    role: true,
                    blockedAt: true,
                    mustChangePassword: true,
                    createdAt: true,
                    city: { select: { name: true } },
                },
            }),
            total: await this.tech.prisma.user.count({ where }),
            organizations:
                'Модель организаций пользователей в проекте отсутствует; города не считаются организациями.',
        };
    }
    @Get('users/:id') async user(@Req() req: any, @Param('id') id: string) {
        allow(req, 'personal');
        const user = await this.tech.prisma.user.findUnique({
            where: { id },
            select: {
                id: true,
                publicId: true,
                name: true,
                phone: true,
                role: true,
                blockedAt: true,
                mustChangePassword: true,
                cityId:true,
                createdAt: true,
                city: { select: { name: true } },
                driverProfile: {
                    select: {
                        id: true,
                        status: true,
                        carModel:true,carNumber:true,acceptCityFixed:true,acceptCityAuction:true,acceptIntercity:true,acceptDelivery:true,acceptCargo:true,
                        selfieUrl: true,
                        passportUrl: true,
                        driverLicenseUrl: true,
                        techPassportFrontUrl: true,
                        techPassportBackUrl: true,
                    },
                },
            },
        });
        if (!user) throw new BadRequestException('Пользователь не найден');
        return {
            user,
            events: await this.tech.prisma.techEvent.findMany({
                where: { userId: id },
                take: 30,
                orderBy: { at: 'desc' },
            }),
            sessions: await this.tech.prisma.refreshToken.count({
                where: { userId: id, expiresAt: { gt: new Date() } },
            }),
            sessionLimitation:
                'Число записей обновления токенов, не точное число открытых устройств',
        };
    }
    @Get('users/:id/documents/:type') async legacyOriginal(
        @Req() req: any,
        @Param('id') id: string,
        @Param('type') type: string,
        @Res() res: any,
    ) {
        allow(req, 'originals');
        if (
            ![
                'selfieUrl',
                'passportUrl',
                'driverLicenseUrl',
                'techPassportFrontUrl',
                'techPassportBackUrl',
            ].includes(type)
        )
            throw new BadRequestException('Тип документа не найден');
        const profile = await this.tech.prisma.driverProfile.findUnique({
            where: { userId: id },
        });
        const url = profile?.[type];
        if (!url || !url.startsWith('/uploads/' + profile.id + '/'))
            throw new BadRequestException(
                'Старый локальный оригинал не найден',
            );
        const root = resolve(
                process.env.UPLOAD_DIR || join(process.cwd(), 'uploads'),
            ),
            target = resolve(root, url.slice('/uploads/'.length));
        if (!target.startsWith(root + '/')) throw new ForbiddenException();
        await this.tech.audit(
            req.tech.id,
            'legacy.file.original.view',
            profile.id,
            {
                type,
                provenance: 'Автор и время старой загрузки не установлены',
            },
        );
        let buffer: Buffer;
        try {
            const stat = await fs.stat(target);
            if (stat.size > 10485760) throw new Error();
            buffer = await fs.readFile(target);
        } catch {
            throw new BadRequestException(
                'Оригинал отсутствует или превышает лимит безопасного просмотра',
            );
        }
        let format: string;
        try {
            format = (
                await sharp(buffer, { limitInputPixels: 40000000 }).metadata()
            ).format;
        } catch {
            throw new BadRequestException(
                'Старый файл не является поддерживаемым изображением',
            );
        }
        if (!['jpeg', 'png', 'webp'].includes(format))
            throw new BadRequestException('Неподдерживаемый формат');
        res.setHeader('Content-Type', 'image/' + format);
        res.setHeader('Cache-Control', 'no-store');
        res.setHeader('X-Content-Type-Options', 'nosniff');
        res.send(buffer);
    }
    @Post('users/:id/:action') userOperation(
        @Req() req: any,
        @Param('id') id: string,
        @Param('action') action: string,
        @Body() b: any,
    ) {
        allow(req, 'users');
        allow(req, 'danger');
        return this.tech.userOperation(req.tech, id, action, b);
    }
    @Get('files') async files(@Req() req: any, @Query() q: any) {
        allow(req, 'events');
        const where: any = {};
        const dates=recordDates(q);if(dates)where.createdAt=dates;
        for (const k of ['userId', 'objectId', 'requestId', 'verdict','docType'])
            if (q[k]) where[k] = String(q[k]).slice(0, 120);
        return {
            items: (
                await this.tech.prisma.techFile.findMany({
                    where,
                    ...paging(q),
                    orderBy: { createdAt: 'desc' },
                })
            ).map(({ path, ...x }) => x),
            total: await this.tech.prisma.techFile.count({ where }),
            history:
                'Старые публичные документы не импортируются и не приписываются новым действиям.',
        };
    }
    @Get('files/:id') async file(@Req() req: any, @Param('id') id: string) {
        allow(req, 'events');
        const f = await this.tech.prisma.techFile.findUnique({ where: { id } });
        if (!f) throw new BadRequestException('Файл не найден');
        const { path, ...visible } = f;
        return visible;
    }
    @Get('files/:id/original') async original(
        @Req() req: any,
        @Param('id') id: string,
        @Res() res: any,
    ) {
        allow(req, 'originals');
        await this.tech.audit(req.tech.id, 'file.original.view', id);
        const { row, buffer } = await this.tech.fileBytes(id);
        res.setHeader('Cache-Control', 'no-store');
        res.setHeader('Content-Type', row.mime);
        res.setHeader('X-Content-Type-Options', 'nosniff');
        res.setHeader(
            'Content-Disposition',
            `inline; filename="document-${id}"`,
        );
        res.send(buffer);
    }
    @Get('notifications') async notifications(
        @Req() req: any,
        @Query() q: any,
    ) {
        allow(req, 'events');
        const where:any = { accountId: req.tech.id };
        const dates=recordDates(q);if(dates)where.createdAt=dates;
        if(q.severity)where.severity=String(q.severity);
        if(q.acknowledged)where.acknowledgedAt=q.acknowledged==='true'?{not:null}:null;
        if(q.pushSent)where.pushAt=q.pushSent==='true'?{not:null}:null;
        return {
            items: await this.tech.prisma.techNotification.findMany({
                where,
                ...paging(q),
                orderBy: { createdAt: 'desc' },
            }),
            total: await this.tech.prisma.techNotification.count({ where }),
            vapidPublicKey: this.tech.vapid?.publicKey ?? null,
        };
    }
    @Post('notifications/:id/ack') async ack(
        @Req() req: any,
        @Param('id') id: string,
    ) {
        allow(req, 'events');
        return this.tech.prisma.techNotification.updateMany({
            where: { id, accountId: req.tech.id },
            data: { acknowledgedAt: new Date() },
        });
    }
    @Post('push') async push(@Req() req: any, @Body() b: any) {
        allow(req, 'events');
        let url: URL;
        try {
            url = new URL(b.endpoint);
        } catch {
            throw new BadRequestException('Некорректный push endpoint');
        }
        const allowed = [
            'fcm.googleapis.com',
            'updates.push.services.mozilla.com',
            'web.push.apple.com',
        ];
        if (
            url.protocol !== 'https:' ||
            url.username ||
            url.password ||
            url.port ||
            isIP(url.hostname) ||
            (!allowed.includes(url.hostname) &&
                !url.hostname.endsWith('.notify.windows.com'))
        )
            throw new BadRequestException('Неподдерживаемый push-провайдер');
        if (
            !b.keys ||
            typeof b.keys.p256dh !== 'string' ||
            typeof b.keys.auth !== 'string' ||
            JSON.stringify(b).length > 4000
        )
            throw new BadRequestException();
        const existing = await this.tech.prisma.techPush.findUnique({
            where: { endpoint: b.endpoint },
        });
        if (existing && existing.accountId !== req.tech.id)
            throw new ForbiddenException(
                'Подписка принадлежит другой учётной записи',
            );
        return this.tech.prisma.techPush.upsert({
            where: { endpoint: b.endpoint },
            create: {
                accountId: req.tech.id,
                endpoint: b.endpoint,
                subscription: { endpoint: b.endpoint, keys: b.keys },
            },
            update: { subscription: { endpoint: b.endpoint, keys: b.keys } },
        });
    }
    @Get('settings') async settings(@Req() req: any) {
        allow(req, 'settings');
        return {
            rules: await this.tech.prisma.techRule.findMany(),
            defaults: RULE_DEFAULTS,
            accounts: await this.tech.prisma.techAccount.findMany({
                select: {
                    id: true,
                    login: true,
                    permissions: true,
                    disabled: true,
                    createdAt: true,
                },
            }),
        };
    }
    @Post('settings/rules/:key') async rules(
        @Req() req: any,
        @Param('key') key: string,
        @Body() b: any,
    ) {
        allow(req, 'settings');
        await this.tech.reauth(req.tech, b.password);
        const v = b.value;
        let valid = false;
        if (key === 'retention')
            valid =
                Number.isInteger(v?.eventDays) &&
                v.eventDays >= 7 &&
                v.eventDays <= 730 &&
                Number.isInteger(v.fileDays) &&
                v.fileDays >= 7 &&
                v.fileDays <= 730;
        if (key === 'image')
            valid =
                typeof v?.version === 'string' &&
                v.version.length <= 60 &&
                Number.isFinite(v.rejectVariance) &&
                v.rejectVariance >= 0 &&
                v.rejectVariance <= 100 &&
                Number.isFinite(v.reviewVariance) &&
                v.reviewVariance >= v.rejectVariance &&
                v.reviewVariance <= 1000 &&
                Number.isInteger(v.maxBytes) &&
                v.maxBytes >= 1024 &&
                v.maxBytes <= 10485760;
        if (key === 'security')
            valid =
                Number.isInteger(v?.threshold) &&
                v.threshold >= 3 &&
                v.threshold <= 100 &&
                Number.isInteger(v.windowMinutes) &&
                v.windowMinutes >= 1 &&
                v.windowMinutes <= 60;
        if (!valid) throw new BadRequestException('Некорректные правила');
        await this.tech.audit(req.tech.id, 'rule.update', key, {
            before: await this.tech.rule(key),
            after: v,
        });
        return this.tech.prisma.techRule.upsert({
            where: { key },
            create: { key, value: v },
            update: { value: v },
        });
    }
    @Post('settings/accounts') async accounts(@Req() req: any, @Body() b: any) {
        allow(req, 'settings');
        allow(req, 'danger');
        await this.tech.reauth(req.tech, b.password);
        if (
            !Array.isArray(b.permissions) ||
            b.permissions.some((x) => !PERMISSIONS.includes(x))
        )
            throw new BadRequestException('Некорректные права');
        if (b.id === req.tech.id)
            throw new BadRequestException(
                'Самостоятельное изменение своей записи запрещено',
            );
        if (typeof b.login !== 'string' || !/^[a-z0-9_.-]{3,60}$/.test(b.login))
            throw new BadRequestException('Некорректный логин');
        const data: any = {
            login: b.login,
            permissions: b.permissions,
            disabled: b.disabled === true,
        };
        if (b.newPassword) {
            if (
                typeof b.newPassword !== 'string' ||
                b.newPassword.length < 14 ||
                Buffer.byteLength(b.newPassword) > 72
            )
                throw new BadRequestException('Пароль: 14–72 символа');
            data.passwordHash = await bcrypt.hash(b.newPassword, 12);
        }
        if (!b.id && !data.passwordHash)
            throw new BadRequestException('Нужен пароль новой записи');
        await this.tech.audit(req.tech.id, 'account.configure', b.id ?? null, {
            login: b.login,
            permissions: b.permissions,
            disabled: data.disabled,
        });
        const a = b.id
            ? await this.tech.prisma.techAccount.update({
                  where: { id: b.id },
                  data,
              })
            : await this.tech.prisma.techAccount.create({ data });
        if (b.id)
            await this.tech.prisma.techSession.updateMany({
                where: { accountId: b.id },
                data: { revokedAt: new Date() },
            });
        return { id: a.id };
    }
    @Get('audit')
    async auditRecords(@Req() req: any, @Query() q: any) {
        allow(req, 'settings');
        allow(req, 'personal');
        return {
            items: (
                await this.tech.prisma.techAudit.findMany({
                    ...paging(q),
                    orderBy: { seq: 'desc' },
                })
            ).map((x) => ({ ...x, seq: String(x.seq) })),
            total: await this.tech.prisma.techAudit.count(),
        };
    }

    @Post('audit/verify') async audit(@Req() req: any) {
        allow(req, 'settings');
        return this.tech.verifyAudit();
    }
}
// Existing app authentication is required; technical identities cannot use this route.
@Controller('technical-client')
@UseGuards(JwtAuthGuard)
export class TechnicalClientController {
    constructor(private tech: TechnicalService) {}
    @Post('event') async event(@Req() req: any, @Body() b: any) {
        if (
            !['form.open', 'form.abandon', 'retry', 'screen.open'].includes(
                b.action,
            ) ||
            !safeId(b.objectId ?? 'unknown')
        )
            throw new BadRequestException();
        const allowed = await this.tech.prisma.techEvent.count({
            where: {
                userId: req.user.sub,
                action: { startsWith: 'client.' },
                at: { gte: new Date(Date.now() - 60000) },
            },
        });
        if (allowed >= 30)
            throw new ForbiddenException('Лимит событий устройства');
        return this.tech.prisma.techEvent.create({
            data: {
                requestId: req.techRequestId,
                userId: req.user.sub,
                sessionId: safeId(req.headers['x-client-session']),
                objectId: b.objectId ?? null,
                action: 'client.' + b.action,
                stage: 'FINISH',
                result: 'REPORTED',
                message:
                    'Событие сообщено устройством; не подтверждает выполнение серверной операции',
            },
        });
    }
}
