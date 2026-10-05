CREATE TABLE "CarMake" (
    "id" INTEGER NOT NULL,
    "name" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CarMake_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "CarModel" (
    "id" INTEGER NOT NULL,
    "makeId" INTEGER NOT NULL,
    "name" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CarModel_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "CarMake_name_key" ON "CarMake"("name");
CREATE INDEX "CarModel_makeId_name_idx" ON "CarModel"("makeId", "name");
CREATE UNIQUE INDEX "CarModel_makeId_name_key" ON "CarModel"("makeId", "name");

ALTER TABLE "CarModel" ADD CONSTRAINT "CarModel_makeId_fkey" FOREIGN KEY ("makeId") REFERENCES "CarMake"("id") ON DELETE CASCADE ON UPDATE CASCADE;
