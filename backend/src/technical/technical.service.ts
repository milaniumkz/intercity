import {
    BadRequestException,
    ForbiddenException,
    Injectable,
    OnModuleInit,
    OnModuleDestroy,
    UnauthorizedException,
} from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { promises as fs } from 'fs';
import { join, resolve } from 'path';
import { randomBytes, timingSafeEqual } from 'crypto';
import * as bcrypt from 'bcrypt';
import * as os from 'os';
import sharp from 'sharp';
import * as webpush from 'web-push';
import {
    digest,
    hmac,
    PERMISSIONS,
    RULE_DEFAULTS,
    safeMessage,
    safeId,
    techContext,
    canonical,
} from './technical-utils';

@Injectable()
export class TechnicalService implements OnModuleInit, OnModuleDestroy {
    readonly storage = resolve(
        process.env.TECH_STORAGE_DIR || join(process.cwd(), 'technical-data'),
    );
    private auditKey: Buffer;
    private timer: NodeJS.Timeout;
    private running = false;
    private connections = new Map<string, Set<any>>();
    private lastCollectionSuccess: Date | null = null;
    private collectionFailures = 0;
    private maintenanceAt: Date | null = null;
    private lastPushError: string | null = null;
    readonly startedAt = new Date();
    vapid: { publicKey: string; privateKey: string };
    constructor(readonly prisma: PrismaService) {}
    async onModuleInit() {
        await fs.mkdir(this.storage, { recursive: true, mode: 0o700 });
        const keyPath = join(this.storage, 'audit.key');
        try {
            await fs.writeFile(keyPath, randomBytes(32), {
                flag: 'wx',
                mode: 0o600,
            });
        } catch (e) {
            if (e.code !== 'EEXIST') throw e;
        }
        this.auditKey = await fs.readFile(keyPath);
        const vapidPath = join(this.storage, 'vapid.json');
        if (
            process.env.TECH_VAPID_PUBLIC_KEY &&
            process.env.TECH_VAPID_PRIVATE_KEY
        )
            this.vapid = {
                publicKey: process.env.TECH_VAPID_PUBLIC_KEY,
                privateKey: process.env.TECH_VAPID_PRIVATE_KEY,
            };
        else {
            try {
                await fs.writeFile(
                    vapidPath,
                    JSON.stringify(webpush.generateVAPIDKeys()),
                    { flag: 'wx', mode: 0o600 },
                );
            } catch (e) {
                if (e.code !== 'EEXIST') throw e;
            }
            this.vapid = JSON.parse(await fs.readFile(vapidPath, 'utf8'));
        }
        this.timer = setInterval(() => void this.maintenance(), 30000);
        this.timer.unref();
    }
    onModuleDestroy() {
        clearInterval(this.timer);
    }
    async rule(key: string) {
        return (
            (await this.prisma.techRule.findUnique({ where: { key } }))
                ?.value ?? RULE_DEFAULTS[key]
        );
    }
    async audit(
        actorId: string,
        action: string,
        objectId: string | null,
        data: any = {},
    ) {
        const at = new Date();
        data = JSON.parse(JSON.stringify(data));
        return this.prisma.$transaction(async (tx) => {
            await tx.$executeRaw`SELECT pg_advisory_xact_lock(77203419)`;
            const last = await tx.techAudit.findFirst({
                orderBy: { seq: 'desc' },
            });
            const previousHash = last?.hash ?? 'GENESIS';
            const record = {
                at: at.toISOString(),
                actorId,
                action,
                objectId,
                data,
            };
            const hash = hmac(this.auditKey, previousHash + canonical(record));
            return tx.techAudit.create({
                data: {
                    at,
                    actorId,
                    action,
                    objectId,
                    data,
                    previousHash,
                    hash,
                },
            });
        });
    }
    async verifyAudit() {
        let cursor: bigint | undefined,
            previous = 'GENESIS',
            count = 0;
        for (;;) {
            const rows = await this.prisma.techAudit.findMany({
                where: cursor ? { seq: { gt: cursor } } : {},
                orderBy: { seq: 'asc' },
                take: 500,
            });
            if (!rows.length) break;
            for (const r of rows) {
                const expected = hmac(
                    this.auditKey,
                    r.previousHash +
                        canonical({
                            at: r.at.toISOString(),
                            actorId: r.actorId,
                            action: r.action,
                            objectId: r.objectId,
                            data: r.data,
                        }),
                );
                if (r.previousHash !== previous || r.hash !== expected)
                    return {
                        valid: false,
                        atSequence: String(r.seq),
                        checked: count,
                    };
                previous = r.hash;
                cursor = r.seq;
                count++;
            }
        }
        return {
            valid: true,
            checked: count,
            head: previous,
            limitation:
                'Удаление хвоста выявляется только сравнением с ранее сохранённой внешней контрольной точкой.',
        };
    }
    async begin(req: any, identity: any) {
        try {
            await this.prisma.techEvent.create({
                data: {
                    ...identity,
                    requestId: identity.requestId,
                    action:
                        req.method +
                        ' /api/' +
                        String(req.path || req.url)
                            .split('/')[2]
                            ?.replace(/[^a-z-]/g, '')
                            .slice(0, 30),
                    stage: 'START',
                    result: 'PENDING',
                },
            });
            this.lastCollectionSuccess = new Date();
        } catch {
            this.collectionFailures++;
        }
    }
    async authenticated(req: any) {
        if (!req.user?.sub || !req.techRequestId) return;
        try {
            await this.prisma.techEvent.create({
                data: {
                    userId: req.user.sub,
                    requestId: req.techRequestId,
                    sessionId: safeId(req.headers['x-client-session']),
                    objectId: req.params?.id ?? null,
                    action:
                        req.method + ' ' + String(req.route?.path ?? '/api'),
                    stage: 'PROCESSING',
                    result: 'PENDING',
                    details: { actorRole: req.user.role },
                },
            });
        } catch {
            this.collectionFailures++;
        }
    }

