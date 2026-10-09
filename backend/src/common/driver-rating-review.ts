import { BadRequestException } from '@nestjs/common';

export function ratingReviewHint(reason: string) {
    if (/приложен|промокод|цена тарифа|ошибка карт|поиск адрес/i.test(reason)) {
        return { recommendation: 'CHECK_PLATFORM_ISSUE', text: 'Возможна проблема сервиса. Проверьте связь причины с действиями водителя; не учитывайте оценку без подтверждения.' };
    }
    return { recommendation: 'CHECK_TRIP_FACTS', text: 'Проверьте пояснение пассажира, маршрут, статусы и время поездки. Текст сам по себе не подтверждает нарушение.' };
}
export async function reviseDriverRating(tx: any, driverId: string, oldRating: number | null, newRating: number | null) {
    await tx.$executeRaw`SELECT id FROM "DriverProfile" WHERE id = ${driverId} FOR UPDATE`;
    const current = await tx.driverRating.findUnique({where:{driverId}});
    const count = Math.max(0, (current?.ratingCount ?? 0) - (oldRating == null ? 0 : 1) + (newRating == null ? 0 : 1));
    const sum = (current?.ratingAvg ?? 0) * (current?.ratingCount ?? 0) - (oldRating ?? 0) + (newRating ?? 0);
    const ratingAvg = count ? Math.max(1, Math.min(5, sum / count)) : 5;
    await tx.driverRating.upsert({where:{driverId},create:{driverId,ratingAvg,ratingCount:count},update:{ratingAvg,ratingCount:count}});
}
export function validateReviewDecision(data: Record<string,unknown>) {
    const decision = String(data.ratingDecision ?? '').toUpperCase();
    if (!['APPROVE','CHANGE','REJECT'].includes(decision)) throw new BadRequestException('Выберите решение по оценке');
    const note = String(data.resolutionNote ?? '').trim();
    if (note.length < 5 || note.length > 2000) throw new BadRequestException('Укажите пояснение решения от 5 до 2000 символов');
    const rating = Number(data.rating);
    if (decision === 'CHANGE' && (!Number.isInteger(rating) || rating < 1 || rating > 5)) throw new BadRequestException('Оценка должна быть целым числом от 1 до 5');
    return {decision,note,rating};
}
