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
  enable-kz-tax-accounting)
    [[ "$TARGET" =~ ^[0-9a-f]{40}$ ]] || { echo 'Expected deployed commit SHA is required' >&2; exit 1; }
    test "$(cat "$APP_ROOT/current_commit")" = "$TARGET"
    umask 077
    backup="$APP_ROOT/backups/$(date -u +%Y%m%d-%H%M%S)-enable-kz-tax-accounting"
    mkdir -p "$backup"
    docker exec intercity-postgres sh -c 'exec pg_dump -Fc -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > "$backup/database.dump"
    test -s "$backup/database.dump"
    docker exec -i intercity-postgres pg_restore --list < "$backup/database.dump" > "$backup/contents.txt"
    test -s "$backup/contents.txt"
    echo "Verified database backup: $backup/database.dump"
    docker exec -i intercity-backend node <<'JSENABLETAX'
const { PrismaClient } = require('@prisma/client');
const { TaxService } = require('./dist/src/tax/tax.service');
(async () => {
  const p = new PrismaClient();
  try {
    const tax = new TaxService(p);
    const config = await tax.configuration();
    if (config.year !== '2026') throw new Error('Review annual parameters for the new year');
    await tax.configure({enabled:true,operatorReference:config.operatorReference,
      referralContractReference:config.referralContractReference,minPayout:Number(config.minPayout),
      year:'2026',mrp:config.mrp || 4325,mzp:config.mzp || 85000,
      policyReference:config.reference || '2026 test configuration: MRP 4325 KZT, MZP 85000 KZT; no government remittance'});
    console.log(JSON.stringify({taxEnabled:(await tax.configuration()).enabled,
      governmentIntegration:false,automaticRemittance:false,
      verifiedProfiles:await p.taxProfile.count({where:{countryCode:'KZ',status:'VERIFIED'}}),
      pendingProfiles:await p.taxProfile.count({where:{countryCode:'KZ',status:'PENDING'}})}));
  } finally {await p.$disconnect();}
})().catch(e => {console.error(e.message);process.exitCode=1;});
JSENABLETAX
    ;;
  seed-city-tariffs)
    [[ "$TARGET" =~ ^[0-9a-f]{40}$ ]] || { echo 'Expected deployed commit SHA is required' >&2; exit 1; }
    test "$(cat "$APP_ROOT/current_commit")" = "$TARGET"
    test -s /tmp/seed-all-city-tariffs.cjs
    umask 077
    backup="$APP_ROOT/backups/$(date -u +%Y%m%d-%H%M%S)-all-city-tariffs"
    mkdir -p "$backup"
    docker exec intercity-postgres sh -c 'exec pg_dump -Fc -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > "$backup/database.dump"
    test -s "$backup/database.dump"
    docker exec -i intercity-postgres pg_restore --list < "$backup/database.dump" > "$backup/contents.txt"
    test -s "$backup/contents.txt"
    echo "Verified database backup: $backup/database.dump"
    docker exec -i intercity-backend node < /tmp/seed-all-city-tariffs.cjs
    ;;
  status)
    if [[ "$TARGET" == "tax" ]]; then
      cat "$APP_ROOT/current_commit"
      docker exec -i intercity-backend node <<'JSTAXSTATUS'
const { PrismaClient } = require('@prisma/client');
(async () => {
  const p = new PrismaClient();
  try {
    const tables = await p.$queryRaw`SELECT to_regclass('public."TaxIncomeEntry"') IS NOT NULL AS ready`;
    const enabled = await p.appSettings.findUnique({where:{key:'kzTaxEnabled'}});
    const threshold = await p.appSettings.findUnique({where:{key:'referralMinPayoutKzt'}});
    const identityKey = process.env.TAX_ID_ENCRYPTION_KEY || process.env.JWT_SECRET || '';
    console.log(JSON.stringify({taxTablesReady:tables[0].ready,taxEnabled:enabled?.value==='true',referralMinimumKzt:threshold?.value || '5000',identityEncryptionReady:identityKey.length>=32}));
    if (tables[0].ready) console.log(JSON.stringify({taxProfiles:await p.taxProfile.count(),taxIncomeEvents:await p.taxIncomeEntry.count(),taxRemittances:await p.taxRemittance.count()}));
  } finally {await p.$disconnect();}
})().catch(() => {console.error('Tax readiness check failed');process.exitCode=1;});
JSTAXSTATUS
      exit 0
    fi
    if [[ "$TARGET" == "city-tariffs" ]]; then
      cat "$APP_ROOT/current_commit"
      docker exec -i intercity-postgres sh -c 'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1' <<'SQLTARIFFAUDIT'
SELECT json_build_object('country',c."countryCode",'cities',count(*),'activeCities',count(*) FILTER(WHERE c."isActive"),'withoutValidTariff',count(*) FILTER(WHERE NOT EXISTS(SELECT 1 FROM "TariffCity" t WHERE t."cityId"=c.id AND t."isActive" AND t."basePrice">=0 AND t."pricePerKm">0 AND t."pricePerMin">=0 AND t."minPrice">0))) FROM "City" c WHERE c."countryCode" IN ('KZ','RU') GROUP BY c."countryCode";
SELECT json_build_object('country',c."countryCode",'basePrice',t."basePrice",'pricePerKm',t."pricePerKm",'pricePerMin',t."pricePerMin",'minPrice',t."minPrice",'cities',count(DISTINCT c.id)) FROM "TariffCity" t JOIN "City" c ON c.id=t."cityId" WHERE c."countryCode" IN ('KZ','RU') AND t."isActive" GROUP BY c."countryCode",t."basePrice",t."pricePerKm",t."pricePerMin",t."minPrice" ORDER BY count(*) DESC LIMIT 15;
SQLTARIFFAUDIT
      exit 0
    fi
    if [[ "$TARGET" == "notifications" ]]; then
      docker exec -i intercity-backend node <<'JSNOTIFICATIONS'
