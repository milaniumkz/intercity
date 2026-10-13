-- AlterEnum
ALTER TYPE "WalletBalanceSource" ADD VALUE 'REFERRAL';

-- AlterTable
ALTER TABLE "Wallet" ADD COLUMN     "referralMoney" DECIMAL(18,2) NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "TaxProfile" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL DEFAULT 'KZ',
    "kind" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "iinEncrypted" TEXT NOT NULL,
    "iinHash" TEXT NOT NULL,
    "iinLast4" TEXT NOT NULL,
    "activities" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "exemptions" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "consentVersion" TEXT NOT NULL,
    "consentAt" TIMESTAMP(3) NOT NULL,
    "verifiedAt" TIMESTAMP(3),
    "birthDate" TIMESTAMP(3),
    "effectiveFrom" TIMESTAMP(3),
    "verifiedBy" TEXT,
    "verificationReference" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TaxProfile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TaxAccountingIdentity" (
    "ownerKey" TEXT NOT NULL,
    "iinEncrypted" TEXT NOT NULL,
    "iinHash" TEXT NOT NULL,
    "iinLast4" TEXT NOT NULL,
    "firstIncomeAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TaxAccountingIdentity_pkey" PRIMARY KEY ("ownerKey")
);

-- CreateTable
CREATE TABLE "TaxIncomeEntry" (
    "id" TEXT NOT NULL,
    "eventKey" TEXT NOT NULL,
    "ownerKey" TEXT NOT NULL,
    "taxpayerKey" TEXT,
    "sourceKind" TEXT NOT NULL,
    "sourceId" TEXT NOT NULL,
    "currency" TEXT NOT NULL,
    "occurredAt" TIMESTAMP(3) NOT NULL,
    "period" TEXT NOT NULL,
    "profileKind" TEXT,
    "profileSnapshot" JSONB,
    "status" TEXT NOT NULL,
    "reviewReason" TEXT,
    "gross" DECIMAL(18,2) NOT NULL,
    "opv" DECIMAL(18,2) NOT NULL DEFAULT 0,
    "opvr" DECIMAL(18,2) NOT NULL DEFAULT 0,
    "so" DECIMAL(18,2) NOT NULL DEFAULT 0,
    "osms" DECIMAL(18,2) NOT NULL DEFAULT 0,
    "withheld" DECIMAL(18,2) NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TaxIncomeEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TaxRemittance" (
    "id" TEXT NOT NULL,
    "reference" TEXT NOT NULL,
    "period" TEXT NOT NULL,
    "ownerKey" TEXT NOT NULL,
    "component" TEXT NOT NULL,
    "amount" DECIMAL(18,2) NOT NULL,
    "paidAt" TIMESTAMP(3) NOT NULL,
    "recordedBy" TEXT NOT NULL,
    "note" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TaxRemittance_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TaxPeriodBasis" (
    "id" TEXT NOT NULL,
    "ownerKey" TEXT NOT NULL,
    "period" TEXT NOT NULL,
    "externalGross" DECIMAL(18,2) NOT NULL,
    "reference" TEXT NOT NULL,
    "recordedBy" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TaxPeriodBasis_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "TaxProfile_userId_key" ON "TaxProfile"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "TaxProfile_iinHash_key" ON "TaxProfile"("iinHash");

-- CreateIndex
CREATE INDEX "TaxAccountingIdentity_iinHash_idx" ON "TaxAccountingIdentity"("iinHash");

-- CreateIndex
CREATE UNIQUE INDEX "TaxIncomeEntry_eventKey_key" ON "TaxIncomeEntry"("eventKey");

-- CreateIndex
CREATE INDEX "TaxIncomeEntry_ownerKey_period_status_idx" ON "TaxIncomeEntry"("ownerKey", "period", "status");

-- CreateIndex
CREATE INDEX "TaxIncomeEntry_taxpayerKey_period_status_idx" ON "TaxIncomeEntry"("taxpayerKey", "period", "status");

-- CreateIndex
CREATE INDEX "TaxIncomeEntry_period_profileKind_status_idx" ON "TaxIncomeEntry"("period", "profileKind", "status");

-- CreateIndex
CREATE UNIQUE INDEX "TaxRemittance_reference_key" ON "TaxRemittance"("reference");

-- CreateIndex
CREATE INDEX "TaxRemittance_period_ownerKey_idx" ON "TaxRemittance"("period", "ownerKey");

-- CreateIndex
CREATE UNIQUE INDEX "TaxPeriodBasis_ownerKey_period_key" ON "TaxPeriodBasis"("ownerKey", "period");

-- AddForeignKey
ALTER TABLE "TaxProfile" ADD CONSTRAINT "TaxProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;


-- Accounting invariants are enforced even outside the application.
ALTER TABLE "TaxProfile" ADD CONSTRAINT "TaxProfile_supported_status"
  CHECK ("countryCode" = 'KZ' AND "kind" IN ('SELF_EMPLOYED','IE') AND "status" IN ('PENDING','VERIFIED','REJECTED'));
ALTER TABLE "TaxIncomeEntry" ADD CONSTRAINT "TaxIncomeEntry_valid_amounts"
  CHECK ("gross" > 0 AND "opv" >= 0 AND "opvr" >= 0 AND "so" >= 0 AND "osms" >= 0
    AND "withheld" >= 0 AND "withheld" <= "opv" + "opvr" + "so" + "osms");
ALTER TABLE "TaxRemittance" ADD CONSTRAINT "TaxRemittance_valid_component"
  CHECK ("amount" > 0 AND "component" IN ('OPV','OPVR','SO','OSMS'));
ALTER TABLE "TaxPeriodBasis" ADD CONSTRAINT "TaxPeriodBasis_valid_base" CHECK ("externalGross" >= 0);
