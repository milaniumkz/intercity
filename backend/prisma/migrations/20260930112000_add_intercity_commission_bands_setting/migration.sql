INSERT INTO "AppSettings" ("id", "key", "value", "createdAt", "updatedAt")
VALUES (
    'intercity-commission-bands-setting',
    'intercityCommissionByDistanceKm',
    '[{"fromKm":0,"toKm":200,"fee":500},{"fromKm":200,"toKm":500,"fee":1000},{"fromKm":500,"toKm":1000,"fee":1500},{"fromKm":1000,"toKm":null,"fee":2000}]',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
)
ON CONFLICT ("key") DO NOTHING;

