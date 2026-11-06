import {driverPerformance} from './driver-performance';
import {routeMatchesRequestSchedule} from './driver-route-schedule';
import {ensureRouteTopWindow, canSeePriorityRequest} from './driver-route-top';
const city = (value: unknown) => String(value ?? '').trim().toLowerCase();
export function deliveryDriverEligible(profile: any, request: any) {
  if (!profile.acceptDelivery || !['ACTIVE','APPROVED'].includes(profile.status) || profile.userId === request.passengerId || driverPerformance(profile).activity.blocked) return false;
  if (request.requestType === 'DELIVERY_CITY') {
    const online = profile.online;
    if (!online?.isOnline) return false;
    if (request.fromLat != null && request.fromLng != null && online.lastLat != null && online.lastLng != null) {
      return Math.abs(request.fromLat-online.lastLat)<=.1 && Math.abs(request.fromLng-online.lastLng)<=.15;
    }
    return !!city(online.city?.name) && city(request.fromCity).includes(city(online.city.name));
  }
  return (profile.intercityRoutes ?? []).some((route: any) => route.isActive && route.seatsAvailable > 0 &&
    city(route.fromCity) === city(request.fromCity) && city(route.toCity) === city(request.toCity) && routeMatchesRequestSchedule(route,request));
}
export async function notifyDeliveryDrivers(prisma: any, push: any, request: any) {
  if (!request.requestType?.startsWith('DELIVERY') || !push?.sendToUser) return;
  const profiles = await prisma.driverProfile.findMany({
    where: {acceptDelivery:true,status:{in:['ACTIVE','APPROVED']},userId:{not:request.passengerId},
      ...(request.requestType==='DELIVERY_CITY' ? {online:{isOnline:true, OR:[
        ...(request.fromLat!=null && request.fromLng!=null ? [{lastLat:{gte:request.fromLat-.1,lte:request.fromLat+.1},lastLng:{gte:request.fromLng-.15,lte:request.fromLng+.15}}] : []),
        {city:{name:{equals:request.fromCity,mode:'insensitive'}}}
      ]}} : {intercityRoutes:{some:{isActive:true,fromCity:{equals:request.fromCity,mode:'insensitive'},toCity:{equals:request.toCity,mode:'insensitive'}}}})},
    include:{serviceStats:true,online:{include:{city:true}},intercityRoutes:{where:{isActive:true}}}
  });
  const window=await prisma.$transaction((tx: any)=>ensureRouteTopWindow(tx,request));
  const recipients=profiles.filter((p: any)=>deliveryDriverEligible(p,request)&&canSeePriorityRequest(window,p.id));
  // Bound concurrent Firebase calls, while keeping delivery creation independent.
  for(let index=0;index<recipients.length;index+=4) {
    await Promise.allSettled(recipients.slice(index,index+4).map((p: any)=>push.sendToUser(p.userId,{
      title:'Новая заявка на доставку',body:`${request.fromAddressLabel || request.fromManualAddress || request.fromCity} → ${request.toAddressLabel || request.toManualAddress || request.toCity}. Дата и время указаны в заявке.`,
      data:{type:'delivery_available',requestId:request.id,route:'/driver/trip-create'}
    })));
  }
}
