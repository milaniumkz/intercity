ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "publicId" TEXT;

WITH numbered AS (
  SELECT id, (10000000 + row_number() OVER (ORDER BY "createdAt"))::text AS public_id
  FROM "User"
  WHERE "publicId" IS NULL
)
UPDATE "User" u
SET "publicId" = numbered.public_id
FROM numbered
WHERE u.id = numbered.id;

CREATE UNIQUE INDEX IF NOT EXISTS "User_publicId_key" ON "User"("publicId");
