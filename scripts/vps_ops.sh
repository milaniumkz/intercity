#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="${APP_ROOT:-/opt/intercity}"
ACTION="${1:?status|logs|restart|redeploy-current|rollback}"
TARGET="${2:-}"

compose() {
  cd "$APP_ROOT/current/infra/vps"
  docker compose -f docker-compose.prod.yml "$@"
}

case "$ACTION" in
  status)
    if [[ "$TARGET" == "driver-2153-dispatch" ]]; then
      docker exec -i intercity-postgres sh -c 'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -x -v ON_ERROR_STOP=1' <<'SQLDISPATCH'
SELECT q.id, q.status, q.mode, q."requestType", c.name AS city, q."driverId", q."dispatchDriverId",
 q."dispatchExpiresAt", q."dispatchRetryAt", q."dispatchTriedDriverIds", q."createdAt", q."fromLat", q."fromLng"
FROM "Order" q LEFT JOIN "City" c ON c.id=q."cityId"
WHERE q.status IN ('CREATED','SEARCHING_DRIVER','DRIVER_ASSIGNED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS')
ORDER BY q."createdAt" DESC LIMIT 20;
SELECT q.id, q.status, q."updatedAt" FROM "IntercityRequest" q
WHERE q."selectedDriverId"=(SELECT "userId" FROM "DriverProfile" WHERE id='f9e18ab4-ef0b-4695-8769-5c6ae57403c7')
AND q.status IN ('ACCEPTED','DRIVER_ASSIGNED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS');
SELECT o."isOnline", o."cityId", o."lastLat", o."lastLng", o."lastLocationAt", d."acceptCityFixed", d."acceptDelivery", d."acceptCargo", w.money,
 s."activityBlockedUntil", s."activityScore" FROM "DriverProfile" d
LEFT JOIN "DriverOnline" o ON o."driverId"=d.id LEFT JOIN "Wallet" w ON w."userId"=d."userId"
LEFT JOIN "DriverServiceStats" s ON s."driverId"=d.id WHERE d.id='f9e18ab4-ef0b-4695-8769-5c6ae57403c7';
SELECT key,value FROM "AppSettings" WHERE key IN ('driverMinOnlineBalance','driverMinOnlineBalanceRub','dispatchSearchRadiusKm','dispatchMinFreshSec');
SQLDISPATCH
      exit 0
    fi
    if [[ "$TARGET" == "driver-7052597368" ]]; then
      docker exec -i intercity-postgres sh -c 'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -x -v ON_ERROR_STOP=1' <<'SQLDRIVER'
SELECT d.id, d.status, d."acceptCityFixed", o."isOnline", c.name AS city,
 o."lastLat", o."lastLng", o."lastLocationAt", r."ratingAvg", r."ratingCount",
 s."activityScore", s."activityBlockedUntil", w.money, w."moneyRub"
FROM "User" u JOIN "DriverProfile" d ON d."userId"=u.id
LEFT JOIN "DriverOnline" o ON o."driverId"=d.id
LEFT JOIN "City" c ON c.id=o."cityId"
LEFT JOIN "DriverRating" r ON r."driverId"=d.id
LEFT JOIN "DriverServiceStats" s ON s."driverId"=d.id
LEFT JOIN "Wallet" w ON w."userId"=u.id
WHERE regexp_replace(u.phone, '[^0-9]', '', 'g') LIKE '%7052597368';
SELECT q.id, q.status, q."driverId", q."dispatchDriverId", q."dispatchExpiresAt", q."createdAt"
FROM "Order" q JOIN "DriverProfile" d ON d.id=q."driverId" OR d.id=q."dispatchDriverId"
JOIN "User" u ON u.id=d."userId"
WHERE regexp_replace(u.phone, '[^0-9]', '', 'g') LIKE '%7052597368'
AND q.status IN ('SEARCHING_DRIVER','DRIVER_ASSIGNED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS')
ORDER BY q."createdAt" DESC;
SELECT q.id, q.status, q."selectedDriverId", q."updatedAt"
FROM "IntercityRequest" q JOIN "User" u ON u.id=q."selectedDriverId"
WHERE regexp_replace(u.phone, '[^0-9]', '', 'g') LIKE '%7052597368'
AND q.status IN ('ACCEPTED','DRIVER_ASSIGNED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS');
SELECT right(regexp_replace(u.phone, '[^0-9]', '', 'g'), 4) AS phone_last4,
 d.id, d.status, o."isOnline", c.name AS city, o."lastLocationAt", s."activityScore",
 r."ratingAvg", r."ratingCount", f."hasCheckers", f."hasBranding", s."serviceStartAt",
 (b."bonusActiveUntil">now()) AS fuel_bonus_active
