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
  seed-kz-city-tariffs)
    test "$(cat "$APP_ROOT/current_commit")" = "b6ae1d7500b22ae6da04cb8bedcea00e80572b54"
    test "$(sha256sum "$APP_ROOT/current/backend/prisma/schema.prisma" | cut -d " " -f 1)" = "3aecf8594e9564f14d9ea21648b0b0f78feb3ae7ff6551bd94b0b15273e26c6e"
    test "$(sha256sum "$APP_ROOT/current/backend/src/geo/geo.service.ts" | cut -d " " -f 1)" = "e6932169a439cbff92d16294573a9474d663150b26b5c4894865e9ffb5cf7cc2"
    test "$(sha256sum "$APP_ROOT/current/backend/src/orders/orders.service.ts" | cut -d " " -f 1)" = "bb851a6d26766f938e51093176c98c6a9824fed14a29ccd4be17a7ed589b29f5"
    umask 077
    backup="$APP_ROOT/backups/$(date -u +%Y%m%d-%H%M%S)-kz-city-tariffs"
    mkdir -p "$backup"
    docker exec intercity-postgres sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > "$backup/database.sql"
    test -s "$backup/database.sql"
    tail -n 10 "$backup/database.sql" | grep -q 'PostgreSQL database dump complete'
    echo "Verified database backup: $backup/database.sql"
    docker exec -i intercity-backend node - <<'NODE'
const {PrismaClient}=require('@prisma/client');
const {GeoService}=require('/app/dist/src/geo/geo.service');
const assert=require('node:assert/strict');
const p=new PrismaClient();
(async()=>{
 const before=await p.city.findMany({include:{tariffs:true},orderBy:{name:'asc'}});
 console.log(JSON.stringify({before:before.filter(c=>c.countryCode==='KZ').map(c=>({name:c.name,tariffs:c.tariffs.length})),yandexGeocoderConfigured:!!process.env.YANDEX_GEOCODER_API_KEY}));
 const ruSnapshot=JSON.stringify(before.filter(c=>c.countryCode==='RU'));
 const cities=GeoService.fallbackCities.filter(c=>c.region==='Казахстан');
 cities.push({name:'Шемонаиха',region:'Восточно-Казахстанская область',lat:50.6273293,lng:81.9086454});
 const result=await p.$transaction(async tx=>{
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(6100629)`;
  let newCities=0,newTariffs=0;
  for(const data of cities){const found=await tx.city.findUnique({where:{name:data.name}});if(found){assert.equal(found.countryCode,'KZ');}else{await tx.city.create({data:{...data,countryCode:'KZ'}});newCities++;}}
  const active=await tx.city.findMany({where:{countryCode:'KZ',isActive:true},include:{tariffs:true}});
  for(const city of active){if(city.tariffs.some(t=>t.isActive&&t.basePrice>0&&t.pricePerKm>0&&t.minPrice>0))continue;assert(!city.tariffs.some(t=>t.isActive),'Invalid existing active tariff: '+city.name);await tx.tariffCity.create({data:{cityId:city.id,name:'Стандарт — стартовый ориентировочный',basePrice:400,pricePerKm:90,pricePerMin:15,minPrice:700}});newTariffs++;}
  return {newCities,newTariffs};
 },{timeout:30000});
 const after=await p.city.findMany({include:{tariffs:true},orderBy:{name:'asc'}});
 assert.equal(JSON.stringify(after.filter(c=>c.countryCode==='RU')),ruSnapshot);
 console.log(JSON.stringify({result,kzCities:after.filter(c=>c.countryCode==='KZ').map(c=>({name:c.name,activeTariffs:c.tariffs.filter(t=>t.isActive).length})),russianRatesUnchanged:true}));
})().catch(e=>{console.error(e.message);process.exitCode=1}).finally(()=>p.$disconnect());

NODE
    ;;
  status)
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
