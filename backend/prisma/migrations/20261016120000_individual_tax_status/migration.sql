-- A declared individual status requires no tax identity or verification.
-- Historical protected accounting identities and posted liabilities are retained.
ALTER TABLE "TaxProfile"
  ALTER COLUMN "iinEncrypted" DROP NOT NULL,
  ALTER COLUMN "iinHash" DROP NOT NULL,
  ALTER COLUMN "iinLast4" DROP NOT NULL;
