-- Preserve existing interest in city orders when merging the two UI options.
UPDATE "DriverProfile"
SET "acceptCityFixed" = ("acceptCityFixed" OR "acceptCityAuction"),
    "acceptCityAuction" = ("acceptCityFixed" OR "acceptCityAuction")
WHERE "acceptCityFixed" IS DISTINCT FROM "acceptCityAuction";
