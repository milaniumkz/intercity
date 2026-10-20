import { JwtService } from '@nestjs/jwt';
import { TechnicalService } from './technical.service';
// Existing driver originals must no longer be anonymously served by express.static.
export function legacyFilesGuard(tech: TechnicalService, jwt: JwtService) {
    return async (req: any, res: any, next: any) => {
        req.techStaticPath = '/uploads/:profile/:file';
        let decoded: string;
        try {
            decoded = decodeURIComponent(String(req.path));
        } catch {
            return res
                .status(400)
                .json({ message: 'Некорректный путь документа' });
        }
        if (
            decoded.includes('\\') ||
            decoded.includes('\0') ||
            decoded.split('/').some((x) => x === '.' || x === '..')
        )
            return res
                .status(403)
                .json({ message: 'Недопустимый путь документа' });
        const directory = decoded.split('/')[1];
        if (!/^[0-9a-f-]{36}$/i.test(directory ?? ''))
            return res.status(404).json({ message: 'Документ не найден' });
        try {
            const profile = await tech.prisma.driverProfile.findUnique({
                where: { id: directory },
                select: { id: true, userId: true },
            });
            if (!profile)
                return res.status(404).json({ message: 'Документ не найден' });
            req.techObjectId = profile.id;
            let actor: string | null = null;
            const cookie = String(req.headers.cookie ?? '')
                .split(';')
                .map((x) => x.trim())
                .find((x) => x.startsWith('tech_session='));
            const account = await tech.session(cookie?.slice(13) ?? '');
            if (account) req.tech = account;
            if (account?.permissions.includes('originals')) actor = account.id;
            const bearer = String(req.headers.authorization ?? '');
            if (!actor && bearer.startsWith('Bearer ')) {
                const payload = jwt.verify(bearer.slice(7), {
                    secret: process.env.JWT_SECRET,
                });
                const user = await tech.prisma.user.findUnique({
                    where: { id: payload.sub },
                    select: {
                        id: true,
                        role: true,
                        authVersion: true,
                        blockedAt: true,
                        mustChangePassword: true,
                    },
                });
                if (
                    user &&
                    !user.blockedAt &&
                    !user.mustChangePassword &&
                    (payload.ver ?? 0) === user.authVersion
                )
                    req.techUserId = user.id;
                if (
                    user &&
                    !user.blockedAt &&
                    !user.mustChangePassword &&
                    (payload.ver ?? 0) === user.authVersion &&
                    (user.id === profile.userId || user.role === 'ADMIN')
                )
                    actor = 'app:' + user.id;
            }
            if (!actor)
                return res.status(403).json({
                    message: 'Для доступа к оригиналу требуется авторизация',
                });
            await tech.audit(actor, 'legacy.file.original.view', profile.id, {
                fileName: String(req.path).split('/').pop()?.slice(0, 160),
                provenance: 'Автор и время старой загрузки неизвестны',
            });
            res.setHeader('Cache-Control', 'no-store');
            res.setHeader('X-Content-Type-Options', 'nosniff');
            res.setHeader(
                'Content-Security-Policy',
                "default-src 'none'; sandbox",
            );
            next();
        } catch {
            return res.status(403).json({ message: 'Нет доступа к документу' });
        }
    };
}
