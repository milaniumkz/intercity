export const DRIVER_ACTIVITY_RULES = {
    initialScore: 100, rejectPenalty: 3, blockHours: 12, restoredScore: 30,
    greenFrom: 70, yellowFrom: 30,
};

export function driverPriority(driver: any, now = new Date()) {
    const start = driver.serviceStats?.serviceStartAt ? new Date(driver.serviceStats.serviceStartAt).getTime() : NaN;
    const days = Number.isFinite(start) ? Math.max(0, Math.floor((now.getTime() - start) / 86400000)) : 0;
    const items = [
        { key: 'checkers', label: 'Шашка', points: driver.priorityFlags?.hasCheckers ? 5 : 0,
            rule: 'Подтверждённая шашка на автомобиле: +5 баллов.' },
        { key: 'branding', label: 'Обклейка', points: driver.priorityFlags?.hasBranding ? 10 : 0,
            rule: 'Подтверждённая фирменная обклейка: +10 баллов.' },
        { key: 'rating', label: 'Рейтинг выше 4,9', points: driver.rating?.ratingAvg > 4.9 ? 10 : 0,
            rule: 'Рейтинг строго выше 4,9: +10 баллов. При снижении до 4,9 или ниже этот бонус перестаёт действовать.' },
        { key: 'service', label: 'Стаж в сервисе', points: days * 2,
            rule: 'Каждые полные сутки с даты подключения: +2 балла. Дата подключения устанавливается при одобрении профиля.' },
        { key: 'fuel', label: 'Партнёрская заправка',
            points: driver.fuelBonus?.bonusActiveUntil && new Date(driver.fuelBonus.bonusActiveUntil) > now ? 2 : 0,
            rule: 'Действующий бонус партнёрской заправки: +2 балла. После истечения срока этот бонус перестаёт действовать.' },
    ];
    return { total: items.reduce((sum, item) => sum + item.points, 0), items };
}

export function driverPerformance(driver: any, now = new Date()) {
    const stats = driver.serviceStats;
    let score = stats?.activityScore ?? DRIVER_ACTIVITY_RULES.initialScore;
    let blockedUntil = stats?.activityBlockedUntil ? new Date(stats.activityBlockedUntil) : null;
    if (score <= 0 && blockedUntil && blockedUntil <= now) {
        score = DRIVER_ACTIVITY_RULES.restoredScore;
        blockedUntil = null;
    }
    const blocked = score <= 0 || Boolean(blockedUntil && blockedUntil > now);
    const level = blocked ? 'blocked' : score >= DRIVER_ACTIVITY_RULES.greenFrom ? 'green' :
        score >= DRIVER_ACTIVITY_RULES.yellowFrom ? 'yellow' : 'red';
    return {
        activity: { score, blocked, blockedUntil, level, rules: DRIVER_ACTIVITY_RULES },
        rating: { average: driver.rating?.ratingAvg ?? null, count: driver.rating?.ratingCount ?? 0 },
        priority: driverPriority(driver, now),
    };
}
