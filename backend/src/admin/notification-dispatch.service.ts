import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { RealtimeService } from '../realtime/realtime.service';

type DispatchJobStatus = 'QUEUED' | 'RUNNING' | 'DONE' | 'FAILED';

type DispatchJob = {
    id: string;
    campaignId: string;
    status: DispatchJobStatus;
    retryCount?: number;
    requeuedFromJobId?: string;
    queuedAt: string;
    startedAt?: string;
    finishedAt?: string;
    successCount: number;
    failCount: number;
    lastError?: string;
};

@Injectable()
export class NotificationDispatchService {
    private readonly jobs = new Map<string, DispatchJob>();
    private readonly queue: string[] = [];
    private isWorkerRunning = false;
    private readonly maxJobs = 1000;
    private readonly retentionMs = 24 * 60 * 60 * 1000;
    private lastRetrySpikeAtMs = 0;
    private readonly retrySpikeCooldownMs = 10 * 60 * 1000;

    constructor(
        private readonly prisma: PrismaService,
        private readonly realtimeService: RealtimeService,
    ) { }

    async enqueue(
        campaignId: string,
        options?: { retryCount?: number; requeuedFromJobId?: string },
    ): Promise<DispatchJob> {
        this.cleanupJobs();
        const id = `job_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
        const job: DispatchJob = {
            id,
            campaignId,
            status: 'QUEUED',
            retryCount: options?.retryCount ?? 0,
            requeuedFromJobId: options?.requeuedFromJobId ?? undefined,
            queuedAt: new Date().toISOString(),
            successCount: 0,
            failCount: 0,
        };
        this.jobs.set(id, job);
        await this.createPersistentJob(job);
        this.queue.push(id);
        this.runWorker().catch(() => null);
        return job;
    }

    async getJob(jobId: string): Promise<DispatchJob | null> {
        this.cleanupJobs();
        const fromDb = await this.loadJobFromDb(jobId);
        if (fromDb) {
            this.jobs.set(fromDb.id, fromDb);
            return fromDb;
        }
        return this.jobs.get(jobId) ?? null;
    }

    async listJobs(limit = 100): Promise<DispatchJob[]> {
        this.cleanupJobs();
        const safeLimit = Math.max(1, Math.min(500, Number.isFinite(limit) ? limit : 100));
        const fromDb = await this.loadJobsFromDb(safeLimit);
        if (fromDb.length > 0) {
            for (const job of fromDb) {
                this.jobs.set(job.id, job);
            }
            return fromDb;
        }
        return Array.from(this.jobs.values())
            .sort((a, b) => (b.queuedAt || '').localeCompare(a.queuedAt || ''))
            .slice(0, safeLimit);
    }

    private async runWorker() {
        if (this.isWorkerRunning) return;
        this.isWorkerRunning = true;
        try {
            while (this.queue.length > 0) {
                const jobId = this.queue.shift();
                if (!jobId) continue;
                const job = this.jobs.get(jobId);
                if (!job) continue;
                job.status = 'RUNNING';
                job.startedAt = new Date().toISOString();
                await this.updatePersistentJob(job);
                try {
                    const result = await this.dispatchCampaign(job.campaignId);
                    job.successCount = result.successCount;
                    job.failCount = result.failCount;
                    job.status = result.failCount > 0 ? 'FAILED' : 'DONE';
                    if (result.lastError) {
                        job.lastError = result.lastError;
                    }
                } catch (error: any) {
                    job.status = 'FAILED';
                    job.lastError = error?.message?.toString() ?? 'Dispatch failed';
                } finally {
                    job.finishedAt = new Date().toISOString();
                    await this.updatePersistentJob(job);
                    await this.evaluateRetrySpikeAndPublish();
                    this.cleanupJobs();
                }
            }
        } finally {
            this.isWorkerRunning = false;
        }
    }

    private async dispatchCampaign(campaignId: string): Promise<{ successCount: number; failCount: number; lastError?: string }> {
        const campaign = await (this.prisma as any).notificationCampaign.findUnique({
            where: { id: campaignId },
        });
        if (!campaign) {
            throw new Error('Campaign not found');
        }

        const users = await this.prisma.user.findMany({
            where: {
                ...(campaign.cityId ? { cityId: campaign.cityId } : {}),
                pushToken: { not: null },
            },
            select: {
                id: true,
                pushToken: true,
            },
            take: 5000,
        });

        const tokens = users
            .map((u) => (u.pushToken ?? '').trim())
            .filter((token) => token.length > 0);

        let successCount = 0;
        let failCount = 0;
        let lastError: string | undefined;
        for (const token of tokens) {
            const ok = await this.sendPushWithRetry(token, campaign.title, campaign.body);
            if (ok) {
                successCount += 1;
            } else {
                failCount += 1;
                lastError = 'One or more tokens failed';
            }
        }

        await (this.prisma as any).notificationCampaign.update({
            where: { id: campaignId },
            data: {
                isSent: successCount > 0 && failCount === 0,
                sentAt: new Date(),
            },
        });

        return { successCount, failCount, lastError };
    }

    private async sendPushWithRetry(token: string, title: string, body: string): Promise<boolean> {
        const serverKey = (process.env.FCM_SERVER_KEY || '').trim();
        if (!serverKey) {
            return false;
        }
        for (let attempt = 1; attempt <= 3; attempt++) {
            try {
                const response = await fetch('https://fcm.googleapis.com/fcm/send', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        Authorization: `key=${serverKey}`,
                    },
                    body: JSON.stringify({
                        to: token,
                        notification: { title, body },
                        priority: 'high',
                    }),
                });
                if (response.ok) return true;
            } catch (_) {
                // retry
            }
            await new Promise((resolve) => setTimeout(resolve, attempt * 400));
        }
        return false;
    }

    private cleanupJobs() {
        const now = Date.now();
        for (const [id, job] of this.jobs.entries()) {
            const finishedAt = job.finishedAt ? new Date(job.finishedAt).getTime() : 0;
            if (finishedAt > 0 && now - finishedAt > this.retentionMs) {
                this.jobs.delete(id);
            }
        }
        if (this.jobs.size <= this.maxJobs) return;
        const sorted = Array.from(this.jobs.values()).sort((a, b) => (a.queuedAt || '').localeCompare(b.queuedAt || ''));
        const dropCount = Math.max(0, this.jobs.size - this.maxJobs);
        for (let i = 0; i < dropCount; i++) {
            this.jobs.delete(sorted[i].id);
        }
        this.cleanupPersistentJobs().catch(() => null);
    }

    private async createPersistentJob(job: DispatchJob) {
        try {
            await (this.prisma as any).notificationDispatchJob.create({
                data: {
                    id: job.id,
                    campaignId: job.campaignId,
                    status: job.status,
                    retryCount: job.retryCount ?? 0,
                    requeuedFromJobId: job.requeuedFromJobId ?? null,
                    queuedAt: new Date(job.queuedAt),
                    startedAt: job.startedAt ? new Date(job.startedAt) : null,
                    finishedAt: job.finishedAt ? new Date(job.finishedAt) : null,
                    successCount: job.successCount,
                    failCount: job.failCount,
                    lastError: job.lastError ?? null,
                },
            });
        } catch (_) {
            // Table may be unavailable before migration; keep in-memory flow.
        }
    }

    private async updatePersistentJob(job: DispatchJob) {
        try {
            await (this.prisma as any).notificationDispatchJob.update({
                where: { id: job.id },
                data: {
                    status: job.status,
                    startedAt: job.startedAt ? new Date(job.startedAt) : null,
                    finishedAt: job.finishedAt ? new Date(job.finishedAt) : null,
                    successCount: job.successCount,
                    failCount: job.failCount,
                    lastError: job.lastError ?? null,
                },
            });
        } catch (_) {
            // Table may be unavailable before migration; keep in-memory flow.
        }
    }

    private async loadJobFromDb(jobId: string): Promise<DispatchJob | null> {
        try {
            const row = await (this.prisma as any).notificationDispatchJob.findUnique({
                where: { id: jobId },
            });
            if (!row) return null;
            return this.mapDbJob(row);
        } catch (_) {
            return null;
        }
    }

    private async loadJobsFromDb(limit: number): Promise<DispatchJob[]> {
        try {
            const rows = await (this.prisma as any).notificationDispatchJob.findMany({
                orderBy: { queuedAt: 'desc' },
                take: limit,
            });
            return (rows as any[]).map((row) => this.mapDbJob(row));
        } catch (_) {
            return [];
        }
    }

    private mapDbJob(row: any): DispatchJob {
        return {
            id: row.id,
            campaignId: row.campaignId,
            status: row.status as DispatchJobStatus,
            retryCount: Number(row.retryCount ?? 0),
            requeuedFromJobId: row.requeuedFromJobId ?? undefined,
            queuedAt: new Date(row.queuedAt).toISOString(),
            startedAt: row.startedAt ? new Date(row.startedAt).toISOString() : undefined,
            finishedAt: row.finishedAt ? new Date(row.finishedAt).toISOString() : undefined,
            successCount: Number(row.successCount ?? 0),
            failCount: Number(row.failCount ?? 0),
            lastError: row.lastError ?? undefined,
        };
    }

    private async cleanupPersistentJobs() {
        try {
            const cutoff = new Date(Date.now() - this.retentionMs);
            await (this.prisma as any).notificationDispatchJob.deleteMany({
                where: {
                    finishedAt: { lt: cutoff },
                },
            });
        } catch (_) {
            // best-effort cleanup only
        }
    }

    private async evaluateRetrySpikeAndPublish() {
        const nowMs = Date.now();
        if (nowMs - this.lastRetrySpikeAtMs < this.retrySpikeCooldownMs) {
            return;
        }

        const recentWindowMs = 30 * 60 * 1000;
        const sinceMs = nowMs - recentWindowMs;
        const recent = (await this.listJobs(500)).filter((job) => {
            const t = new Date(job.queuedAt).getTime();
            return Number.isFinite(t) && t >= sinceMs;
        });
        const completed = recent.filter((job) => job.status === 'DONE' || job.status === 'FAILED');
        if (completed.length < 10) return;

        const failed = completed.filter((job) => job.status === 'FAILED').length;
        const retries = completed.filter((job) => (job.retryCount ?? 0) > 0).length;
        const failedRate = failed / completed.length;
        const retryRate = retries / completed.length;

        const isSpike = failedRate >= 0.35 || (failed >= 5 && retryRate >= 0.4);
        if (!isSpike) return;

        this.lastRetrySpikeAtMs = nowMs;
        this.realtimeService.publish({
            type: 'dispatch.retry.spike',
            entity: 'system',
            at: new Date(nowMs).toISOString(),
            payload: {
                windowMinutes: 30,
                completed: completed.length,
                failed,
                retries,
                failedRate: Number(failedRate.toFixed(4)),
                retryRate: Number(retryRate.toFixed(4)),
            },
        });
    }
}