    async finish(
        req: any,
        identity: any,
        status: number,
        duration: number,
        aborted: boolean,
        message?: string,
    ) {
        try {
            if (req.techEvidencePending) await req.techEvidencePending;
            const path = String(req.route?.path || '/unmatched').slice(0, 180);
            const action = req.method + ' ' + path;
            const userId = req.user?.sub ?? req.techUserId ?? null;
            const objectId = req.params?.id ?? req.techObjectId ?? null;
            const identitySnapshot = userId
                ? await this.prisma.user.findUnique({
                      where: { id: userId },
                      select: { name: true, role: true },
                  })
                : null;
            let issueId: string | null = null;
            const fileFailure = path.includes('/docs/upload') && status >= 400;
            if (
                status >= 500 ||
                status === 401 ||
                status === 403 ||
                status === 413 ||
                fileFailure
            ) {
                const kind =
                    status >= 500 ? 'ERROR' : fileFailure ? 'FILE' : 'SECURITY';
                const title =
                    status >= 500
                        ? 'Ошибка серверной операции'
                        : fileFailure
                          ? 'Отказ при загрузке документа'
                          : 'Отказ доступа или входа';
                // No IP-based attribution. Security rules aggregate facts; a rule match is not proof of abuse.
                let shouldGroup = kind !== 'SECURITY';
                if (!shouldGroup) {
                    const rule: any = await this.rule('security');
                    const count = await this.prisma.techEvent.count({
                        where: {
                            at: {
                                gte: new Date(
                                    Date.now() - rule.windowMinutes * 60000,
                                ),
                            },
                            status: { in: [401, 403] },
                            ...(userId ? { userId } : { ip: identity.ip }),
                        },
                    });
                    req.techEvidence = {
                        ...(req.techEvidence ?? {}),
                        securityRule: {
                            key: 'repeated-access-denials-v1',
                            threshold: rule.threshold,
                            windowMinutes: rule.windowMinutes,
                            observedCount: count + 1,
                            grouping: userId
                                ? 'authenticated-user'
                                : 'network-address',
                            interpretation:
                                'Совпадение правила не доказывает нарушение и не устанавливает личность по IP',
                        },
                    };
                    shouldGroup = count + 1 >= rule.threshold;
                }
                if (shouldGroup) {
                    const issue = await this.touchIssue({
                        where: {
                            fingerprint: digest(
                                kind + ':' + action + ':' + status,
                            ),
                        },
                        create: {
                            fingerprint: digest(
                                kind + ':' + action + ':' + status,
                            ),
                            kind,
                            title,
                            severity: status >= 500 ? 'CRITICAL' : 'WARNING',
                        },
                        update: { count: { increment: 1 }, lastAt: new Date() },
                    });
                    issueId = issue.id;
                    if (
                        issue.mutedUntil === null ||
                        issue.mutedUntil < new Date() ||
                        issue.severity === 'CRITICAL'
                    ) {
                        const accounts = await this.prisma.techAccount.findMany(
                            {
                                where: {
                                    disabled: false,
                                    permissions: { has: 'events' },
                                },
                                select: { id: true },
                            },
                        );
                        await this.prisma.techNotification.createMany({
                            data: accounts.map((a) => ({
                                accountId: a.id,
                                issueId: issue.id,
                                severity: issue.severity,
                            })),
                            skipDuplicates: true,
                        });
                    }
                }
            }
            await this.prisma.techEvent.create({
                data: {
                    ...identity,
                    userId,
                    actorId: req.tech?.id ?? null,
                    objectId,
                    action,
                    stage: aborted ? 'ABORTED' : 'FINISH',
                    result: aborted
                        ? 'UNKNOWN'
                        : status >= 400
                          ? 'FAILURE'
                          : 'SUCCESS',
                    status,
                    durationMs: duration,
                    message: message ? safeMessage(message) : null,
                    issueId,
                    details: {
                        ...(req.techEvidence ?? {}),
                        actorRole: req.user?.role ?? null,
                        identity: identitySnapshot
                            ? { ...identitySnapshot, organization: null }
                            : null,
                    },
                },
            });
            this.lastCollectionSuccess = new Date();
            if (req.tech)
                await this.audit(
                    req.tech.id,
                    'http.result',
                    identity.requestId,
                    { action, status, aborted },
                );
        } catch {
            this.collectionFailures++;
        }
    }
    private async touchIssue(args: any) {
        return this.prisma.$transaction(async (tx) => {
            await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${args.where.fingerprint}))`;
            const old = await tx.techIssue.findUnique({ where: args.where });
            const reopen =
                old && ['RESOLVED', 'NOT_CONFIRMED'].includes(old.status);
            const issue = await tx.techIssue.upsert({
                ...args,
                update: {
                    ...args.update,
                    ...(reopen
                        ? {
                              status: 'NEW',
                              confirmedCause: null,
                              verification: null,
                              fixedVersion: null,
                              hypothesis:
                                  'Повторное появление после закрытия; требуется новая проверка',
                          }
                        : {}),
                },
            });
            if (reopen)
                await tx.techNotification.updateMany({
                    where: { issueId: issue.id },
                    data: {
                        acknowledgedAt: null,
                        pushAt: null,
                        nextAttemptAt: new Date(),
                    },
                });
            return issue;
        });
    }

    async systemError(value: unknown) {
        try {
            const message = safeMessage(value),
                fingerprint = digest('runtime:' + message),
                context = techContext.getStore();
            const issue = await this.touchIssue({
                where: { fingerprint },
                create: {
                    fingerprint,
                    kind: 'ERROR',
                    severity: 'CRITICAL',
                    title: 'Ошибка компонента сервера',
                },
                update: { count: { increment: 1 }, lastAt: new Date() },
            });
            await this.prisma.techEvent.create({
                data: {
                    requestId:
                        context?.requestId ??
                        'runtime:' + randomBytes(16).toString('hex'),
                    userId: context?.userId,
                    actorId: 'system',
                    action: 'system.error',
                    stage: 'FINISH',
                    result: 'FAILURE',
                    message,
                    issueId: issue.id,
                },
            });
            const accounts = await this.prisma.techAccount.findMany({
                where: { disabled: false, permissions: { has: 'events' } },
                select: { id: true },
            });
            await this.prisma.techNotification.createMany({
                data: accounts.map((a) => ({
                    accountId: a.id,
                    issueId: issue.id,
                    severity: 'CRITICAL',
                })),
                skipDuplicates: true,
            });
        } catch {
            this.collectionFailures++;
        }
    }

    async login(login: string, password: string, ip: string) {
        const keys = [
            'login:' + digest(login.toLowerCase()),
            'ip:' + digest(ip),
        ];
        for (const key of keys) {
            const r = await this.prisma.techLoginAttempt.findUnique({
                where: { key },
            });
            if (r && r.until > new Date() && r.failures >= 8)
                throw new UnauthorizedException('Вход временно ограничен');
        }
        const account = await this.prisma.techAccount.findUnique({
            where: { login: login.toLowerCase() },
        });
        const valid =
            account &&
            !account.disabled &&
            (await bcrypt.compare(password, account.passwordHash));
        if (!valid) {
            for (const key of keys)
                await this.prisma.techLoginAttempt.upsert({
                    where: { key },
                    create: {
                        key,
                        failures: 1,
                        until: new Date(Date.now() + 15 * 60000),
                    },
                    update: {
                        failures: { increment: 1 },
                        until: new Date(Date.now() + 15 * 60000),
                    },
                });
            await this.audit('anonymous', 'login.failed', null, {
                loginHash: digest(login.toLowerCase()),
            });
            throw new UnauthorizedException('Неверные учётные данные');
        }
        for (const key of keys)
            await this.prisma.techLoginAttempt.deleteMany({ where: { key } });
        const token = randomBytes(32).toString('base64url');
        await this.audit(account.id, 'login.success', null);
        await this.prisma.techSession.create({
            data: {
                accountId: account.id,
                tokenHash: digest(token),
                expiresAt: new Date(Date.now() + 8 * 3600000),
            },
        });
        return {
            token,
            account: {
                id: account.id,
                login: account.login,
                permissions: account.permissions,
            },
        };
    }
    async session(token: string) {
        if (!token || token.length > 100) return null;
        const s = await this.prisma.techSession.findUnique({
            where: { tokenHash: digest(token) },
        });
        if (!s || s.revokedAt || s.expiresAt < new Date()) return null;
        const a = await this.prisma.techAccount.findUnique({
            where: { id: s.accountId },
        });
        return a && !a.disabled
            ? {
                  id: a.id,
                  login: a.login,
                  permissions: a.permissions,
                  sessionId: s.id,
              }
            : null;
    }
    async reauth(actor: any, password: string) {
        const key = 'reauth:' + actor.id,
            r = await this.prisma.techLoginAttempt.findUnique({
                where: { key },
            });
        if (r && r.until > new Date() && r.failures >= 8)
            throw new ForbiddenException(
                'Повторная проверка временно ограничена',
            );
        const a = await this.prisma.techAccount.findUnique({
            where: { id: actor.id },
        });
        if (
            !password ||
            !a ||
            !(await bcrypt.compare(password, a.passwordHash))
        ) {
            await this.prisma.techLoginAttempt.upsert({
                where: { key },
                create: {
                    key,
                    failures: 1,
                    until: new Date(Date.now() + 900000),
                },
                update: {
                    failures: { increment: 1 },
                    until: new Date(Date.now() + 900000),
                },
            });
            throw new ForbiddenException(
                'Повторная проверка пароля не пройдена',
            );
        }
        await this.prisma.techLoginAttempt.deleteMany({ where: { key } });
    }
    async overview() {
        const checkedAt = new Date();
        let db: any = { status: 'unavailable' };
        try {
            await this.prisma.$queryRaw`SELECT 1`;
            db = { status: 'available', lastSuccessAt: checkedAt };
        } catch {}
        let storage: any = { status: 'unavailable' };
        try {
            const test = join(
                this.storage,
                'probe-' + randomBytes(8).toString('hex'),
            );
            await fs.writeFile(test, 'probe', { flag: 'wx', mode: 0o600 });
            await fs.unlink(test);
            const stat = await fs.statfs(this.storage);
            storage = {
                status: 'available',
                lastSuccessAt: checkedAt,
                freeBytes: Number(stat.bavail) * Number(stat.bsize),
                totalBytes: Number(stat.blocks) * Number(stat.bsize),
                scope: 'Файловая система закрытого хранилища',
            };
        } catch {}
        const since = new Date(Date.now() - 86400000);
        let counts: any = null,
            reports: any = [];
        if (db.status === 'available') {
            counts = {
                errors: await this.prisma.techEvent.count({
                    where: { at: { gte: since }, status: { gte: 500 } },
                }),
                affectedUsers: (
                    await this.prisma.techEvent.groupBy({
                        by: ['userId'],
                        where: {
                            at: { gte: since },
                            status: { gte: 400 },
                            userId: { not: null },
                        },
                    })
                ).length,
                newIssues: await this.prisma.techIssue.count({
                    where: { status: 'NEW' },
                }),
                fileProblems: await this.prisma.techFile.count({
                    where: {
                        verdict: { in: ['REJECT', 'REVIEW'] },
                        deletedAt: null,
                    },
                }),
            };
            reports = await this.prisma.techReport.findMany({
                orderBy: { at: 'desc' },
                take: 30,
            });
        }
        return {
            checkedAt,
            api: { status: 'available', lastSuccessAt: checkedAt },
            database: db,
            storage,
            application: {
                status: 'unknown',
                reason: 'Нет отдельного внешнего браузерного мониторинга',
            },
            resources: {
                scope: 'Процесс/контейнер API, не весь VPS',
                uptimeSeconds: process.uptime(),
                rssBytes: process.memoryUsage().rss,
                loadAverage: os.loadavg(),
                cpuCount: os.cpus().length,
            },
            collector: {
                lastSuccessAt: this.lastCollectionSuccess,
                failures: this.collectionFailures,
            },
            jobs: {
                technicalMaintenanceAt: this.maintenanceAt,
                otherJobs: 'Нет общего источника состояния всех фоновых задач',
                pushConfigured: !!this.vapid,
                lastPushError: this.lastPushError,
            },
            version: process.env.RELEASE_SHA ?? 'Не передана процессу',
            counts,
            reports,
        };
    }
    async saveFile(
        userId: string,
        objectId: string,
        docType: string,
        buffer: Buffer,
    ) {
        const rule: any = await this.rule('image');
        const requestId = techContext.getStore()?.requestId ?? 'unlinked';
        if (buffer.length > rule.maxBytes)
            throw new BadRequestException('Файл превышает допустимый размер');
        let verdict = 'ACCEPT',
            reason =
                'Формат и технические показатели прошли проверку; читаемость текста не гарантируется',
            mime: string,
            metrics: any;
        try {
            const image = sharp(buffer, {
                limitInputPixels: 40000000,
                failOn: 'error',
            });
            const meta = await image.metadata();
            if (
                !['jpeg', 'png', 'webp'].includes(meta.format) ||
                meta.pages > 1
            )
                throw new Error('format');
            mime = 'image/' + (meta.format === 'jpeg' ? 'jpeg' : meta.format);
            const { data, info } = await image
                .rotate()
                .resize({
                    width: 512,
                    height: 512,
                    fit: 'inside',
                    withoutEnlargement: true,
                })
                .greyscale()
                .raw()
                .toBuffer({ resolveWithObject: true });
            let sum = 0,
                sq = 0,
                n = 0;
            for (let y = 1; y < info.height - 1; y++)
                for (let x = 1; x < info.width - 1; x++) {
                    const i = y * info.width + x,
                        v =
                            4 * data[i] -
                            data[i - 1] -
                            data[i + 1] -
                            data[i - info.width] -
                            data[i + info.width];
                    sum += v;
                    sq += v * v;
                    n++;
                }
            const variance = n ? sq / n - (sum / n) ** 2 : 0;
            metrics = {
                width: meta.width,
                height: meta.height,
                laplacianVariance: variance,
                screenRecapture: 'Не определяется данным алгоритмом',
            };
            if (variance < rule.rejectVariance) {
                verdict = 'REJECT';
                reason =
                    'Изображение почти однородное или крайне размыто: недостаточно деталей для проверки';
            } else if (variance < rule.reviewVariance) {
                verdict = 'REVIEW';
                reason = 'Сниженная детализация: требуется ручная проверка';
            }
        } catch {
            throw new BadRequestException(
                'Недопустимый или повреждённый файл. Допускаются JPEG, PNG, WebP; оригинал небезопасного файла не сохранён',
            );
        }
        const id = randomBytes(16).toString('hex'),
            name = id + '.bin';
        await fs.writeFile(join(this.storage, name), buffer, {
            flag: 'wx',
            mode: 0o600,
        });
        let row: any;
        try {
            row = await this.prisma.techFile.create({
                data: {
                    id,
                    userId,
                    objectId,
                    requestId,
                    docType,
                    path: name,
                    mime,
                    size: buffer.length,
                    sha256: digest(buffer),
                    verdict,
                    reason,
                    algorithm: rule.version,
                    metrics,
                },
            });
        } catch (e) {
            await fs.unlink(join(this.storage, name)).catch(() => {});
            throw e;
        }
        await this.prisma.techEvent.create({
            data: {
                requestId,
                userId,
                objectId,
                action: 'document.quality',
                stage: 'FINISH',
                result:
                    verdict === 'REJECT'
                        ? 'FAILURE'
                        : verdict === 'REVIEW'
                          ? 'REVIEW'
                          : 'SUCCESS',
                message: reason,
                details: { fileId: id, algorithm: rule.version, metrics },
            },
        });
        if (verdict !== 'ACCEPT') {
            const fingerprint = digest('document.quality:' + verdict);
            const issue = await this.touchIssue({
                where: { fingerprint },
                create: {
                    fingerprint,
                    kind: 'FILE',
                    title:
                        verdict === 'REJECT'
                            ? 'Документ отклонён'
                            : 'Документ требует ручной проверки',
                    severity: 'WARNING',
                },
                update: { count: { increment: 1 }, lastAt: new Date() },
            });
            await this.prisma.techEvent.create({
                data: {
                    requestId,
                    userId,
                    objectId,
                    action: 'document.review',
                    stage: 'FINISH',
                    result: verdict,
                    issueId: issue.id,
                    details: { fileId: id },
                },
            });
            const accounts = await this.prisma.techAccount.findMany({
                where: { disabled: false, permissions: { has: 'events' } },
                select: { id: true },
            });
            await this.prisma.techNotification.createMany({
                data: accounts.map((a) => ({
                    accountId: a.id,
                    issueId: issue.id,
                    severity: 'WARNING',
                })),
                skipDuplicates: true,
            });
        }
        return row;
    }
    async fileBytes(id: string) {
        const row = await this.prisma.techFile.findUnique({ where: { id } });
        if (!row || row.deletedAt)
            throw new BadRequestException(
                'Оригинал отсутствует или срок хранения истёк',
            );
        const path = resolve(this.storage, row.path);
        if (!path.startsWith(this.storage + '/'))
            throw new ForbiddenException();
        let buffer: Buffer;
        try {
            buffer = await fs.readFile(path);
        } catch {
            throw new BadRequestException('Оригинал не найден в хранилище');
        }
        if (digest(buffer) !== row.sha256)
            throw new BadRequestException(
                'Контрольная сумма оригинала не совпадает',
            );
        return { row, buffer };
    }
    trackConnection(userId: string, res: any) {
        let set = this.connections.get(userId);
        if (!set) {
            set = new Set();
            this.connections.set(userId, set);
        }
        set.add(res);
        res.once('close', () => {
            set.delete(res);
            if (!set.size) this.connections.delete(userId);
        });
    }
    closeConnections(userId: string) {
        for (const res of this.connections.get(userId) ?? []) {
            res.end();
        }
        this.connections.delete(userId);
    }
    async userOperation(actor: any, id: string, action: string, body: any) {
        if (
            !body.confirm ||
            typeof body.reason !== 'string' ||
            body.reason.trim().length < 5
        )
            throw new BadRequestException(
                'Нужны подтверждение и причина (от 5 символов)',
            );
        await this.reauth(actor, body.password);
        const before = await this.prisma.user.findUnique({
            where: { id },
            select: {
                id: true,
                blockedAt: true,
                authVersion: true,
                mustChangePassword: true,
            },
        });
        if (!before) throw new BadRequestException('Пользователь не найден');
        const data: any = { authVersion: { increment: 1 } };
        if (action === 'block') data.blockedAt = new Date();
        else if (action === 'unblock') data.blockedAt = null;
        else if (action === 'temporary-password') {
            if (
                typeof body.temporaryPassword !== 'string' ||
                body.temporaryPassword.length < 12 ||
                body.temporaryPassword.length > 72
            )
                throw new BadRequestException(
                    'Временный пароль: от 12 до 72 символов',
                );
            data.password = await bcrypt.hash(body.temporaryPassword, 12);
            data.mustChangePassword = true;
        } else if (action !== 'revoke-sessions')
            throw new BadRequestException('Неизвестная операция');
        await this.audit(actor.id, 'user.' + action, id, {
            reason: safeMessage(body.reason),
            before,
        });
        await this.prisma.$transaction([
            this.prisma.user.update({ where: { id }, data }),
            this.prisma.refreshToken.deleteMany({ where: { userId: id } }),
        ]);
        this.closeConnections(id);
        await this.audit(actor.id, 'user.' + action + '.completed', id, {
            blocked:
                action === 'block'
                    ? true
                    : action === 'unblock'
                      ? false
                      : !!before.blockedAt,
            mustChangePassword:
                action === 'temporary-password' || before.mustChangePassword,
        });
        return { ok: true };
    }
    async maintenance() {
        if (this.running) return;
        this.running = true;
        try {
            const retention: any = await this.rule('retention');
            // File metadata is retained as a tombstone so history never claims an original still exists.
            const expired = await this.prisma.techFile.findMany({
                where: {
                    deletedAt: null,
                    createdAt: {
                        lt: new Date(
                            Date.now() - retention.fileDays * 86400000,
                        ),
                    },
                },
                take: 100,
            });
            for (const f of expired) {
                const url = '/api/driver/docs/files/' + f.id;
                if (
                    await this.prisma.driverProfile.count({
                        where: {
                            OR: [
                                'selfieUrl',
                                'passportUrl',
                                'driverLicenseUrl',
                                'techPassportFrontUrl',
                                'techPassportBackUrl',
                            ].map((k) => ({ [k]: url })),
                        },
                    })
                )
                    continue;
                try {
                    await fs.unlink(join(this.storage, f.path));
                } catch (e) {
                    if (e.code !== 'ENOENT') throw e;
                }
                await this.prisma.techFile.update({
                    where: { id: f.id },
                    data: { deletedAt: new Date() },
                });
            }
            const ids = await this.prisma.techEvent.findMany({
                where: {
                    at: {
                        lt: new Date(
                            Date.now() - retention.eventDays * 86400000,
                        ),
                    },
                },
                take: 1000,
                select: { id: true },
            });
            await this.prisma.techEvent.deleteMany({
                where: { id: { in: ids.map((x) => x.id) } },
            });
            await this.prisma.techSession.deleteMany({
                where: { expiresAt: { lt: new Date() } },
            });
            await this.prisma.techLoginAttempt.deleteMany({
                where: { until: { lt: new Date() } },
            });
            await this.scanDomain();
            await this.deliverPush();
            this.maintenanceAt = new Date();
        } catch {
            this.collectionFailures++;
        } finally {
            this.running = false;
        }
    }
    async scanDomain() {
        const cursor = (
            await this.prisma.appSettings.findUnique({
                where: { key: 'technicalTripScanCursor' },
            })
        )?.value;
        const reviews = await this.prisma.tripVerification.findMany({
            where: {
                status: 'REVIEW',
                ...(cursor ? { id: { gt: cursor } } : {}),
            },
            orderBy: { id: 'asc' },
            take: 100,
        });
        for (const trip of reviews) {
            const fingerprint = digest('trip.review:' + trip.id);
            if (
                await this.prisma.techIssue.findUnique({
                    where: { fingerprint },
                })
            )
                continue;
            const issue = await this.touchIssue({
                where: { fingerprint },
                create: {
                    fingerprint,
                    kind: 'DOMAIN',
                    title: 'Поездка направлена на проверку вознаграждения',
                    severity: 'WARNING',
                    hypothesis:
                        'Автоматическое правило требует проверки фактов; нарушение не установлено',
                },
                update: {},
            });
            await this.prisma.techEvent.create({
                data: {
                    userId: trip.driverUserId,
                    actorId: 'system',
                    requestId: 'process:' + trip.id,
                    objectId: trip.tripId,
                    action: 'system.trip.review',
                    stage: 'FINISH',
                    result: 'REVIEW',
                    issueId: issue.id,
                    details: {
                        rule: 'existing-trip-verification',
                        verificationId: trip.id,
                        reasons: trip.reasons,
                        completedAt: trip.completedAt,
                        source: 'Результат существующей проверки поездки; автор события — система, водитель — участник процесса. GPS не скопирован.',
                    },
                },
            });
            const accounts = await this.prisma.techAccount.findMany({
                where: { disabled: false, permissions: { has: 'events' } },
                select: { id: true },
            });
            await this.prisma.techNotification.createMany({
                data: accounts.map((a) => ({
                    accountId: a.id,
                    issueId: issue.id,
                    severity: 'WARNING',
                })),
                skipDuplicates: true,
            });
        }
        const nextCursor =
            reviews.length === 100 ? reviews[reviews.length - 1].id : '';
        await this.prisma.appSettings.upsert({
            where: { key: 'technicalTripScanCursor' },
            create: { key: 'technicalTripScanCursor', value: nextCursor },
            update: { value: nextCursor },
        });
    }
    async deliverPush() {
        if (!this.vapid) return;
        webpush.setVapidDetails(
            process.env.TECH_VAPID_SUBJECT ||
                process.env.PUBLIC_WEB_URL ||
                'https://intercity.89-207-255-27.sslip.io',
            this.vapid.publicKey,
            this.vapid.privateKey,
        );
        const subscribed = await this.prisma.techPush.findMany({
            select: { accountId: true },
            distinct: ['accountId'],
        });
        const enabled = await this.prisma.techAccount.findMany({
            where: {
                id: { in: subscribed.map((x) => x.accountId) },
                disabled: false,
                permissions: { has: 'events' },
            },
            select: { id: true },
        });
        const pending = await this.prisma.techNotification.findMany({
            where: {
                accountId: { in: enabled.map((x) => x.id) },
                pushAt: null,
                acknowledgedAt: null,
                nextAttemptAt: { lte: new Date() },
            },
            orderBy: { createdAt: 'asc' },
            take: 25,
        });
        for (const n of pending) {
            const account = await this.prisma.techAccount.findUnique({
                where: { id: n.accountId },
            });
            if (
                !account ||
                account.disabled ||
                !account.permissions.includes('events')
            )
                continue;
            const subscriptions = await this.prisma.techPush.findMany({
                where: { accountId: n.accountId },
            });
            if (!subscriptions.length) continue;
            let success = false;
            for (const s of subscriptions) {
                try {
                    await webpush.sendNotification(
                        s.subscription as any,
                        JSON.stringify({
                            title: 'INTERCITY: техническое уведомление',
                            body:
                                n.severity === 'CRITICAL'
                                    ? 'Требуется внимание к системе'
                                    : 'Новое событие в технической панели',
                            url: '/api/technical/panel/#issues/' + n.issueId,
                        }),
                        { TTL: 86400, timeout: 10000 },
                    );
                    success = true;
                } catch (e) {
                    this.lastPushError =
                        'Ошибка доставки Web Push, HTTP ' +
                        (e.statusCode ?? 'неизвестен');
                    if ([404, 410].includes(e.statusCode))
                        await this.prisma.techPush.deleteMany({
                            where: { id: s.id },
                        });
                }
            }
            await this.prisma.techNotification.update({
                where: { id: n.id },
                data: success
                    ? { pushAt: new Date(), attempts: { increment: 1 } }
                    : {
                          attempts: { increment: 1 },
                          nextAttemptAt: new Date(
                              Date.now() +
                                  Math.min(
                                      3600000,
                                      30000 * 2 ** Math.min(n.attempts, 7),
                                  ),
                          ),
                      },
            });
        }
    }
}
