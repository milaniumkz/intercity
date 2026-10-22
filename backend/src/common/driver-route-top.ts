import { BadRequestException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { driverPerformance } from './driver-performance';
export const ROUTE_TOP_POLICY_KEY = 'driverRouteTopPolicy';
export const DEFAULT_ROUTE_TOP_POLICY = { priceKzt: 1000, kztPerRub: 7, durationHours: 12, firstAccessSeconds: 30 };
export function parseRouteTopPolicy(raw?: string | null) {
    if (!raw) return { ...DEFAULT_ROUTE_TOP_POLICY };
    let value: any;
    try { value = JSON.parse(raw); } catch { throw new BadRequestException('Проверьте настройки поднятия маршрута в топ'); }
    if (![value.priceKzt,value.kztPerRub,value.durationHours,value.firstAccessSeconds].every(v => typeof v === 'number' && Number.isFinite(v)) ||
        value.priceKzt < .01 || value.priceKzt > 1000000 || value.kztPerRub <= 0 || value.kztPerRub > 100000 ||
        value.durationHours < 1 || value.durationHours > 168 || value.firstAccessSeconds < 5 || value.firstAccessSeconds > 120) {
        throw new BadRequestException('Укажите положительные цену и курс, срок 1–168 часов и первый доступ 5–120 секунд');
    }
    return { priceKzt: value.priceKzt, kztPerRub: value.kztPerRub, durationHours: value.durationHours, firstAccessSeconds: value.firstAccessSeconds };
}
export function routeTopPrice(policy: ReturnType<typeof parseRouteTopPolicy>, currency: string) {
    return new Prisma.Decimal(policy.priceKzt).div(currency === 'RUB' ? policy.kztPerRub : 1).toDecimalPlaces(2).toNumber();
}
async function activeTopDrivers(tx: any,request: any,routeIds?: string[],now=new Date()) {
    const routes=await tx.driverIntercityRoute.findMany({where:{...(routeIds?{id:{in:routeIds}}:{}),isActive:true,topUntil:{gt:now},seatsAvailable:{gte:request.seats ?? 1},
        fromCity:{equals:request.fromCity,mode:'insensitive'},toCity:{equals:request.toCity,mode:'insensitive'},driver:{status:{in:['ACTIVE','APPROVED']},acceptIntercity:true}},
        include:{driver:{include:{serviceStats:true}}}});
    return routes.filter((r:any)=>!driverPerformance(r.driver,now).activity.blocked);
}
// One durable group invitation: all eligible promoted drivers receive the same
// first-access window. A price proposal doesn't close it or claim the trip.
export async function ensureRouteTopWindow(tx: any,request: any,now=new Date()) {
    if(request.requestType!=='INTERCITY') return null;
    const key=`route-top-group:${request.fromCity.trim().toLowerCase()}→${request.toCity.trim().toLowerCase()}`;
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${key}))`;
    const existing=await tx.intercityRoutePriorityWindow.findUnique({where:{requestId:request.id}});
    if(existing) {
        if(existing.expiresAt<=now || !existing.routeIds.length) return {...existing,activeDriverIds:[]};
        const active=await activeTopDrivers(tx,request,existing.routeIds,now);
        return {...existing,activeDriverIds:active.map((r:any)=>r.driverId)};
    }
    const active=await activeTopDrivers(tx,request,undefined,now);
    const policy=parseRouteTopPolicy((await tx.appSettings.findUnique({where:{key:ROUTE_TOP_POLICY_KEY}}))?.value);
    const expiresAt=active.length ? new Date(now.getTime()+policy.firstAccessSeconds*1000) : now;
    const window=await tx.intercityRoutePriorityWindow.create({data:{requestId:request.id,routeIds:active.map((r:any)=>r.id),expiresAt}});
    return {...window,activeDriverIds:active.map((r:any)=>r.driverId)};
}
export function canSeePriorityRequest(window: any,driverProfileId: string,now=new Date()) {
    return !window || window.expiresAt<=now || !window.activeDriverIds.length || window.activeDriverIds.includes(driverProfileId);
}
