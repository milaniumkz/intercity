ALTER TABLE "Order" ADD COLUMN "dispatchDriverId" TEXT,
ADD COLUMN "dispatchExpiresAt" TIMESTAMP(3),
ADD COLUMN "dispatchTriedDriverIds" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
ADD COLUMN "dispatchRetryAt" TIMESTAMP(3);
CREATE UNIQUE INDEX "Order_one_pending_offer_per_driver" ON "Order" ("dispatchDriverId")
WHERE "dispatchDriverId" IS NOT NULL AND status = 'SEARCHING_DRIVER';
CREATE INDEX "Order_dispatch_queue" ON "Order" (status, "dispatchRetryAt", "createdAt");
