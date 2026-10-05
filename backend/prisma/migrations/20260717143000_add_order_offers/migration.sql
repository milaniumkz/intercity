ALTER TABLE "Order" ADD COLUMN IF NOT EXISTS "selectedOfferId" TEXT;

CREATE TABLE IF NOT EXISTS "OrderOffer" (
    "id" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "price" DOUBLE PRECISION NOT NULL,
    "comment" TEXT,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "OrderOffer_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "OrderOffer_orderId_driverId_key" ON "OrderOffer"("orderId", "driverId");
CREATE INDEX IF NOT EXISTS "OrderOffer_orderId_status_createdAt_idx" ON "OrderOffer"("orderId", "status", "createdAt");
CREATE INDEX IF NOT EXISTS "OrderOffer_driverId_status_createdAt_idx" ON "OrderOffer"("driverId", "status", "createdAt");

ALTER TABLE "OrderOffer"
    ADD CONSTRAINT "OrderOffer_orderId_fkey"
    FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "OrderOffer"
    ADD CONSTRAINT "OrderOffer_driverId_fkey"
    FOREIGN KEY ("driverId") REFERENCES "DriverProfile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