FROM "DriverProfile" d JOIN "User" u ON u.id=d."userId"
LEFT JOIN "DriverOnline" o ON o."driverId"=d.id
LEFT JOIN "City" c ON c.id=o."cityId"
LEFT JOIN "DriverServiceStats" s ON s."driverId"=d.id
LEFT JOIN "DriverRating" r ON r."driverId"=d.id
LEFT JOIN "DriverPriorityFlags" f ON f."driverId"=d.id
LEFT JOIN "DriverPartnerFuelBonus" b ON b."driverId"=d.id
WHERE o."isOnline"=true OR s."activityScore"=88;
SQLDRIVER
      exit 0
    fi
    if [[ "$TARGET" == "release-lockfile" ]]; then
      python3 - "$APP_ROOT/current/apps/mobile_flutter/pubspec.lock" <<'PYLOCK'
import base64, pathlib, sys
print('RELEASE_LOCK_BASE64=' + base64.b64encode(pathlib.Path(sys.argv[1]).read_bytes()).decode())
PYLOCK
      exit 0
    fi
    cat "$APP_ROOT/current_commit" 2>/dev/null || true
    compose ps
    command -v python3
    df -h "$APP_ROOT"
    current_release="$(readlink -f "$APP_ROOT/current")"
    for file in backend/prisma/schema.prisma backend/src/orders/orders.service.ts backend/src/intercity/intercity.service.ts backend/src/wallet/wallet.service.ts apps/mobile_flutter/lib/core/utils/phone_input_formatter.dart apps/admin_web/lib/features/admin/screens/admin_dashboard_page.dart; do
      (cd "$current_release" && sha256sum "$file")
    done
    docker exec -i intercity-postgres sh -c 'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1' <<'SQL'
SELECT table_name, column_name FROM information_schema.columns
WHERE table_schema = 'public' AND
  ((table_name = 'Wallet' AND column_name IN ('money', 'bonus', 'moneyRub', 'bonusRub')) OR
   (table_name = 'City' AND column_name = 'countryCode')) ORDER BY 1, 2;
SELECT to_regclass('public._prisma_migrations');
SELECT pg_size_pretty(pg_database_size(current_database()));
SQL
    migrations_table="$(docker exec -i intercity-postgres sh -c 'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1' <<'SQL'
SELECT to_regclass('public._prisma_migrations');
SQL
    )"
    if [[ -n "$migrations_table" ]]; then
      docker exec -i intercity-postgres sh -c 'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1' <<'SQL'
SELECT migration_name, finished_at IS NOT NULL AS applied, rolled_back_at IS NOT NULL AS rolled_back
FROM _prisma_migrations ORDER BY started_at;
SQL
    fi
    curl -fsS https://api.intercity.89-207-255-27.sslip.io/health
    ;;
  logs)
    service="${TARGET:-backend}"
    case "$service" in backend|caddy|postgres) ;; *) echo "Unsupported service" >&2; exit 1 ;; esac
    compose logs --tail=200 "$service" | sed -E 's/(Bearer )[A-Za-z0-9._-]+/\1***REDACTED***/g'
    ;;
  restart)
    compose restart
    compose ps
    ;;
  redeploy-current)
    compose up -d --build
    compose ps
    ;;
  rollback)
    if [[ -z "$TARGET" || ! -d "$APP_ROOT/releases/$TARGET" ]]; then
      echo "Pass existing release commit sha" >&2
      exit 1
    fi
    ln -sfn "$APP_ROOT/releases/$TARGET" "$APP_ROOT/current"
    printf '%s\n' "$TARGET" > "$APP_ROOT/current_commit"
    cd "$APP_ROOT/current/infra/vps"
    cp "$APP_ROOT/shared/.env" .env
    docker compose -f docker-compose.prod.yml up -d --build
    docker compose -f docker-compose.prod.yml ps
    ;;
  *)
    echo "Unsupported action: $ACTION" >&2
    exit 1
    ;;
esac
