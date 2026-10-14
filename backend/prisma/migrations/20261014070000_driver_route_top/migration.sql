ALTER TABLE "DriverIntercityRoute" ADD COLUMN "topUntil" TIMESTAMP(3);
CREATE TABLE "IntercityRoutePriorityWindow" (
  "requestId" TEXT PRIMARY KEY,
  "routeIds" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "IntercityRoutePriorityWindow_requestId_fkey" FOREIGN KEY ("requestId") REFERENCES "IntercityRequest"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX "IntercityRoutePriorityWindow_expiresAt_idx" ON "IntercityRoutePriorityWindow"("expiresAt");
