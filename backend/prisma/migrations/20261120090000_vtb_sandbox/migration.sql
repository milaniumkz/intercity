CREATE TABLE "VtbSandboxPayment" (
 "id" TEXT NOT NULL, "userId" TEXT NOT NULL, "requestKey" TEXT NOT NULL,
 "amountMinor" INTEGER NOT NULL, "bankAmountMinor" INTEGER NOT NULL, "conversionRate" INTEGER NOT NULL DEFAULT 7, "purpose" TEXT NOT NULL DEFAULT 'TOPUP', "status" TEXT NOT NULL DEFAULT 'CREATED',
 "bankOrderId" TEXT, "paymentUrl" TEXT, "lastError" TEXT, "verifiedAt" TIMESTAMP(3),
 "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL,
 CONSTRAINT "VtbSandboxPayment_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "VtbSandboxPayment_bankOrderId_key" ON "VtbSandboxPayment"("bankOrderId");
CREATE UNIQUE INDEX "VtbSandboxPayment_userId_requestKey_key" ON "VtbSandboxPayment"("userId", "requestKey");
CREATE INDEX "VtbSandboxPayment_userId_createdAt_idx" ON "VtbSandboxPayment"("userId", "createdAt");
ALTER TABLE "VtbSandboxPayment" ADD CONSTRAINT "VtbSandboxPayment_userId_fkey"
 FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
