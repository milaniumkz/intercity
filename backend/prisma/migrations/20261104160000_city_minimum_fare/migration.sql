-- Use the existing administrative KZT-per-RUB exchange rate, never change it.
UPDATE "TariffCity" t SET "minPrice"=CASE c."countryCode" WHEN 'RU' THEN (
SELECT ROUND(500 / COALESCE((SELECT (value::jsonb->>'kztPerRub')::numeric FROM "AppSettings" WHERE key='driverRouteTopPolicy'),7),2)
) ELSE 500 END,"updatedAt"=NOW()
FROM "City" c WHERE t."cityId"=c.id AND c."countryCode" IN ('KZ','RU');
-- Ensure every city has a tariff; do not reactivate explicitly disabled tariffs.
INSERT INTO "TariffCity" (id,"cityId",name,"basePrice","pricePerKm","pricePerMin","minPrice","isActive","createdAt","updatedAt","vehicleClass")
SELECT gen_random_uuid()::text,c.id,'Эконом — базовый тариф',
CASE WHEN c."countryCode"='RU' THEN 90 ELSE 400 END,
CASE WHEN c."countryCode"='RU' THEN 18 ELSE 90 END,
CASE WHEN c."countryCode"='RU' THEN 4 ELSE 15 END,
CASE WHEN c."countryCode"='RU' THEN (
SELECT ROUND(500 / COALESCE((SELECT (value::jsonb->>'kztPerRub')::numeric FROM "AppSettings" WHERE key='driverRouteTopPolicy'),7),2)
) ELSE 500 END,true,NOW(),NOW(),'ECONOMY'
FROM "City" c WHERE c."countryCode" IN ('KZ','RU') AND NOT EXISTS(SELECT 1 FROM "TariffCity" t WHERE t."cityId"=c.id);
