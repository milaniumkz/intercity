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
    if [[ "$TARGET" == "release-progress" ]]; then
      python3 - "$APP_ROOT" <<'PYPROGRESS'
import pathlib, datetime, sys
root=pathlib.Path(sys.argv[1])
for directory,pattern in [(pathlib.Path('/tmp'),'intercity-vps-*.tar.gz'),(root/'backups','*'),(root/'releases','*')]:
    paths=sorted(directory.glob(pattern),key=lambda p:p.stat().st_mtime,reverse=True)[:3]
    for path in paths:
        st=path.stat()
        print(str(path), 'bytes='+str(st.st_size), 'modified='+datetime.datetime.fromtimestamp(st.st_mtime,datetime.timezone.utc).isoformat())
PYPROGRESS
      ps -eo comm,etime,pcpu --sort=-pcpu | head -15
      docker ps --format '{{.Names}} {{.Status}}'
      docker images --format '{{.Repository}} {{.ID}} {{.CreatedSince}} {{.Size}}' | head -8
      exit 0
    fi
    if [[ "$TARGET" == "payment-config" ]]; then
      docker exec -i intercity-backend node <<'JSPAYMENTCONFIG'
(async () => {
  const login=process.env.KASSA24_LOGIN || process.env.KASSA24_MERCHANT_ID || '';
  const password=process.env.KASSA24_PASSWORD || '';
  console.log(JSON.stringify({loginPresent:!!login,passwordPresent:!!password,tokenEncryptionKeyReady:(process.env.KASSA24_TOKEN_ENCRYPTION_KEY || process.env.JWT_SECRET || '').length>=32,acquiringIdPresent:!!process.env.KASSA24_ACQUIRING_ID,savedCardsEnabled:process.env.KASSA24_SAVED_CARDS_ENABLED==='true',demo:process.env.KASSA24_DEMO==='true',publicApiUrlPresent:!!(process.env.BACKEND_PUBLIC_URL || process.env.PUBLIC_API_URL),publicWebUrlPresent:!!(process.env.PUBLIC_WEB_URL || process.env.WEB_APP_URL || process.env.FRONTEND_URL)}));
  if (login && password) {
    try {
      const base=process.env.KASSA24_API_URL || 'https://ecommerce.pult24.kz';
      const url=new URL('payment/status?orderid=intercity-readonly-credential-check',base.replace(/\/+$/,'')+'/');
      if (url.protocol!=='https:') throw new Error('TLS required');
      const response=await fetch(url,{headers:{Authorization:'Basic '+Buffer.from(login+':'+password).toString('base64')},signal:AbortSignal.timeout(8000)});
      console.log(JSON.stringify({authenticatedReadHttpStatus:response.status}));
    } catch (_) {console.log(JSON.stringify({authenticatedReadUnavailable:true}));}
  }
})().catch(()=>process.exitCode=1);
JSPAYMENTCONFIG
      docker exec -i intercity-postgres sh -c 'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1' <<'SQLPAYMENTCONFIG'
SELECT key, value='true' AS enabled FROM "AppSettings" WHERE key='kassa24SavedCardsEnabled';
SELECT key, value ~ '^[0-9]+$' AS numeric_value_present FROM "AppSettings" WHERE key='kassa24AcquiringId';
SQLPAYMENTCONFIG
      exit 0
    fi
    if [[ "$TARGET" == driver-offers:* ]]; then
      driver_phone="${TARGET#driver-offers:}"
      [[ "$driver_phone" =~ ^[78][0-9]{10}$ ]] || { echo "Invalid driver phone" >&2; exit 1; }
      docker exec -i intercity-postgres sh -c 'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1 -v driver_phone="$1"' sh "$driver_phone" <<'SQLOFFERS'
SELECT now();
SELECT d.id,d.status,o."isOnline",o."lastLocationAt",s."activityScore"
FROM "DriverProfile" d JOIN "User" u ON u.id=d."userId"
LEFT JOIN "DriverOnline" o ON o."driverId"=d.id LEFT JOIN "DriverServiceStats" s ON s."driverId"=d.id
WHERE right(regexp_replace(u.phone,'[^0-9]','','g'),10)=right(:'driver_phone',10);
SELECT a.key,a.delta,a.score,a."createdAt" FROM "DriverActivityEvent" a
JOIN "DriverProfile" d ON d.id=a."driverId" JOIN "User" u ON u.id=d."userId"
WHERE right(regexp_replace(u.phone,'[^0-9]','','g'),10)=right(:'driver_phone',10)
ORDER BY a."createdAt" DESC LIMIT 12;
SELECT ord.id,ord.status,ord."dispatchDriverId",ord."dispatchExpiresAt",ord."updatedAt"
FROM "Order" ord JOIN "DriverProfile" d ON d.id=ANY(ord."dispatchTriedDriverIds") OR d.id=ord."dispatchDriverId"
JOIN "User" u ON u.id=d."userId"
WHERE right(regexp_replace(u.phone,'[^0-9]','','g'),10)=right(:'driver_phone',10)
ORDER BY ord."updatedAt" DESC LIMIT 10;
SQLOFFERS
      exit 0
    fi
    if [[ "$TARGET" == "rating-storage" ]]; then
      docker exec -i intercity-postgres sh -c 'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1' <<'SQLRATING'
SELECT to_regclass('public."Complaint"'), to_regclass('public."DriverRating"');
SELECT column_name FROM information_schema.columns WHERE table_name='Complaint' ORDER BY ordinal_position;
SQLRATING
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
