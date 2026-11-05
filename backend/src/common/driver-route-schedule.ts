/** The chosen departure day is interpreted in the driver's submitted local offset. */
export function routeRequestTimeRange(route: any, now = new Date()) {
    const departure = new Date(route.departureAt ?? NaN);
    const offset = route.departureOffsetMinutes ?? 300;
    if (!Number.isFinite(departure.getTime()) || !Number.isInteger(offset) || offset < -720 || offset > 840) return null;
    const local = new Date(departure.getTime() + offset * 60000);
    const start = new Date(Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate()) - offset * 60000);
    const end=new Date(start.getTime()+86400000-1);
    if(end<now)return null;
    return {gte: start, lte: end};
}
export function routeMatchesRequestSchedule(route: any, request: any, now = new Date()) {
    const range = routeRequestTimeRange(route, now);
    const date = new Date(request.date ?? NaN);
    return !!range && Number.isFinite(date.getTime()) && date >= range.gte && date <= range.lte;
}
