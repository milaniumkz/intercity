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
  repair-kirovsk-country)
    [[ "$(cat "$APP_ROOT/current_commit")" == "8a2be71212250194144f134922616588f9fb5254" ]] || { echo 'Release changed'; exit 1; }
    [[ "$(sha256sum "$APP_ROOT/current/backend/src/geo/geo.service.ts" | cut -d' ' -f1)" == "c62c058d8e6d0cea86afcb8cea1f709317e71190efdb7f6be964b88d74025da9" ]] || { echo 'Source mismatch'; exit 1; }
    backup_dir="$APP_ROOT/backups/$(date +%Y%m%d-%H%M%S)-kirovsk-country"
    mkdir -p "$backup_dir"; chmod 700 "$backup_dir"
    docker exec intercity-postgres sh -c 'exec pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$backup_dir/postgres.sql"
    test -s "$backup_dir/postgres.sql"
    grep -q 'PostgreSQL database dump complete' "$backup_dir/postgres.sql"
    tar -C "$APP_ROOT/shared" -czf "$backup_dir/uploads.tar.gz" uploads
    tar -tzf "$backup_dir/uploads.tar.gz" >/dev/null
    docker exec -i intercity-postgres sh -c 'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1' <<'SQL'
BEGIN;
DO $repair$
DECLARE old_city "City"%ROWTYPE; duplicate "City"%ROWTYPE; relation RECORD; refs BIGINT;
BEGIN
 SELECT * INTO STRICT old_city FROM "City" WHERE id='b9259dbe-1d95-4943-a5fc-ccd4beee1ab0' FOR UPDATE;
 SELECT * INTO STRICT duplicate FROM "City" WHERE id='9bc26cc6-ac90-522c-a086-2e811e088bc2' FOR UPDATE;
 IF old_city.name<>'Кировск' OR old_city."countryCode"<>'KZ' OR abs(old_city.lat-67.6609434)>.00001 OR abs(old_city.lng-33.7190394)>.00001 THEN RAISE EXCEPTION 'Legacy city changed'; END IF;
 IF duplicate.name<>'Кировск' OR duplicate."countryCode"<>'RU' OR abs(duplicate.lat-67.61475)>.00001 OR abs(duplicate.lng-33.67274)>.00001 THEN RAISE EXCEPTION 'Catalog city changed'; END IF;
 FOR relation IN
  SELECT c.conrelid::regclass AS table_name,a.attname AS column_name
  FROM pg_constraint c JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=c.conkey[1]
  WHERE c.contype='f' AND c.confrelid='"City"'::regclass
 LOOP
  EXECUTE format('SELECT count(*) FROM %s WHERE %I=$1',relation.table_name,relation.column_name) INTO refs USING duplicate.id;
  IF refs<>0 THEN RAISE EXCEPTION 'Duplicate city acquired references'; END IF;
 END LOOP;
 UPDATE "City" SET "countryCode"='RU',region=duplicate.region,lat=duplicate.lat,lng=duplicate.lng,
 aliases=ARRAY(SELECT DISTINCT value FROM unnest(old_city.aliases||duplicate.aliases) value ORDER BY value),
 "updatedAt"=CURRENT_TIMESTAMP WHERE id=old_city.id;
 DELETE FROM "City" WHERE id=duplicate.id;
END $repair$;
COMMIT;
SELECT "countryCode",name,region,lat,lng FROM "City" WHERE id='b9259dbe-1d95-4943-a5fc-ccd4beee1ab0';
SQL
    echo "Country corrected; original city ID, tariff values and order history retained. Backup: $backup_dir"
    ;;
  status)
    if [[ "$TARGET" == "inspect-city-country" ]]; then
      docker exec -i intercity-backend node <<'JS'
const {PrismaClient}=require('@prisma/client');const p=new PrismaClient();
p.city.findMany({where:{name:'Кировск',lat:{gt:60}},select:{id:true,name:true,region:true,countryCode:true,lat:true,lng:true,tariffs:{select:{id:true,name:true,basePrice:true,minPrice:true,isActive:true}},_count:{select:{tariffs:true,orders:true,users:true,drivers:true,promos:true,notificationCampaigns:true}}}}).then(rows=>console.log(JSON.stringify(rows))).finally(()=>p.$disconnect());
JS
      exit 0
    fi
    if [[ "$TARGET" == "audit-geo-catalog" ]]; then
      docker exec -i -e BASE_URL=http://127.0.0.1:3000/api -e CATALOG_DIR=/app/dist/src/geo/data intercity-backend node < /tmp/intercity-audit-geo-catalog.js
      exit 0
    fi
    if [[ "$TARGET" == "geo-key-status" ]]; then
      docker exec -i intercity-backend node <<'JS'
