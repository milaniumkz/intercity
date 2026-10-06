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
  seed-russian-city-tariffs)
    test "$(cat "$APP_ROOT/current_commit")" = "9f86f3bb2d1b806d6ec46c72fca74b821dfe8a95"
    test "$(sha256sum "$APP_ROOT/current/backend/prisma/schema.prisma" | cut -d " " -f 1)" = "3aecf8594e9564f14d9ea21648b0b0f78feb3ae7ff6551bd94b0b15273e26c6e"
    test "$(sha256sum "$APP_ROOT/current/backend/src/orders/orders.service.ts" | cut -d " " -f 1)" = "bb851a6d26766f938e51093176c98c6a9824fed14a29ccd4be17a7ed589b29f5"
    test "$(sha256sum "$APP_ROOT/current/backend/src/geo/geo.service.ts" | cut -d " " -f 1)" = "e6932169a439cbff92d16294573a9474d663150b26b5c4894865e9ffb5cf7cc2"
    umask 077
    backup="$APP_ROOT/backups/$(date -u +%Y%m%d-%H%M%S)-russian-city-tariffs"
    mkdir -p "$backup"
    docker exec intercity-postgres sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > "$backup/database.sql"
    test -s "$backup/database.sql"
    tail -n 10 "$backup/database.sql" | grep -q 'PostgreSQL database dump complete'
    echo "Verified database backup: $backup/database.sql"
    docker exec -i intercity-backend node - <<'NODE'
