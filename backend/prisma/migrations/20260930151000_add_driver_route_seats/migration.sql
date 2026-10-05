ALTER TABLE "DriverIntercityRoute"
ADD COLUMN IF NOT EXISTS "seatsTotal" INTEGER NOT NULL DEFAULT 4,
ADD COLUMN IF NOT EXISTS "seatsAvailable" INTEGER NOT NULL DEFAULT 4;

UPDATE "DriverIntercityRoute"
SET "seatsTotal" = GREATEST(1, COALESCE("seatsTotal", 4)),
    "seatsAvailable" = GREATEST(0, COALESCE("seatsAvailable", COALESCE("seatsTotal", 4)));
