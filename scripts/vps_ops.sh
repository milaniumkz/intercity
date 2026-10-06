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
  cancel-account-active)
    [[ "$TARGET" =~ ^[0-9]{10}$ ]] || { echo 'Expected 10-digit phone'; exit 1; }
    [[ "$(cat "$APP_ROOT/current_commit")" == '0a2f26ab9b0e9f72b2d7a1b5bb6dd52ee44be66e' ]] || { echo 'Production version changed; review required'; exit 1; }
    echo "ab6fb735531728569d6cd45f6cb2ca8d67b442b05783ebb5baaf07981ba2f78f  $APP_ROOT/current/backend/src/orders/orders.service.ts" | sha256sum --check --status
    echo "22fa79e44ac3622b02e3fb3c84f54bfa30f4513dacba8a9b23e7b02470ca995a  $APP_ROOT/current/backend/src/intercity/intercity.service.ts" | sha256sum --check --status
    backup_dir="$APP_ROOT/backups/$(date -u +%Y%m%d-%H%M%S)-account-order-cancel"
    mkdir -m 700 "$backup_dir"
    (umask 077; docker exec intercity-postgres sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > "$backup_dir/database.sql")
    test -s "$backup_dir/database.sql"
    grep -q 'PostgreSQL database dump complete' "$backup_dir/database.sql"
    echo 'Database backup verified'
    docker exec -i intercity-backend node - "$TARGET" <<'JS'
const {PrismaClient}=require('@prisma/client');
const {JwtService}=require('@nestjs/jwt');
const db=new PrismaClient();
(async()=>{
 const users=await db.user.findMany({where:{phone:{endsWith:process.argv[2]}},select:{id:true,role:true}});
 if(users.length!==1)throw Error('Expected exactly one account');
 const user=users[0];
 const orders=await db.order.findMany({where:{passengerId:user.id,status:{notIn:['COMPLETED','CANCELLED']}},select:{id:true,status:true}});
 const requests=await db.intercityRequest.findMany({where:{passengerId:user.id,status:{notIn:['COMPLETED','CANCELLED']}},select:{id:true,status:true}});
 const expectedOrders=['b46a944c-bf95-40fd-ae0f-dd25940a0e58'];
 const expectedRequests=['fbdc4438-0e1d-4587-8900-e7ef70b71855'];
 if(process.argv[2]!=='7052597368' || orders.some(x=>!expectedOrders.includes(x.id)) || requests.some(x=>!expectedRequests.includes(x.id)))throw Error('Account/order scope changed; review required');
 const token=new JwtService({secret:process.env.JWT_SECRET}).sign({sub:user.id,role:user.role},{expiresIn:'60s'});
 for(const [items,model,prefix] of [[orders,db.order,'orders'],[requests,db.intercityRequest,'intercity/requests']]) {
  for(const item of items){
   const response=await fetch(`http://127.0.0.1:${process.env.PORT||3000}/api/${prefix}/${item.id}/cancel`,{method:'POST',headers:{Authorization:`Bearer ${token}`}});
   if(!response.ok)throw Error('Cancellation API returned HTTP '+response.status);
   const result=await model.findUnique({where:{id:item.id},select:{id:true,status:true}});
   if(result.status!=='CANCELLED')throw Error('Cancellation verification failed');
   console.log(JSON.stringify(result));
  }
 }
 const remainingActiveOrders=await db.order.count({where:{passengerId:user.id,status:{notIn:['COMPLETED','CANCELLED']}}});
 const remainingActiveRequests=await db.intercityRequest.count({where:{passengerId:user.id,status:{notIn:['COMPLETED','CANCELLED']}}});
 console.log(JSON.stringify({remainingActiveOrders,remainingActiveRequests}));
 if(remainingActiveOrders||remainingActiveRequests)throw Error('Active records remain');
})().catch(e=>{console.error(e.message);process.exitCode=1}).finally(()=>db.$disconnect());
JS
    ;;
  inspect-account)
    [[ "$TARGET" =~ ^[0-9]{10}$ ]] || { echo 'Expected 10-digit phone'; exit 1; }
    docker exec -i intercity-backend node - "$TARGET" <<'JS'
const {PrismaClient}=require('@prisma/client');
const db=new PrismaClient();
(async()=>{
 const users=await db.user.findMany({where:{phone:{endsWith:process.argv[2]}},select:{id:true,role:true}});
 if(users.length!==1)throw Error('Expected exactly one account; found '+users.length);
 const user=users[0];
 const orders=await db.order.findMany({where:{passengerId:user.id,status:{notIn:['COMPLETED','CANCELLED']}},select:{id:true,status:true,mode:true,bonusUsedAmount:true,currency:true,createdAt:true}});
 const requests=await db.intercityRequest.findMany({where:{passengerId:user.id,status:{notIn:['COMPLETED','CANCELLED']}},select:{id:true,status:true,createdAt:true}});
 console.log(JSON.stringify({user,orders,requests}));
})().catch(e=>{console.error(e.message);process.exitCode=1}).finally(()=>db.$disconnect());
JS
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