const raw=process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
let valid=false;
try {const a=JSON.parse(raw || ''); valid=a.project_id==='inter-city-pkzpps' && !!a.client_email && !!a.private_key;} catch (_) {}
console.log(JSON.stringify({serverFirebaseAccountPresent:!!raw,serverFirebaseAccountValid:valid}));
JSNOTIFICATIONS
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
    if [[ "$TARGET" == topup-account:* ]]; then
      account_phone="${TARGET#topup-account:}"
      [[ "$account_phone" =~ ^7[0-9]{10}$ ]] || { echo "Invalid account phone" >&2; exit 1; }
      docker exec -i intercity-backend node - "$account_phone" <<'JSTOPUPAUDIT'
const {PrismaClient}=require('@prisma/client');
const {Kassa24Gateway,confirmedPayment}=require('./dist/src/payments/kassa24-gateway');
const p=new PrismaClient();
(async()=>{
 const users=await p.user.findMany({where:{phone:{endsWith:process.argv[2].slice(-10)}},select:{id:true,wallet:{select:{id:true,money:true,moneyRub:true}}}});
 console.log(JSON.stringify({matchedAccounts:users.length}));
 const login=process.env.KASSA24_LOGIN||process.env.KASSA24_MERCHANT_ID||'';
 const demo=process.env.KASSA24_DEMO==='true';
 const gateway=new Kassa24Gateway({baseUrl:process.env.KASSA24_API_URL||'https://ecommerce.pult24.kz',login,password:process.env.KASSA24_PASSWORD||'',demo});
 for(const user of users){
  if(!user.wallet)continue;
  console.log(JSON.stringify({walletMoneyKzt:user.wallet.money,walletMoneyRub:user.wallet.moneyRub}));
  const topups=await p.topupRequest.findMany({where:{walletId:user.wallet.id},orderBy:{createdAt:'desc'},take:10});
  for(const t of topups){
   console.log(JSON.stringify({id:t.id,amount:t.amount,currency:t.currency,status:t.status,provider:t.provider,createdAt:t.createdAt,creditedRows:await p.walletTransaction.count({where:{topupRequestId:t.id,direction:'CREDIT'}})}));
   if(t.status==='PENDING'&&t.currency==='KZT'&&['KASSA24','ONLINE'].includes(t.provider)){
    try{const state=await gateway.status(t.id);console.log(JSON.stringify({id:t.id,bankStatus:state?.status,bankNotFound:!!state?.notFound,bankDemo:state?.demo,confirmedLive:!!confirmedPayment(state,t.id,t.amount,login,false)}));}catch(_){console.log(JSON.stringify({id:t.id,bankStatusUnavailable:true}));}
   }
  }
 }
})().catch(()=>{console.error('Payment audit unavailable');process.exitCode=1}).finally(()=>p.$disconnect());
JSTOPUPAUDIT
      exit 0
    fi
    if [[ "$TARGET" == driver-account:* ]]; then
      account_phone="${TARGET#driver-account:}"
      [[ "$account_phone" =~ ^[78][0-9]{10}$ ]] || { echo "Invalid account phone" >&2; exit 1; }
      cat "$APP_ROOT/current_commit"
      docker exec -i intercity-postgres sh -c 'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1 -v account_phone="$1"' sh "$account_phone" <<'SQLACCOUNT'
SELECT json_build_object('userId',u.id,'role',u.role,'phoneCanonical',u.phone=('+'||:'account_phone'),'driverStatus',d.status,'activityScore',s."activityScore",'blockedUntil',s."activityBlockedUntil",'moneyKzt',w.money,'lockedKzt',w."lockedBonus",'bonusKzt',w.bonus,'moneyRub',w."moneyRub",'lockedRub',w."lockedBonusRub",'acceptIntercity',d."acceptIntercity")
FROM "User" u LEFT JOIN "DriverProfile" d ON d."userId"=u.id LEFT JOIN "DriverServiceStats" s ON s."driverId"=d.id LEFT JOIN "Wallet" w ON w."userId"=u.id
WHERE right(regexp_replace(u.phone,'[^0-9]','','g'),10)=right(:'account_phone',10);
SELECT json_build_object('routeId',r.id,'from',r."fromCity",'to',r."toCity",'active',r."isActive",'seats',r."seatsAvailable",'topUntil',r."topUntil") FROM "DriverIntercityRoute" r JOIN "DriverProfile" d ON d.id=r."driverId" JOIN "User" u ON u.id=d."userId" WHERE right(regexp_replace(u.phone,'[^0-9]','','g'),10)=right(:'account_phone',10);
SELECT json_build_object('paymentType',t.type,'amount',t.amount,'currency',t.currency,'createdAt',t."createdAt") FROM "WalletTransaction" t JOIN "Wallet" w ON w.id=t."walletId" JOIN "User" u ON u.id=w."userId" WHERE right(regexp_replace(u.phone,'[^0-9]','','g'),10)=right(:'account_phone',10) AND t.type='DRIVER_ROUTE_TOP' ORDER BY t."createdAt" DESC LIMIT 5;
SELECT json_build_object('activeSessions',count(*),'latestLogin',max(r."createdAt")) FROM "RefreshToken" r JOIN "User" u ON u.id=r."userId" WHERE right(regexp_replace(u.phone,'[^0-9]','','g'),10)=right(:'account_phone',10);
SELECT key,value FROM "AppSettings" WHERE key='driverRouteTopPolicy';
SQLACCOUNT
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
