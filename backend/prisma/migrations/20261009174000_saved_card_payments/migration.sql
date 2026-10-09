-- AlterTable
ALTER TABLE "Order" ADD COLUMN     "paymentCardId" TEXT;

-- AlterTable
ALTER TABLE "IntercityRequest" ADD COLUMN     "paymentCardId" TEXT;

-- CreateTable
CREATE TABLE "SavedPaymentCard" (
    "id" TEXT NOT NULL,
    "phone" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "tokenEncrypted" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "last4" TEXT NOT NULL,
    "acquiringId" INTEGER NOT NULL,
    "demo" BOOLEAN NOT NULL,
    "isDefault" BOOLEAN NOT NULL DEFAULT false,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SavedPaymentCard_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CardBinding" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "phone" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "providerId" TEXT,
    "acquiringId" INTEGER NOT NULL,
    "demo" BOOLEAN NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CardBinding_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TripCardPayment" (
    "id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "tripId" TEXT NOT NULL,
    "passengerId" TEXT NOT NULL,
    "driverUserId" TEXT NOT NULL,
    "cardId" TEXT NOT NULL,
    "amount" DOUBLE PRECISION NOT NULL,
    "currency" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "leaseUntil" TIMESTAMP(3),
    "nextCheckAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastError" TEXT,
    "paidAt" TIMESTAMP(3),
    "refundedAt" TIMESTAMP(3),
    "earningsCredited" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TripCardPayment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CardPaymentAttempt" (
    "id" TEXT NOT NULL,
    "paymentId" TEXT NOT NULL,
    "number" INTEGER NOT NULL,
    "providerId" TEXT,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CardPaymentAttempt_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SavedPaymentCard_tokenHash_key" ON "SavedPaymentCard"("tokenHash");

-- CreateIndex
CREATE INDEX "SavedPaymentCard_userId_active_idx" ON "SavedPaymentCard"("userId", "active");

-- CreateIndex
CREATE INDEX "TripCardPayment_status_nextCheckAt_idx" ON "TripCardPayment"("status", "nextCheckAt");

-- CreateIndex
CREATE UNIQUE INDEX "TripCardPayment_kind_tripId_key" ON "TripCardPayment"("kind", "tripId");

-- CreateIndex
CREATE UNIQUE INDEX "CardPaymentAttempt_paymentId_number_key" ON "CardPaymentAttempt"("paymentId", "number");

