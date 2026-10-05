ALTER TABLE "TopupRequest" ADD COLUMN IF NOT EXISTS "provider" TEXT;
ALTER TABLE "TopupRequest" ADD COLUMN IF NOT EXISTS "externalOrderId" TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS "TopupRequest_externalOrderId_key" ON "TopupRequest"("externalOrderId");
