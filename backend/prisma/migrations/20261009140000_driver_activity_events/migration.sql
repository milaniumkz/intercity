CREATE TABLE "DriverActivityEvent" (
 "id" TEXT NOT NULL, "key" TEXT NOT NULL, "driverId" TEXT NOT NULL,
 "delta" INTEGER NOT NULL, "score" INTEGER NOT NULL, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT "DriverActivityEvent_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "DriverActivityEvent_key_key" ON "DriverActivityEvent"("key");
CREATE INDEX "DriverActivityEvent_driverId_createdAt_idx" ON "DriverActivityEvent"("driverId", "createdAt");
ALTER TABLE "DriverActivityEvent" ADD CONSTRAINT "DriverActivityEvent_driverId_fkey" FOREIGN KEY ("driverId") REFERENCES "DriverProfile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "IntercityRequest" ADD COLUMN "completedAt" TIMESTAMP(3);
