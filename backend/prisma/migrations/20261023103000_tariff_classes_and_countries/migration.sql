ALTER TABLE "TariffCity" ADD COLUMN "vehicleClass" TEXT NOT NULL DEFAULT 'ECONOMY';
UPDATE "TariffCity" SET "vehicleClass" = CASE
 WHEN lower(name) ~ '(бизнес|business)' THEN 'BUSINESS'
 WHEN lower(name) ~ '(комфорт|comfort)' THEN 'COMFORT'
 WHEN lower(name) ~ '(оптимал|optimal)' THEN 'OPTIMAL'
 ELSE 'ECONOMY' END;
ALTER TABLE "TariffCargo" ADD COLUMN "countryCode" TEXT NOT NULL DEFAULT 'KZ';
ALTER TABLE "TariffDelivery" ADD COLUMN "countryCode" TEXT NOT NULL DEFAULT 'KZ';
ALTER TABLE "IntercityRequest" ADD COLUMN "reservedRouteId" TEXT;
ALTER TABLE "IntercityRequest" ADD COLUMN "reservedSeats" INTEGER NOT NULL DEFAULT 0;
