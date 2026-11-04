-- Initial configurable cargo rates. Preserve every existing tariff and never
-- introduce a competing rate where the operator already has an active one.
INSERT INTO "TariffCargo" (id, "countryCode", name, "basePrice", "pricePerKm", "pricePerKg", "minPrice", "isActive", "createdAt", "updatedAt")
SELECT gen_random_uuid()::text, v.country, 'Грузовые — базовый тариф', v.base, v.km, v.kg, v.minimum, true, NOW(), NOW()
FROM (VALUES ('KZ', 1000, 100, 20, 1500), ('RU', 300, 25, 5, 500)) AS v(country, base, km, kg, minimum)
WHERE NOT EXISTS (SELECT 1 FROM "TariffCargo" t WHERE t."countryCode" = v.country AND t."isActive");
