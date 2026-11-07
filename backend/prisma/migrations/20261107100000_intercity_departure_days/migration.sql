-- Keep existing records and reservations; allow the same driver route on different days.
ALTER TABLE "IntercityRequest" ADD COLUMN "departureOffsetMinutes" INTEGER;
ALTER TABLE "RideSharingTrip" ADD COLUMN "departureOffsetMinutes" INTEGER;
UPDATE "IntercityRequest" r SET "departureOffsetMinutes"=d."departureOffsetMinutes"
FROM "DriverIntercityRoute" d WHERE r."reservedRouteId"=d.id;
DROP INDEX IF EXISTS "DriverIntercityRoute_driverId_fromCity_toCity_key";
CREATE INDEX "DriverIntercityRoute_driverId_fromCity_toCity_departureAt_idx" ON "DriverIntercityRoute"("driverId","fromCity","toCity","departureAt");
CREATE INDEX "IntercityRequest_passengerId_date_idx" ON "IntercityRequest"("passengerId","date");
CREATE INDEX "RideSharingTrip_driverId_departureTime_idx" ON "RideSharingTrip"("driverId","departureTime");
