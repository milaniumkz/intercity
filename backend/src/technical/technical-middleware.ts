import { TechnicalService } from './technical.service';
import { requestIdentity, safeMessage, techContext } from './technical-utils';
export function technicalMiddleware(tech: TechnicalService) {
    return (req: any, res: any, next: any) => {
        if (
            !String(req.url).startsWith('/api/') ||
            String(req.url).startsWith('/api/technical/panel')
        )
            return next();
        const identity = requestIdentity(req),
            started = Date.now();
        req.techRequestId = identity.requestId;
        res.setHeader('X-Request-ID', identity.requestId);
        let message: string | undefined,
            done = false;
        const originalJson = res.json.bind(res);
        res.json = (body: any) => {
            if (res.statusCode >= 400) {
                const raw = body?.message;
                message = safeMessage(
                    Array.isArray(raw)
                        ? raw.join('; ')
                        : (raw ?? 'Операция отклонена'),
                );
            }
            return originalJson(body);
        };
        const begin = tech.begin(req, identity);
        const finish = (aborted: boolean) => {
            if (done) return;
            done = true;
            void begin
                .then(() => req.techEvidencePending)
                .then(() =>
                    tech.finish(
                        req,
                        identity,
                        res.statusCode,
                        Date.now() - started,
                        aborted,
                        message,
                    ),
                );
        };
        res.on('finish', () => finish(false));
        res.on('close', () => finish(!res.writableFinished));
        techContext.run({ requestId: identity.requestId }, next);
    };
}
