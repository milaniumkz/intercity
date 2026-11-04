import { BadRequestException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';

const DAY = 86400000, OFFSET = 5 * 3600000;
export function dashboardPeriod(period = '24h', from?: string, to?: string, now = new Date()) {
    const today = new Date(now.getTime() + OFFSET).toISOString().slice(0, 10);
    const midnight = new Date(`${today}T00:00:00+05:00`);
    let start: Date, end = now;
    if (period === 'custom') {
        const parse = (value?: string) => {
            if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new BadRequestException('Укажите даты периода в формате ГГГГ-ММ-ДД');
            const date = new Date(`${value}T00:00:00+05:00`);
            if (!Number.isFinite(date.getTime()) || new Date(date.getTime() + OFFSET).toISOString().slice(0, 10) !== value) throw new BadRequestException('Некорректная дата периода');
            return date;
        };
        start = parse(from); end = new Date(parse(to).getTime() + DAY);
    } else if (period === 'today') start = midnight;
    else if (period === 'week') start = new Date(midnight.getTime() - 6 * DAY);
    else if (period === 'month') start = new Date(midnight.getTime() - 29 * DAY);
    else if (period === '24h') start = new Date(now.getTime() - DAY);
    else throw new BadRequestException('Неизвестный период статистики');
    if (start >= end || end.getTime() - start.getTime() > 366 * DAY) throw new BadRequestException('Выберите период от одного дня до 366 дней');
    return { period, from: start.toISOString(), to: end.toISOString(), timezone: 'UTC+5' };
}

export async function dashboardStatistics(db: PrismaService, period?: string, from?: string, to?: string) {
    const range = dashboardPeriod(period, from, to), start = new Date(range.from), end = new Date(range.to);
    // One database snapshot. Both order stores are independent business requests;
    // prices for marketplace trips come from the accepted offer, never an offer sum.
    const rows = await db.$queryRaw<Array<{ data: any }>>(Prisma.sql`
    WITH users AS (
      SELECT u.*, (u.role::text='DRIVER' OR EXISTS(SELECT 1 FROM "DriverProfile" d WHERE d."userId"=u.id)) AS driver
      FROM "User" u WHERE u.role::text <> 'ADMIN' AND u.phone NOT LIKE 'erased:%'
    ), all_trips AS NOT MATERIALIZED (
      SELECT o.id, 'ORDER' AS source, CASE WHEN o.mode='CARGO' THEN 'CARGO' WHEN o.mode='INTERCITY' THEN 'INTERCITY' WHEN o.mode='DELIVERY' THEN CASE WHEN o."requestType" IN ('DELIVERY_CITY','DELIVERY_INTERCITY','DELIVERY_RF') THEN o."requestType" ELSE 'DELIVERY_CITY' END WHEN o."requestType"='CITY_AUCTION' THEN 'CITY_AUCTION' ELSE 'CITY_FIXED' END AS mode,
        o.status::text, o."createdAt", o."completedAt", o."passengerId", o."fromAddress" AS origin, o."toAddress" AS destination,
        o.price, o.currency FROM "Order" o
      UNION ALL
      SELECT r.id,'MARKET',r."requestType",r.status,r."createdAt",r."completedAt",r."passengerId",r."fromCity",r."toCity",
        COALESCE(f.price,r.price),r.currency FROM "IntercityRequest" r LEFT JOIN "IntercityOffer" f ON f.id=r."selectedOfferId"

    ), trips AS (SELECT * FROM all_trips WHERE "createdAt">=${start} AND "createdAt"<${end}),
    completed_trips AS (SELECT * FROM all_trips WHERE status='COMPLETED' AND "completedAt">=${start} AND "completedAt"<${end}),
    grouped AS (
      SELECT mode, count(*)::int AS total,
       count(*) FILTER(WHERE status='COMPLETED')::int AS completed,
       count(*) FILTER(WHERE status='CANCELLED')::int AS cancelled,
       count(*) FILTER(WHERE status IN ('EXPIRED','REJECTED'))::int AS expired,
       count(*) FILTER(WHERE status NOT IN ('COMPLETED','CANCELLED','EXPIRED','REJECTED'))::int AS active
      FROM trips GROUP BY mode
    ), days AS (
      SELECT generate_series(((${start}::timestamp + interval '5 hours')::date)::timestamp,
        ((${end}::timestamp - interval '1 millisecond' + interval '5 hours')::date)::timestamp,interval '1 day') AS day
    )
    SELECT json_build_object(
      'users',(SELECT json_build_object('total',count(*)::int,'drivers',count(*) FILTER(WHERE driver)::int,
       'passengers',count(*) FILTER(WHERE NOT driver)::int,
       'newTotal',count(*) FILTER(WHERE "createdAt">=${start} AND "createdAt"<${end})::int,
       'newDrivers',count(*) FILTER(WHERE driver AND "createdAt">=${start} AND "createdAt"<${end})::int,
       'newPassengers',count(*) FILTER(WHERE NOT driver AND "createdAt">=${start} AND "createdAt"<${end})::int) FROM users),
      'activeOrdersNow',((SELECT count(*)::int FROM "Order" WHERE status NOT IN ('COMPLETED','CANCELLED')) + (SELECT count(*)::int FROM "IntercityRequest" WHERE status NOT IN ('COMPLETED','CANCELLED','EXPIRED','REJECTED'))),
      'drivers',(SELECT json_build_object('newProfiles',count(*) FILTER(WHERE d."createdAt">=${start} AND d."createdAt"<${end})::int,
       'approved',count(*) FILTER(WHERE d.status IN ('APPROVED','ACTIVE'))::int,'pending',count(*) FILTER(WHERE d.status='PENDING')::int,
       'online',(SELECT count(*)::int FROM "DriverOnline" WHERE "isOnline")) FROM "DriverProfile" d),
      'completedInPeriod',(SELECT count(*)::int FROM completed_trips),
      'missingCompletionDates',(SELECT count(*)::int FROM trips WHERE status='COMPLETED' AND "completedAt" IS NULL),
      'orders',(SELECT json_build_object('total',count(*)::int,'completed',count(*) FILTER(WHERE status='COMPLETED')::int,
       'cancelled',count(*) FILTER(WHERE status='CANCELLED')::int,
       'expired',count(*) FILTER(WHERE status IN ('EXPIRED','REJECTED'))::int,
       'active',count(*) FILTER(WHERE status NOT IN ('COMPLETED','CANCELLED','EXPIRED','REJECTED'))::int,
       'uniquePassengers',count(DISTINCT "passengerId")::int) FROM trips),
      'byMode',COALESCE((SELECT json_agg(grouped ORDER BY mode) FROM grouped),'[]'::json),
      'finance',COALESCE((SELECT json_agg(x) FROM (SELECT currency,sum(price) AS turnover,count(*)::int AS completed
         FROM completed_trips GROUP BY currency ORDER BY currency) x),'[]'::json),
      'commissions',COALESCE((SELECT json_agg(x) FROM (SELECT currency,sum(CASE WHEN direction='CREDIT' THEN -amount ELSE amount END) AS amount
        FROM "WalletTransaction" WHERE "createdAt">=${start} AND "createdAt"<${end}
        AND type IN ('ORDER_COMMISSION_DEBIT','DEBIT_INTERCITY_ACCEPTED_REQUEST','DEBIT_INTERCITY_COMPLETED_REQUEST')
        GROUP BY currency ORDER BY currency) x),'[]'::json),
      'daily',COALESCE((SELECT json_agg(json_build_object('date',to_char(day,'YYYY-MM-DD'),
        'users',(SELECT count(*)::int FROM users WHERE "createdAt">=${start} AND "createdAt"<${end} AND ("createdAt"+interval '5 hours')::date=day::date),
        'completedInPeriod',(SELECT count(*)::int FROM completed_trips),
      'missingCompletionDates',(SELECT count(*)::int FROM trips WHERE status='COMPLETED' AND "completedAt" IS NULL),
      'orders',(SELECT count(*)::int FROM trips WHERE ("createdAt"+interval '5 hours')::date=day::date)) ORDER BY day) FROM days),'[]'::json),
      'recentOrders',COALESCE((SELECT json_agg(x) FROM (SELECT id,source,mode,status,"createdAt",origin,destination,price,currency FROM trips ORDER BY "createdAt" DESC,id DESC LIMIT 10) x),'[]'::json),
      'recentUsers',COALESCE((SELECT json_agg(x) FROM (SELECT id,name,phone,driver,"createdAt" FROM users WHERE "createdAt">=${start} AND "createdAt"<${end} ORDER BY "createdAt" DESC,id DESC LIMIT 10) x),'[]'::json)
    ) AS data`);
    return { range, ...rows[0].data };
}
