CREATE TABLE IF NOT EXISTS "DriverIntercityRoute" (
    "id" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "fromCity" TEXT NOT NULL,
    "toCity" TEXT NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DriverIntercityRoute_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "DriverIntercityRoute_driverId_fromCity_toCity_key"
ON "DriverIntercityRoute"("driverId", "fromCity", "toCity");

CREATE INDEX IF NOT EXISTS "DriverIntercityRoute_driverId_isActive_idx"
ON "DriverIntercityRoute"("driverId", "isActive");

CREATE INDEX IF NOT EXISTS "DriverIntercityRoute_fromCity_toCity_isActive_idx"
ON "DriverIntercityRoute"("fromCity", "toCity", "isActive");

ALTER TABLE "DriverIntercityRoute"
ADD CONSTRAINT "DriverIntercityRoute_driverId_fkey"
FOREIGN KEY ("driverId") REFERENCES "DriverProfile"("id")
ON DELETE CASCADE ON UPDATE CASCADE;
