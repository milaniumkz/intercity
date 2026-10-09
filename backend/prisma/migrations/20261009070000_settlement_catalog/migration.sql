ALTER TABLE "City" ADD COLUMN "aliases" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
DROP INDEX IF EXISTS "City_name_key";
CREATE INDEX "City_countryCode_name_idx" ON "City"("countryCode", "name");