const {PrismaClient} = require('@prisma/client');
const assert = require('node:assert/strict');
const p = new PrismaClient();
const cities = [{"name": "Москва", "region": "Россия", "countryCode": "RU", "lat": 55.755864, "lng": 37.617698, "rates": {"basePrice": 180, "pricePerKm": 28, "pricePerMin": 8, "minPrice": 300}}, {"name": "Санкт-Петербург", "region": "Россия", "countryCode": "RU", "lat": 59.938955, "lng": 30.315644, "rates": {"basePrice": 150, "pricePerKm": 25, "pricePerMin": 7, "minPrice": 250}}, {"name": "Новосибирск", "region": "Россия", "countryCode": "RU", "lat": 55.030204, "lng": 82.92043, "rates": {"basePrice": 110, "pricePerKm": 20, "pricePerMin": 5, "minPrice": 180}}, {"name": "Екатеринбург", "region": "Россия", "countryCode": "RU", "lat": 56.838011, "lng": 60.597465, "rates": {"basePrice": 110, "pricePerKm": 20, "pricePerMin": 5, "minPrice": 180}}, {"name": "Казань", "region": "Россия", "countryCode": "RU", "lat": 55.796127, "lng": 49.106414, "rates": {"basePrice": 110, "pricePerKm": 20, "pricePerMin": 5, "minPrice": 180}}, {"name": "Нижний Новгород", "region": "Россия", "countryCode": "RU", "lat": 56.326887, "lng": 44.005986, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Челябинск", "region": "Россия", "countryCode": "RU", "lat": 55.164441, "lng": 61.436843, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Самара", "region": "Россия", "countryCode": "RU", "lat": 53.195878, "lng": 50.100202, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Омск", "region": "Россия", "countryCode": "RU", "lat": 54.989342, "lng": 73.368212, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Ростов-на-Дону", "region": "Россия", "countryCode": "RU", "lat": 47.222078, "lng": 39.720349, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Уфа", "region": "Россия", "countryCode": "RU", "lat": 54.734853, "lng": 55.957864, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Красноярск", "region": "Россия", "countryCode": "RU", "lat": 56.010563, "lng": 92.852572, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Пермь", "region": "Россия", "countryCode": "RU", "lat": 58.010455, "lng": 56.229443, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Воронеж", "region": "Россия", "countryCode": "RU", "lat": 51.660781, "lng": 39.200296, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Волгоград", "region": "Россия", "countryCode": "RU", "lat": 48.707103, "lng": 44.516939, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Краснодар", "region": "Россия", "countryCode": "RU", "lat": 45.03547, "lng": 38.975313, "rates": {"basePrice": 110, "pricePerKm": 20, "pricePerMin": 5, "minPrice": 180}}, {"name": "Саратов", "region": "Россия", "countryCode": "RU", "lat": 51.533557, "lng": 46.034257, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Тюмень", "region": "Россия", "countryCode": "RU", "lat": 57.152985, "lng": 65.541227, "rates": {"basePrice": 110, "pricePerKm": 20, "pricePerMin": 5, "minPrice": 180}}, {"name": "Тольятти", "region": "Россия", "countryCode": "RU", "lat": 53.507836, "lng": 49.420393, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Ижевск", "region": "Россия", "countryCode": "RU", "lat": 56.852744, "lng": 53.211396, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Барнаул", "region": "Россия", "countryCode": "RU", "lat": 53.348115, "lng": 83.779836, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Владивосток", "region": "Россия", "countryCode": "RU", "lat": 43.115536, "lng": 131.885485, "rates": {"basePrice": 110, "pricePerKm": 20, "pricePerMin": 5, "minPrice": 180}}, {"name": "Хабаровск", "region": "Россия", "countryCode": "RU", "lat": 48.480223, "lng": 135.071917, "rates": {"basePrice": 110, "pricePerKm": 20, "pricePerMin": 5, "minPrice": 180}}, {"name": "Иркутск", "region": "Россия", "countryCode": "RU", "lat": 52.286974, "lng": 104.305018, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Оренбург", "region": "Россия", "countryCode": "RU", "lat": 51.768199, "lng": 55.096955, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Калининград", "region": "Россия", "countryCode": "RU", "lat": 54.710426, "lng": 20.452214, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Сочи", "region": "Россия", "countryCode": "RU", "lat": 43.585472, "lng": 39.723098, "rates": {"basePrice": 150, "pricePerKm": 25, "pricePerMin": 7, "minPrice": 250}}, {"name": "Астрахань", "region": "Россия", "countryCode": "RU", "lat": 46.347869, "lng": 48.033574, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}, {"name": "Махачкала", "region": "Россия", "countryCode": "RU", "lat": 42.984913, "lng": 47.504646, "rates": {"basePrice": 90, "pricePerKm": 18, "pricePerMin": 4, "minPrice": 150}}];
(async () => {
 const before = await p.city.findMany({include:{tariffs:true},orderBy:{name:'asc'}});
 console.log(JSON.stringify({before:before.map(c=>({name:c.name,countryCode:c.countryCode,tariffs:c.tariffs.length}))}));
 const kzSnapshot = JSON.stringify(before.filter(c=>c.countryCode==='KZ'));
 const result = await p.$transaction(async tx => {
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(6100629)`;
  const stats={newCities:0,newTariffs:0,preservedTariffs:0};
  const extras=before.filter(c=>c.countryCode==='RU'&&!cities.some(s=>s.name===c.name));
  for(const entry of [...cities,...extras.map(c=>({...c,rates:{basePrice:90,pricePerKm:18,pricePerMin:4,minPrice:150}}))]) {
   let city=await tx.city.findUnique({where:{name:entry.name}});
   if(city) {
    assert.equal(city.countryCode,'RU',`Unexpected country for ${city.name}`);
    if(!city.isActive) city=await tx.city.update({where:{id:city.id},data:{isActive:true}});
   } else {
    const {rates,...data}=entry;
    city=await tx.city.create({data}); stats.newCities++;
   }
   const tariffs=await tx.tariffCity.findMany({where:{cityId:city.id,isActive:true}});
   if(tariffs.some(t=>t.minPrice>0 && t.basePrice>0 && t.pricePerKm>0)) {stats.preservedTariffs++;continue;}
   assert.equal(tariffs.length,0,`Review existing invalid active tariff for ${city.name}`);
   await tx.tariffCity.create({data:{cityId:city.id,name:'Стандарт — стартовый ориентировочный',...entry.rates,isActive:true}});stats.newTariffs++;
  }
  return stats;
 },{timeout:30000});
 const after=await p.city.findMany({include:{tariffs:true},orderBy:{name:'asc'}});
 assert.equal(JSON.stringify(after.filter(c=>c.countryCode==='KZ')),kzSnapshot,'Kazakhstan settings changed');
 const russian=after.filter(c=>c.countryCode==='RU');
 for(const c of russian) assert(c.isActive && c.tariffs.some(t=>t.isActive&&t.basePrice>0&&t.pricePerKm>0&&t.minPrice>0),c.name);
 console.log(JSON.stringify({result,russianCityCount:russian.length,rates:russian.map(c=>({name:c.name,tariffs:c.tariffs.map(t=>({name:t.name,basePrice:t.basePrice,pricePerKm:t.pricePerKm,pricePerMin:t.pricePerMin,minPrice:t.minPrice,isActive:t.isActive}))})),kazakhstanUnchanged:true}));
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