for (const name of ['YANDEX_GEOCODER_API_KEY','YANDEX_MAPS_API_KEY']) console.log(name, process.env[name]?.trim() ? 'configured' : 'missing');
JS
      exit 0
    fi
    if [[ "$TARGET" == "verify-active" ]]; then
      docker exec -i intercity-backend node <<'JS'
const {PrismaClient}=require('@prisma/client');const jwt=require('jsonwebtoken');const p=new PrismaClient();
(async()=>{
 for(const [id,label] of [['b9a5d580-b264-48e1-81d0-ebb98a79e93b','account 2235'],['92578d3c-56e6-4501-989f-9b5726f8681c','account 6779']]){
  const user=await p.user.findUnique({where:{id}});if(!user)throw Error('Account missing');
  const token=jwt.sign({sub:id,role:user.role},process.env.JWT_SECRET,{expiresIn:'2m'});
  const r=await fetch('http://127.0.0.1:3000/api/orders/active',{headers:{Authorization:'Bearer '+token}});
  if(!r.ok)throw Error('Active endpoint failed '+r.status);
  const text=await r.text();const data=text?JSON.parse(text):null;
  console.log(label,JSON.stringify(data));
  const where={passengerId:id,status:{notIn:['CANCELLED','COMPLETED']}};
  const city=await p.order.findFirst({where,orderBy:{createdAt:'desc'},select:{id:true,status:true}});
  const request=city?null:await p.intercityRequest.findFirst({where,orderBy:{createdAt:'desc'},select:{id:true,status:true}});
  const expected=city?{...city,type:'CITY'}:request?{...request,type:'INTERCITY'}:null;
  if(JSON.stringify(expected)!==JSON.stringify(data))throw Error('Active endpoint differs from database state');
 }
})().catch(e=>{console.error(e.message);process.exitCode=1}).finally(()=>p.$disconnect());
JS
      exit 0
    fi
    if [[ "$TARGET" == "inspect-other" ]]; then
      docker exec -i intercity-postgres sh -c 'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1' <<'SQL'
BEGIN READ ONLY;
SELECT id, right(phone,4) FROM "User" WHERE regexp_replace(phone,'[^0-9]','','g')='77780646779';
SELECT o.id,o.status,o."createdAt",o."driverId"
FROM "Order" o JOIN "User" u ON u.id=o."passengerId"
WHERE regexp_replace(u.phone,'[^0-9]','','g')='77780646779' AND o.status::text NOT IN ('COMPLETED','CANCELLED');
SELECT r.id,r.status,r."createdAt",r."selectedDriverId"
FROM "IntercityRequest" r JOIN "User" u ON u.id=r."passengerId"
WHERE regexp_replace(u.phone,'[^0-9]','','g')='77780646779' AND r.status::text NOT IN ('COMPLETED','CANCELLED');
ROLLBACK;
SQL
      exit 0
    fi
    if [[ "$TARGET" == "cancel-oleg" ]]; then
      [[ "$(cat "$APP_ROOT/current_commit")" == "d1e18b60a102417b6f64393d44450a79e67a3c5c" ]] || { echo 'Release changed'; exit 1; }
      [[ "$(sha256sum "$APP_ROOT/current/backend/src/intercity/intercity.service.ts" | cut -d' ' -f1)" == "4b10526111c1a7f664ad557c396f71d040de56329700a8087d4829db5e6dbd4c" ]] || { echo "Source mismatch"; exit 1; }
      [[ "$(sha256sum "$APP_ROOT/current/backend/src/common/active-passenger-order.ts" | cut -d' ' -f1)" == "66ae09652167051f153d0ec7c68641ddcdfbcf8fe1405f538170f4b0b9a78a89" ]] || { echo "Source mismatch"; exit 1; }
      backup_dir="$APP_ROOT/backups/$(date +%Y%m%d-%H%M%S)-cancel-oleg"
      mkdir -p "$backup_dir"
      chmod 700 "$backup_dir"
      docker exec intercity-postgres sh -c 'exec pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$backup_dir/postgres.sql"
      test -s "$backup_dir/postgres.sql"
      grep -q 'PostgreSQL database dump complete' "$backup_dir/postgres.sql"
      tar -C "$APP_ROOT/shared" -czf "$backup_dir/uploads.tar.gz" uploads
      tar -tzf "$backup_dir/uploads.tar.gz" >/dev/null
      echo "Verified backup: $backup_dir"
      docker exec -i intercity-backend node <<'JS'
