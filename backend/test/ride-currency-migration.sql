-- Run only in a disposable empty migration test database.
CREATE TABLE "City" (id TEXT PRIMARY KEY, name TEXT, region TEXT);
CREATE TABLE "Order" (id TEXT PRIMARY KEY, "cityId" TEXT, price DOUBLE PRECISION);
CREATE TABLE "IntercityRequest" (id TEXT PRIMARY KEY, "fromCity" TEXT, price DOUBLE PRECISION);
CREATE TABLE "RideSharingTrip" (id TEXT PRIMARY KEY, "fromCity" TEXT, "pricePerSeat" DOUBLE PRECISION);
CREATE TABLE "Wallet" (id TEXT PRIMARY KEY, money DOUBLE PRECISION, bonus DOUBLE PRECISION);
CREATE TABLE "TopupRequest" (id TEXT PRIMARY KEY, amount DOUBLE PRECISION);
CREATE TABLE "PayoutRequest" (id TEXT PRIMARY KEY, amount DOUBLE PRECISION);
CREATE TABLE "WalletTransaction" (id TEXT PRIMARY KEY, amount DOUBLE PRECISION);
INSERT INTO "Wallet" VALUES ('legacy', 7000, 8000);
INSERT INTO "TopupRequest" VALUES ('legacy-topup', 200);
INSERT INTO "PayoutRequest" VALUES ('legacy-payout', 300);
INSERT INTO "WalletTransaction" VALUES ('legacy-tx', 400);
INSERT INTO "City" VALUES ('ru', 'Москва', 'Центральный федеральный округ'), ('kz', 'Алматы', 'Алматинская область');
INSERT INTO "Order" VALUES ('ru-order', 'ru', 500), ('kz-order', 'kz', 1000);
INSERT INTO "IntercityRequest" VALUES ('ru-request', 'Москва, улица Тверская', 2000), ('kz-request', 'Алматы', 5000);
INSERT INTO "RideSharingTrip" VALUES ('ru-trip', 'Москва', 1500), ('kz-trip', 'Алматы', 3000);

\ir ../prisma/migrations/20261006120000_ride_currency/migration.sql

\ir ../prisma/migrations/20261006130000_wallet_currency/migration.sql

DO $$
BEGIN
  ASSERT (SELECT money FROM "Wallet" WHERE id = 'legacy') = 7000;
  ASSERT (SELECT bonus FROM "Wallet" WHERE id = 'legacy') = 8000;
  ASSERT (SELECT "moneyRub" FROM "Wallet" WHERE id = 'legacy') = 0;
  ASSERT (SELECT "bonusRub" FROM "Wallet" WHERE id = 'legacy') = 0;
  ASSERT (SELECT currency FROM "TopupRequest" WHERE id = 'legacy-topup') = 'KZT';
  ASSERT (SELECT currency FROM "PayoutRequest" WHERE id = 'legacy-payout') = 'KZT';
  ASSERT (SELECT currency FROM "WalletTransaction" WHERE id = 'legacy-tx') = 'KZT';
  ASSERT (SELECT "countryCode" FROM "City" WHERE id = 'ru') = 'RU';
  ASSERT (SELECT "countryCode" FROM "City" WHERE id = 'kz') = 'KZ';
  ASSERT (SELECT "currency" FROM "Order" WHERE id = 'ru-order') = 'RUB';
  ASSERT (SELECT "currency" FROM "Order" WHERE id = 'kz-order') = 'KZT';
  ASSERT (SELECT "currency" FROM "IntercityRequest" WHERE id = 'ru-request') = 'RUB';
  ASSERT (SELECT "currency" FROM "IntercityRequest" WHERE id = 'kz-request') = 'KZT';
  ASSERT (SELECT "currency" FROM "RideSharingTrip" WHERE id = 'ru-trip') = 'RUB';
  ASSERT (SELECT "currency" FROM "RideSharingTrip" WHERE id = 'kz-trip') = 'KZT';
  ASSERT (SELECT price FROM "Order" WHERE id = 'ru-order') = 500;
  ASSERT (SELECT price FROM "IntercityRequest" WHERE id = 'ru-request') = 2000;
  ASSERT (SELECT "pricePerSeat" FROM "RideSharingTrip" WHERE id = 'ru-trip') = 1500;
END $$;
