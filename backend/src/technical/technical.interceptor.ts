import {
    CallHandler,
    ExecutionContext,
    Injectable,
    NestInterceptor,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';
import { TechnicalService } from './technical.service';
import { safeId, techContext } from './technical-utils';
@Injectable()
export class TechnicalEvidenceInterceptor implements NestInterceptor {
    constructor(private tech: TechnicalService) {}
    async intercept(
        context: ExecutionContext,
        next: CallHandler,
    ): Promise<Observable<any>> {
        const req = context.switchToHttp().getRequest();
        const userId = req.user?.sub;
        const contextStore = techContext.getStore();
        if (contextStore) contextStore.userId = userId;
        await this.tech.authenticated(req);
        if (userId && String(req.route?.path).includes('/realtime/'))
            this.tech.trackConnection(
                userId,
                context.switchToHttp().getResponse(),
            );
        // Only explicitly approved non-secret fields. No body/response serialization.
        const profileMutation =
            userId &&
            req.method === 'POST' &&
            String(req.route?.path).match(
                /\/driver\/(profile|online|docs\/(upload|complete))$/,
            );
        const before = profileMutation ? await this.snapshot(userId) : null;
        if (profileMutation) req.techObjectId = before?.profileId ?? null;
        return next.handle().pipe(
            tap({
                next: (value) => {
                    const objectId =
                        value?.id ??
                        value?.order?.id ??
                        value?.request?.id ??
                        value?.booking?.id;
                    if (safeId(objectId)) req.techObjectId = objectId;
                    if (profileMutation)
                        req.techEvidencePending = this.snapshot(userId)
                            .then((after) => {
                                const changes: any = {};
                                for (const key of Object.keys(after ?? {}))
                                    if (
                                        JSON.stringify(before?.[key]) !==
                                        JSON.stringify(after[key])
                                    )
                                        changes[key] = {
                                            before: before?.[key] ?? null,
                                            after: after[key],
                                        };
                                req.techObjectId =
                                    after?.profileId ?? req.techObjectId;
                                req.techEvidence = { changes };
                            })
                            .catch(() => {
                                req.techEvidence = { changesUnavailable: true };
                            });
                },
            }),
        );
    }
    private async snapshot(userId: string) {
        const p = await this.tech.prisma.driverProfile.findUnique({
            where: { userId },
            select: { id: true, status: true, carModel: true },
        });
        return p
            ? { profileId: p.id, status: p.status, carModel: p.carModel }
            : null;
    }
}
