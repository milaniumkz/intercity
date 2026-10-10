ALTER TABLE "OrderOffer" ADD COLUMN "expiresAt" TIMESTAMP(3) NOT NULL DEFAULT (CURRENT_TIMESTAMP + INTERVAL '30 seconds');
UPDATE "OrderOffer" SET "expiresAt" = "updatedAt" + INTERVAL '30 seconds';
CREATE INDEX "OrderOffer_status_expiresAt_idx" ON "OrderOffer"("status", "expiresAt");
CREATE TABLE "OrderAuctionInvitation" (
 "id" TEXT NOT NULL, "orderId" TEXT NOT NULL, "driverId" TEXT NOT NULL,
 "status" TEXT NOT NULL DEFAULT 'PENDING', "expiresAt" TIMESTAMP(3) NOT NULL,
 "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT "OrderAuctionInvitation_pkey" PRIMARY KEY ("id"),
 CONSTRAINT "OrderAuctionInvitation_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE CASCADE ON UPDATE CASCADE,
 CONSTRAINT "OrderAuctionInvitation_driverId_fkey" FOREIGN KEY ("driverId") REFERENCES "DriverProfile"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "OrderAuctionInvitation_orderId_driverId_key" ON "OrderAuctionInvitation"("orderId", "driverId");
CREATE INDEX "OrderAuctionInvitation_status_expiresAt_idx" ON "OrderAuctionInvitation"("status", "expiresAt");
CREATE INDEX "OrderAuctionInvitation_driverId_status_idx" ON "OrderAuctionInvitation"("driverId", "status");
