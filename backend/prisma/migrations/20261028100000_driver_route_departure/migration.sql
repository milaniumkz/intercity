ALTER TABLE "DriverIntercityRoute" ADD COLUMN "departureAt" TIMESTAMP(3);
ALTER TABLE "DriverIntercityRoute" ADD COLUMN "departureOffsetMinutes" INTEGER NOT NULL DEFAULT 300;
CREATE INDEX "DriverIntercityRoute_driverId_isActive_departureAt_idx" ON "DriverIntercityRoute"("driverId", "isActive", "departureAt");