const {PrismaClient}=require('@prisma/client');
const jwt=require('jsonwebtoken');
const p=new PrismaClient();
(async()=>{
 const user=await p.user.findUnique({where:{phone:'+77058652235'}});
 if(!user || user.id!=='b9a5d580-b264-48e1-81d0-ebb98a79e93b')throw Error('Account mismatch');
 const cityId='af3b5950-4431-4342-b7f9-ee352aea6afd';
 const requestIds=['4f9a0a7f-b527-474b-99de-64a296a07e46','ffc853db-9c8b-4197-a4aa-7f12d1334f8c'];
 const city=await p.order.findUnique({where:{id:cityId}});
 if(!city||city.passengerId!==user.id||city.status!=='SEARCHING_DRIVER'||city.driverId)throw Error('City order state changed');
 for(const id of requestIds){const r=await p.intercityRequest.findUnique({where:{id}});if(!r||r.passengerId!==user.id||r.status!=='OPEN'||r.selectedDriverId)throw Error('Request state changed');}
 const token=jwt.sign({sub:user.id,role:user.role},process.env.JWT_SECRET,{expiresIn:'2m'});
 for(const path of [`/orders/${cityId}/cancel`,...requestIds.map(id=>`/intercity/requests/${id}/cancel`)]){
  const r=await fetch('http://127.0.0.1:3000/api'+path,{method:'POST',headers:{Authorization:'Bearer '+token}});
  if(!r.ok)throw Error('Cancellation failed '+r.status);
  const data=await r.json();if(data.status!=='CANCELLED')throw Error('Cancellation not confirmed');
  console.log('Cancelled',data.id);
 }
 const where={passengerId:user.id,status:{notIn:['CANCELLED','COMPLETED']}};
 const cityCount=await p.order.count({where});const intercityCount=await p.intercityRequest.count({where});
 console.log('Remaining active city:',cityCount,'intercity:',intercityCount);
 if(cityCount||intercityCount)throw Error('Other active orders remain');
})().catch(e=>{console.error(e.message);process.exitCode=1}).finally(()=>p.$disconnect());
JS
      exit 0
    fi
    if [[ "$TARGET" == "inspect-oleg" ]]; then
      docker exec -i intercity-postgres sh -c 'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1' <<'SQL'
BEGIN READ ONLY;
SELECT u.id, u.name, right(u.phone,4),
 (SELECT count(*) FROM "Order" o WHERE o."passengerId"=u.id AND o.status::text NOT IN ('COMPLETED','CANCELLED')) AS active_city,
 (SELECT count(*) FROM "IntercityRequest" r WHERE r."passengerId"=u.id AND r.status::text NOT IN ('COMPLETED','CANCELLED')) AS active_intercity
FROM "User" u WHERE lower(u.name) LIKE '%олег%' OR lower(u.name) LIKE '%oleg%';
SELECT o.id,o.status,o."createdAt",o.price,o.currency,o."paymentMethod",right(u.phone,4)
FROM "Order" o JOIN "User" u ON u.id=o."passengerId"
WHERE (lower(u.name) LIKE '%олег%' OR lower(u.name) LIKE '%oleg%') AND o.status::text NOT IN ('COMPLETED','CANCELLED') ORDER BY o."createdAt" DESC;
SELECT r.id,r.status,r."createdAt",r."selectedDriverId",right(u.phone,4)
FROM "IntercityRequest" r JOIN "User" u ON u.id=r."passengerId"
WHERE (lower(u.name) LIKE '%олег%' OR lower(u.name) LIKE '%oleg%') AND r.status::text NOT IN ('COMPLETED','CANCELLED') ORDER BY r."createdAt" DESC;
ROLLBACK;
SQL
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
