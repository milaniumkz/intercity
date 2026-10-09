import { creditRideReferrals } from './referral-bonus';
import { creditDriverDailyBonus } from './driver-daily-bonus';

export type TripPoint = { lat: number; lng: number; accuracy: number; at: string };
export function distanceMeters(a: { lat: number; lng: number }, b: { lat: number; lng: number }) {
    const rad = Math.PI / 180;
    const x = Math.sin((b.lat-a.lat)*rad/2)**2 + Math.cos(a.lat*rad)*Math.cos(b.lat*rad)*Math.sin((b.lng-a.lng)*rad/2)**2;
    return 6371000 * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(Math.max(0, 1-x)));
}
export function evaluateTrip(trip: any, completedAt = new Date()) {
    const points: TripPoint[] = Array.isArray(trip.points) ? trip.points : [];
    const durationSec = trip.startedAt ? (completedAt.getTime()-new Date(trip.startedAt).getTime())/1000 : 0;
    const expectedMeters = Math.max(0, trip.expectedDistanceKm*1000);
    const reasons: string[] = [];
    let travelledMeters = 0;
    let anchor = points[0];
    for (let i=1;i<points.length;i++) {
        const distance = distanceMeters(points[i-1], points[i]);
        const seconds = (Date.parse(points[i].at)-Date.parse(points[i-1].at))/1000;
        if (seconds > 0 && distance/seconds > 70) reasons.push('Скачок GPS или неправдоподобная скорость');
        const movement = distanceMeters(anchor, points[i]);
        if (movement > Math.max(10, points[i].accuracy*1.5, anchor.accuracy*1.5)) { travelledMeters += movement; anchor = points[i]; }
    }
    if (trip.passengerId === trip.driverUserId) reasons.push('Пассажир и водитель — один аккаунт');
    if (points.length < 2 || !trip.startedAt) reasons.push('Недостаточно достоверных GPS-данных');
    if (durationSec < Math.max(20, expectedMeters/55)) reasons.push('Недостаточная длительность поездки');
    const first = points[0], last = points[points.length-1];
    if (first && trip.fromLat != null && trip.fromLng != null && distanceMeters(first, {lat:trip.fromLat,lng:trip.fromLng}) > Math.max(500, first.accuracy*3)) reasons.push('Начало поездки далеко от места посадки');
    if (last && trip.toLat != null && trip.toLng != null && distanceMeters(last, {lat:trip.toLat,lng:trip.toLng}) > Math.max(150,last.accuracy*3)) reasons.push('Завершение далеко от пункта назначения');
    if (trip.fromLat == null || trip.toLat == null) reasons.push('Не заданы координаты маршрута');
    if (travelledMeters < Math.max(30,expectedMeters*.3)) reasons.push('Недостаточно подтверждённого движения');
    if (last && completedAt.getTime()-Date.parse(last.at)>60000) reasons.push('Местоположение при завершении устарело');
    return { status: reasons.length ? 'REVIEW' : 'VERIFIED', reasons: [...new Set(reasons)], summary: { durationSec, expectedMeters, travelledMeters, samples:points.length } };
}
export async function startTripVerification(tx: any, kind: string, trip: any, driverId: string, driverUserId: string) {
    const online = await tx.driverOnline.findUnique({where:{driverId}});
    const now = new Date();
    const points = online?.lastAccuracy != null && online.lastAccuracy <= 100 && online.lastLocationAt && now.getTime()-new Date(online.lastLocationAt).getTime() <= 30000 && online.lastLat != null && online.lastLng != null
        ? [{lat:online.lastLat,lng:online.lastLng,accuracy:online.lastAccuracy,at:now.toISOString()}] : [];
    const expected = trip.distanceKm ?? (trip.fromLat != null && trip.toLat != null ? distanceMeters({lat:trip.fromLat,lng:trip.fromLng},{lat:trip.toLat,lng:trip.toLng})/1000 : 0);
    await tx.tripVerification.upsert({where:{id:`${kind}:${trip.id}`},update:{},create:{id:`${kind}:${trip.id}`,kind,tripId:trip.id,driverId,driverUserId,passengerId:trip.passengerId,currency:trip.currency,
        fromAddress:trip.fromAddress ?? trip.fromAddressLabel ?? trip.fromCity ?? '',toAddress:trip.toAddress ?? trip.toAddressLabel ?? trip.toCity ?? '',expectedDistanceKm:expected,
        fromLat:trip.fromLat,fromLng:trip.fromLng,toLat:trip.toLat,toLng:trip.toLng,startedAt:now,points}});
}
export async function appendTripPoint(tx: any, driverId: string, point: TripPoint) {
    const active = await tx.tripVerification.findMany({where:{driverId,status:'PENDING',completedAt:null},select:{id:true}});
    for (const item of active) {
        await tx.$executeRaw`SELECT id FROM "TripVerification" WHERE id = ${item.id} FOR UPDATE`;
        const trip = await tx.tripVerification.findUnique({where:{id:item.id}});
        if (!trip || trip.status !== 'PENDING' || trip.completedAt) continue;
        const points = Array.isArray(trip.points) ? trip.points : [];
        if (points.length && Date.parse(point.at)-Date.parse(points[points.length-1].at)<5000) continue;
        // Retain the start and recent trajectory without unbounded storage.
        if (points.length >= 2000) points.splice(1,1);
        points.push(point);
        await tx.tripVerification.update({where:{id:item.id},data:{points}});
    }
}
export async function finishTripVerification(tx: any, kind: string, trip: any, driverId: string, driverUserId: string, completedAt: Date) {
    const id = `${kind}:${trip.id}`;
    await tx.$executeRaw`SELECT id FROM "TripVerification" WHERE id = ${id} FOR UPDATE`;
    let record = await tx.tripVerification.findUnique({where:{id}});
    // Trips already in progress when the feature was installed require review as well.
    if (!record) {
        await startTripVerification(tx,kind,trip,driverId,driverUserId);
        record = await tx.tripVerification.findUnique({where:{id}});
        record.startedAt = null;
    }
    if (record.completedAt) return record.status;
    const result = evaluateTrip(record,completedAt);
    await tx.tripVerification.update({where:{id},data:{completedAt,...result}});
    return result.status;
}
export async function releaseVerifiedTripRewards(tx: any, record: any) {
    const trip = record.kind === 'CITY' ? await tx.order.findUnique({where:{id:record.tripId}}) : await tx.intercityRequest.findUnique({where:{id:record.tripId}});
    if (!trip || trip.status !== 'COMPLETED') return;
    let commissionAmount = trip.commissionAmount;
    if (record.kind === 'INTERCITY') {
        const fee = await tx.walletTransaction.findFirst({where:{intercityRequestId:trip.id,type:'DEBIT_INTERCITY_COMPLETED_REQUEST'}});
        commissionAmount = fee?.amount ?? 0;
    }
    await creditRideReferrals(tx,{id:trip.id,currency:trip.currency,commissionAmount:commissionAmount ?? 0,passengerId:record.passengerId,driverUserId:record.driverUserId,intercity:record.kind==='INTERCITY'});
    await creditDriverDailyBonus(tx,record.driverId,record.driverUserId,record.currency,record.completedAt);
}
