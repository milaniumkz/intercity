-- AlterTable
ALTER TABLE "Wallet" ADD COLUMN     "lockedBonus" DOUBLE PRECISION NOT NULL DEFAULT 0,
ADD COLUMN     "lockedBonusRub" DOUBLE PRECISION NOT NULL DEFAULT 0;

-- AlterTable
ALTER TABLE "DriverOnline" ADD COLUMN     "lastAccuracy" DOUBLE PRECISION;

-- CreateTable
CREATE TABLE "DriverDailyParticipation" (
    "id" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "day" TEXT NOT NULL,
    "currency" TEXT NOT NULL,
    "targetOrders" INTEGER NOT NULL,
    "rewardAmount" DOUBLE PRECISION NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DriverDailyParticipation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TripVerification" (
    "id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "tripId" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "driverUserId" TEXT NOT NULL,
    "passengerId" TEXT NOT NULL,
    "currency" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "fromAddress" TEXT NOT NULL,
    "toAddress" TEXT NOT NULL,
    "expectedDistanceKm" DOUBLE PRECISION NOT NULL,
    "fromLat" DOUBLE PRECISION,
    "fromLng" DOUBLE PRECISION,
    "toLat" DOUBLE PRECISION,
    "toLng" DOUBLE PRECISION,
    "startedAt" TIMESTAMP(3),
    "completedAt" TIMESTAMP(3),
    "points" JSONB NOT NULL DEFAULT '[]',
    "reasons" JSONB NOT NULL DEFAULT '[]',
    "summary" JSONB,
    "resolutionNote" TEXT,
    "reviewedBy" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TripVerification_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "DriverDailyParticipation_driverId_day_currency_key" ON "DriverDailyParticipation"("driverId", "day", "currency");

-- CreateIndex
CREATE INDEX "TripVerification_driverId_completedAt_status_idx" ON "TripVerification"("driverId", "completedAt", "status");

-- CreateIndex
CREATE INDEX "TripVerification_status_completedAt_idx" ON "TripVerification"("status", "completedAt");

-- CreateIndex
CREATE UNIQUE INDEX "TripVerification_kind_tripId_key" ON "TripVerification"("kind", "tripId");


-- Preserve promises for drivers who already started today's active promotion.
WITH trips AS (
 SELECT o."driverId", o.currency FROM "Order" o
 WHERE o.status='COMPLETED' AND o."completedAt" >= date_trunc('day',now() AT TIME ZONE 'Asia/Almaty') AT TIME ZONE 'Asia/Almaty'
 UNION
 SELECT d.id,r.currency FROM "IntercityRequest" r JOIN "DriverProfile" d ON d."userId"=r."selectedDriverId"
 WHERE r.status='COMPLETED' AND r."completedAt" >= date_trunc('day',now() AT TIME ZONE 'Asia/Almaty') AT TIME ZONE 'Asia/Almaty'
)
INSERT INTO "DriverDailyParticipation" (id,"driverId",day,currency,"targetOrders","rewardAmount","createdAt")
SELECT md5(t."driverId"||t.currency||now()::text),t."driverId",to_char(now() AT TIME ZONE 'Asia/Almaty','YYYY-MM-DD'),t.currency,(s.value::jsonb->>'targetOrders')::integer,(s.value::jsonb->>'rewardAmount')::double precision,now()
FROM trips t JOIN "AppSettings" s ON s.key='driverDailyBonus'||t.currency
WHERE t."driverId" IS NOT NULL AND (s.value::jsonb->>'enabled')::boolean=true ON CONFLICT DO NOTHING;

-- Replay promotional credits; main-balance debits consume bonuses first.
WITH RECURSIVE ledger AS (
 SELECT "walletId",currency,amount,direction,type,
 row_number() OVER (PARTITION BY "walletId",currency ORDER BY "createdAt", CASE WHEN type='DRIVER_DAILY_BONUS' THEN 0 ELSE 1 END,id) AS n
 FROM "WalletTransaction" WHERE "balanceSource"='MONEY'
), replay AS (
 SELECT "walletId",currency,n,CASE WHEN type='DRIVER_DAILY_BONUS' AND direction='CREDIT' THEN amount ELSE 0::double precision END AS locked FROM ledger WHERE n=1
 UNION ALL
 SELECT l."walletId",l.currency,l.n,GREATEST(0::double precision,r.locked+CASE WHEN l.type='DRIVER_DAILY_BONUS' AND l.direction='CREDIT' THEN l.amount WHEN l.direction='DEBIT' THEN -l.amount ELSE 0 END)
 FROM replay r JOIN ledger l ON l."walletId"=r."walletId" AND l.currency=r.currency AND l.n=r.n+1
), latest AS (SELECT DISTINCT ON ("walletId",currency) "walletId",currency,locked FROM replay ORDER BY "walletId",currency,n DESC)
UPDATE "Wallet" w SET "lockedBonus"=LEAST(GREATEST(0,w.money),COALESCE((SELECT locked FROM latest WHERE "walletId"=w.id AND currency='KZT'),0)),
"lockedBonusRub"=LEAST(GREATEST(0,w."moneyRub"),COALESCE((SELECT locked FROM latest WHERE "walletId"=w.id AND currency='RUB'),0));
