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
  reset-customer-accounts)
    [[ "$TARGET" =~ ^[0-9a-f]{40}$ ]] || { echo 'Exact expected release SHA required' >&2; exit 1; }
    test "$(cat "$APP_ROOT/current_commit")" = "$TARGET"
    (cd "$APP_ROOT/current" && sha256sum -c /tmp/customer-reset-source.sha256)
    test -s /tmp/reset-nonadmin-users.cjs
    umask 077
    backup="$APP_ROOT/backups/$(date -u +%Y%m%d-%H%M%S)-customer-reset-$TARGET"
    mkdir -p "$backup"
    uploads_root="$(docker inspect intercity-backend --format '{{range .Mounts}}{{if eq .Destination "/app/uploads"}}{{.Source}}{{end}}{{end}}')"
    private_root="$(docker inspect intercity-backend --format '{{range .Mounts}}{{if eq .Destination "/app/technical-data"}}{{.Source}}{{end}}{{end}}')"
    [[ "$uploads_root" == "$APP_ROOT/"* && "$private_root" == "$APP_ROOT/"* ]] || { echo 'Unexpected data roots' >&2; exit 1; }
    test -d "$uploads_root" && test -d "$private_root"
    compose stop backend
    trap 'compose start backend >/dev/null' EXIT
    docker exec intercity-postgres sh -c 'exec pg_dump -Fc -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > "$backup/database.dump"
    test -s "$backup/database.dump"
    docker exec -i intercity-postgres pg_restore --list < "$backup/database.dump" > "$backup/database-contents.txt"
    test -s "$backup/database-contents.txt"
    tar -czf "$backup/uploads.tar.gz" -C "$uploads_root" .
    tar -tzf "$backup/uploads.tar.gz" > "$backup/uploads-contents.txt"
    tar -czf "$backup/technical-data.tar.gz" -C "$private_root" .
    tar -tzf "$backup/technical-data.tar.gz" > "$backup/technical-contents.txt"
    echo "Verified database, uploads and private-data backup: $backup"
    compose run --rm -T --no-deps -v /tmp/reset-nonadmin-users.cjs:/tmp/reset-nonadmin-users.cjs:ro -v "$backup:/ops-backup" -e RESET_MANIFEST=/ops-backup/cleanup-manifest.json backend node /tmp/reset-nonadmin-users.cjs --commit
    compose start backend
    trap - EXIT
    ready=0
    for attempt in $(seq 1 30); do
      if docker exec intercity-backend node -e "fetch('http://127.0.0.1:3000/api/geo/cities').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"; then ready=1; break; fi
      sleep 2
    done
    test "$ready" = 1
    echo 'API restarted and geographic catalogue is available'
    ;;
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
  enable-demo-topups)
    expected="${TARGET%%:*}"
    account_phone="${TARGET#*:}"
    [[ "$expected" =~ ^[a-f0-9]{40}$ && "$account_phone" =~ ^7[0-9]{10}$ ]] || { echo 'Invalid release/account target' >&2; exit 1; }
    [[ "$(cat "$APP_ROOT/current_commit")" == "$expected" ]] || { echo 'Unexpected deployed release' >&2; exit 1; }
    backup="$APP_ROOT/backups/$(date +%Y%m%d-%H%M%S)-demo-topups"
    mkdir -p "$backup"
    chmod 700 "$backup"
    docker exec intercity-postgres sh -c 'exec pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$backup/postgres.sql"
    test -s "$backup/postgres.sql"
    grep -q 'PostgreSQL database dump complete' "$backup/postgres.sql"
    echo "Verified backup: $backup"
    docker exec -i intercity-backend node - "$account_phone" <<'JSENABLEDEMO'
const {PrismaClient}=require('@prisma/client');
const {WalletService}=require('./dist/src/wallet/wallet.service');
const p=new PrismaClient();
(async()=>{
 const users=await p.user.findMany({where:{phone:{endsWith:process.argv[2].slice(-10)}},select:{id:true,wallet:{select:{id:true,money:true}}}});
 if(users.length!==1||!users[0].wallet)throw Error('Unique wallet not found');
 const user=users[0];
 await p.appSettings.upsert({where:{key:'allowDemoTopupCredits'},create:{key:'allowDemoTopupCredits',value:'true'},update:{value:'true'}});
 console.log(JSON.stringify({allowDemoTopupCredits:true,balanceBefore:user.wallet.money}));
 const service=new WalletService(p,{});
 const rows=await p.topupRequest.findMany({where:{walletId:user.wallet.id,status:'PENDING',currency:'KZT',provider:{in:['KASSA24','KASSA24_DEMO','ONLINE']}},orderBy:{createdAt:'desc'},take:10});
 for(const row of rows){try{const result=await service.checkTopupPayment(user.id,row.id);console.log(JSON.stringify(result));}catch(_){console.log(JSON.stringify({id:row.id,verificationUnavailable:true}));}}
 const wallet=await p.wallet.findUnique({where:{id:user.wallet.id}});
 console.log(JSON.stringify({balanceAfter:wallet.money,demoCredits:await p.walletTransaction.count({where:{walletId:wallet.id,type:'TOPUP_DEMO_CREDIT'}})}));
})().catch(()=>{console.error('Demo topup operation failed');process.exitCode=1}).finally(()=>p.$disconnect());
JSENABLEDEMO
    ;;
  status)
    if [[ "$TARGET" == "map-upstream" ]]; then
      docker exec -i intercity-backend node <<'JSMAPUPSTREAM'
(async()=>{for(const path of ['0/0/0','16/47806/22234']){try{const r=await fetch('https://tile.openstreetmap.org/'+path+'.png',{headers:{'User-Agent':'InterCity/1.0 (+https://intercity.89-207-255-27.sslip.io)','Accept':'image/png'},signal:AbortSignal.timeout(10000),redirect:'error'});const b=Buffer.from(await r.arrayBuffer());console.log(JSON.stringify({source:'OpenStreetMap',status:r.status,type:r.headers.get('content-type'),bytes:b.length,png:b.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])),cache:r.headers.get('cache-control')}));}catch(e){console.log(JSON.stringify({source:'OpenStreetMap',error:e.name}));process.exitCode=1;}}})();
JSMAPUPSTREAM
      exit 0
    fi
    if [[ "$TARGET" == "map-diagnostics" ]]; then
      cat "$APP_ROOT/current_commit"
      docker exec -i intercity-backend node <<'JSMAPDIAG'
const {PrismaClient}=require('@prisma/client');(async()=>{const p=new PrismaClient();try{await p.$transaction(async tx=>{await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');const where={at:{gte:new Date(Date.now()-86400000)},OR:[{action:{contains:'geo'}},{action:{contains:'route'}},{action:{contains:'map'}},{message:{contains:'GPS',mode:'insensitive'}},{message:{contains:'tile',mode:'insensitive'}}]};console.log(JSON.stringify({counts:await tx.techEvent.groupBy({by:['action','status','result'],where,_count:true}),failures:await tx.techEvent.findMany({where:{AND:[where,{OR:[{status:{gte:400}},{result:'ERROR'}]}]},orderBy:{at:'desc'},take:40,select:{at:true,action:true,status:true,result:true,message:true}})}));},{timeout:30000});}finally{await p.$disconnect()}})().catch(e=>{console.error(e.message);process.exitCode=1});
JSMAPDIAG
      docker logs --since 4h --tail 5000 intercity-backend 2>&1 | grep -Ei 'map|tile|geocod|geo/|route|gps' | tail -40 || true
      exit 0
    fi
    if [[ "$TARGET" == "deploy-progress" ]]; then
      cat "$APP_ROOT/current_commit"
      ps -eo comm,etime,pcpu,pmem | awk 'NR==1 || $1 ~ /^(tar|gzip|docker|scp|node|python3|sshd)$/ {print}'
      find /tmp -maxdepth 2 -name '*1443464*' -printf '%TY-%Tm-%Td %TH:%TM %s %f\n' 2>/dev/null | head -30
      for directory in "$APP_ROOT/releases/1443464baf4105970e49dc6ca4dd7486183de339" "$APP_ROOT"/backups/*1443464*; do
        if [[ -d "$directory" ]]; then du -sh "$directory"; fi
      done
      exit 0
    fi
    if [[ "$TARGET" == "reset-customer-audit" ]]; then
      cat "$APP_ROOT/current_commit"
      compose run --rm -T --no-deps -v /tmp/reset-nonadmin-users.cjs:/tmp/reset-nonadmin-users.cjs:ro backend node /tmp/reset-nonadmin-users.cjs
      exit 0
    fi
    if [[ "$TARGET" == "legal-documents" ]]; then
      cat "$APP_ROOT/current_commit"
      docker exec -i intercity-backend node <<'JSLEGAL'
const {PrismaClient}=require('@prisma/client'),fs=require('fs');
(async()=>{const p=new PrismaClient();try{await p.$transaction(async tx=>{await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');const rows=await tx.appSettings.findMany({where:{OR:['privacy','offer','terms','legal','оферт','соглашен','конфиденц'].map(x=>({key:{contains:x,mode:'insensitive'}}))},select:{key:true,value:true}});console.log(JSON.stringify({legalSettings:rows.map(r=>({key:r.key,value:r.value.slice(0,16000)}))}));});for(const root of [process.env.UPLOAD_DIR||'/app/uploads','/app/public']){if(!fs.existsSync(root))continue;const names=fs.readdirSync(root,{recursive:true}).filter(f=>/privacy|policy|terms|ofert|оферт|соглашен|конфиденц/i.test(f)&&/\.(html?|pdf|txt|docx?)$/i.test(f));console.log(JSON.stringify({publicLegalFiles:names.slice(0,50)}));}}finally{await p.$disconnect()}})().catch(e=>{console.error(e.message);process.exitCode=1});
JSLEGAL
      exit 0
    fi
    if [[ "$TARGET" == "dashboard-rollout" ]]; then
      cat "$APP_ROOT/current_commit"
      docker exec -i intercity-backend node <<'JSROLLOUT'
const {PrismaClient}=require('@prisma/client');
(async()=>{const p=new PrismaClient();try{await p.$transaction(async tx=>{
 await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');
 const keys=['driverTaxIntegrationPaused','kzTaxEnabled','referralCommissionPercent','iosDistributionMode','googlePlayUrl','driverRouteTopPolicy'];
 console.log(JSON.stringify({kind:'rollout-settings',settings:await tx.appSettings.findMany({where:{key:{in:keys}},select:{key:true,value:true}})}));
 console.log(JSON.stringify({kind:'accounting-history',taxEntries:await tx.taxIncomeEntry.count(),referralCredits:await tx.walletTransaction.count({where:{direction:'CREDIT',type:'REFERRAL_INCOME'}}),invitedAccounts:await tx.user.count({where:{referredBy:{not:null}}})}));
 try{const {dashboardStatistics}=require('./dist/src/admin/dashboard-statistics');for(const period of ['24h','today','week','month']){const r=await dashboardStatistics(tx,period);console.log(JSON.stringify({kind:'dashboard-check',period,users:r.users,orders:r.orders,completedInPeriod:r.completedInPeriod,dailyRows:r.daily.length}));}}catch(e){if(e.code==='MODULE_NOT_FOUND')console.log('Dashboard statistics module is not deployed yet');else throw e;}
 },{timeout:30000})}finally{await p.$disconnect()}})().catch(e=>{console.error(e.message);process.exitCode=1});
JSROLLOUT
      exit 0
    fi
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
    if [[ "$TARGET" == "push-errors" ]]; then
      docker logs --since 2h --tail 5000 intercity-backend 2>&1 | grep -E 'Firebase push failed: HTTP [0-9]{3}|Invalid Firebase token removed' | tail -n 30 || true
      exit 0
    fi
    if [[ "$TARGET" == "registration-invite-diagnostics" ]]; then
      docker exec -i intercity-backend node <<'JSREGCHECK'
const {PrismaClient}=require('@prisma/client');(async()=>{const p=new PrismaClient();try{await p.$transaction(async tx=>{await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');const output=[];for(const [source,phone]of [['registration','+77780646779'],['login','+77780676779']]){const u=await tx.user.findUnique({where:{phone},select:{createdAt:true,role:true,blockedAt:true}});output.push({source,exists:!!u,role:u?.role,createdAt:u?.createdAt,blocked:!!u?.blockedAt});}console.log(JSON.stringify({accounts:output}));});}finally{await p.$disconnect()}})().catch(e=>{console.error(e.message);process.exitCode=1});
JSREGCHECK
      exit 0
    fi
    if [[ "$TARGET" == "attention-release-health" ]]; then
      cat "$APP_ROOT/current_commit"
      docker exec -i intercity-backend node <<'JSATTENTIONHEALTH'
const {PrismaClient}=require('@prisma/client');(async()=>{const p=new PrismaClient();try{await p.$transaction(async tx=>{await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');console.log(JSON.stringify({alerts:await tx.adminAttention.groupBy({by:['category','severity'],_count:true}),receipts:{total:await tx.adminAttentionReceipt.count(),pushAccepted:await tx.adminAttentionReceipt.count({where:{pushAt:{not:null}}}),retryPending:await tx.adminAttentionReceipt.count({where:{pushAt:null,lastError:{not:null}}})},recentServerFailures:await tx.techEvent.findMany({where:{at:{gte:new Date(Date.now()-300000)},status:{gte:500}},orderBy:{at:'desc'},take:5,select:{at:true,action:true,status:true,message:true}})}));},{timeout:30000});}finally{await p.$disconnect()}})().catch(e=>{console.error(e.message);process.exitCode=1});
JSATTENTIONHEALTH
      exit 0
    fi
    if [[ "$TARGET" == "intercity-live-offers" ]]; then
      cat "$APP_ROOT/current_commit"
      docker exec -i intercity-backend node <<'JSLIVEOFFERS'
const {PrismaClient}=require('@prisma/client');(async()=>{const p=new PrismaClient();try{await p.$transaction(async tx=>{await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');const people=await tx.user.findMany({where:{OR:[{name:{contains:'Олег',mode:'insensitive'}},{name:{contains:'Анастас',mode:'insensitive'}}]},select:{id:true,name:true,role:true,driverProfile:{select:{id:true,status:true,acceptIntercity:true,intercityRoutes:{select:{fromCity:true,toCity:true,departureAt:true,departureOffsetMinutes:true,isActive:true,seatsAvailable:true}}}}}});const ids=people.map(x=>x.id);const requests=await tx.intercityRequest.findMany({where:{OR:[{passengerId:{in:ids}},{offers:{some:{driverId:{in:ids}}}}]},orderBy:{createdAt:'desc'},take:12,select:{id:true,passengerId:true,createdAt:true,updatedAt:true,requestType:true,status:true,fromCity:true,toCity:true,date:true,seats:true,selectedDriverId:true,offers:{select:{id:true,driverId:true,status:true,price:true,seats:true,createdAt:true,updatedAt:true}}}});const events=await tx.techEvent.findMany({where:{userId:{in:ids},at:{gte:new Date(Date.now()-7200000)},OR:[{action:{contains:'intercity'}},{action:{contains:'offers'}}]},orderBy:{at:'desc'},take:50,select:{at:true,userId:true,action:true,status:true,result:true,message:true,objectId:true}});console.log(JSON.stringify({people,requests,events}));},{timeout:30000});}finally{await p.$disconnect()}})().catch(e=>{console.error(e.message);process.exitCode=1});
JSLIVEOFFERS
      exit 0
    fi
    if [[ "$TARGET" == "identity-video-storage" ]]; then
      cat "$APP_ROOT/current_commit"
      docker exec -i intercity-backend node <<'JSVIDEOSTORAGE'
const {PrismaClient}=require('@prisma/client'),fs=require('fs'),path=require('path');
(async()=>{const p=new PrismaClient();try{await p.$transaction(async tx=>{await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');const users=await tx.user.findMany({where:{role:{not:'ADMIN'},NOT:{phone:{startsWith:'erased:'}}},orderBy:{createdAt:'desc'},take:5,select:{id:true,createdAt:true,biometricProfile:{select:{status:true,referenceVideoPath:true,enrolledAt:true}}}});const root=path.join(process.env.TECH_STORAGE_DIR||path.join(process.cwd(),'technical-data'),'identity');const report=[];for(const u of users){const checks=await tx.biometricChallenge.findMany({where:{userId:u.id},orderBy:{createdAt:'desc'},take:5,select:{id:true,createdAt:true,status:true,purpose:true,consentVersion:true,videoPath:true,reason:true}});report.push({account:u.id.slice(0,8),registered:u.createdAt,profileStatus:u.biometricProfile?.status,enrolledAt:u.biometricProfile?.enrolledAt,referenceVideoStored:!!u.biometricProfile?.referenceVideoPath,referenceFileExists:u.biometricProfile?.referenceVideoPath?fs.existsSync(path.join(root,u.id,u.biometricProfile.referenceVideoPath)):false,attempts:checks.map(c=>({at:c.createdAt,status:c.status,purpose:c.purpose,consent:c.consentVersion,clipStored:!!c.videoPath,clipExists:c.videoPath?fs.existsSync(path.join(root,u.id,c.videoPath)):false,reason:c.reason}))});}const {IdentityService,IDENTITY_CONSENT}=require('./dist/src/identity/identity.service');const visible=await IdentityService.prototype.history.call({prisma:tx},{status:'ALL',take:10});console.log(JSON.stringify({consent:IDENTITY_CONSENT,latestAccounts:report,visible:visible.items.map(c=>({at:c.createdAt,purpose:c.purpose,status:c.status,hasVideo:c.hasVideo,consent:c.consentVersion}))}));},{timeout:30000});}finally{await p.$disconnect()}})().catch(e=>{console.error(e.message);process.exitCode=1});
JSVIDEOSTORAGE
      exit 0
    fi
    if [[ "$TARGET" == "identity-oleg-diagnostics" ]]; then
      cat "$APP_ROOT/current_commit"
      docker exec -i intercity-backend node <<'JSOLEGAUDIT'
const {PrismaClient}=require('@prisma/client'),{IdentityService}=require('./dist/src/identity/identity.service');
(async()=>{const p=new PrismaClient();try{await p.$transaction(async tx=>{await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');const users=await tx.user.findMany({where:{OR:[{name:{contains:'Олег',mode:'insensitive'}},{name:{contains:'Oleg',mode:'insensitive'}}]},select:{id:true,role:true,blockedAt:true,createdAt:true,biometricProfile:{select:{status:true,enrolledAt:true,driverConsent:true,driverDocumentHash:true,vehicleDocumentHash:true,vehicleData:true}},driverProfile:{select:{id:true,status:true,passportUrl:true,driverLicenseUrl:true,techPassportFrontUrl:true,techPassportBackUrl:true,carModel:true,carNumber:true}}},take:10});const report=[];for(const u of users){report.push({account:u.id.slice(0,8),role:u.role,blocked:!!u.blockedAt,createdAt:u.createdAt,driver:!!u.driverProfile,profile:u.biometricProfile?{status:u.biometricProfile.status,enrolledAt:u.biometricProfile.enrolledAt,driverConsent:u.biometricProfile.driverConsent,identityCompared:!!u.biometricProfile.driverDocumentHash,vehicleCompared:!!u.biometricProfile.vehicleDocumentHash,vehicleParsed:!!u.biometricProfile.vehicleData}:null,driverStatus:u.driverProfile?.status,documents:u.driverProfile?{identity:!!u.driverProfile.passportUrl,license:!!u.driverProfile.driverLicenseUrl,vehicleFront:!!u.driverProfile.techPassportFrontUrl,vehicleBack:!!u.driverProfile.techPassportBackUrl,carEntered:!!u.driverProfile.carModel&&!!u.driverProfile.carNumber}:null,documentsRequired:await IdentityService.prototype.driverDocumentsRequired.call({prisma:tx},u.id,tx),attempts:await tx.biometricChallenge.findMany({where:{userId:u.id},orderBy:{createdAt:'desc'},take:15,select:{purpose:true,status:true,reason:true,createdAt:true,claimedAt:true,attempts:true}})});}console.log(JSON.stringify({matchedAccounts:users.length,accounts:report}));},{timeout:30000});}finally{await p.$disconnect()}})().catch(e=>{console.error(e.message);process.exitCode=1});
JSOLEGAUDIT
      exit 0
    fi
    if [[ "$TARGET" == "identity-recovery-diagnostics" ]]; then
      cat "$APP_ROOT/current_commit"
      docker exec -i intercity-backend node <<'JSRECOVERY'
const {PrismaClient}=require('@prisma/client'),{IdentityVault}=require('./dist/src/identity/identity-vault'),{similarity}=require('./dist/src/identity/identity.service'),fs=require('fs');
(async()=>{const p=new PrismaClient(),vault=new IdentityVault();try{if(!fs.existsSync(vault.root+'/key.bin'))throw Error('Identity key must already exist');await vault.init();await p.$transaction(async tx=>{await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');const rows=await tx.biometricChallenge.findMany({where:{purpose:'RECOVERY'},orderBy:{createdAt:'desc'},take:10});const report=[];for(const c of rows){const ref=c.userId?await tx.biometricProfile.findUnique({where:{userId:c.userId}}):null;let score=null;if(ref&&c.candidate){score=Math.round(similarity(JSON.parse(vault.open(Buffer.from(ref.template,'base64'),c.userId)),JSON.parse(vault.open(Buffer.from(c.candidate,'base64'),c.userId)))*1000)/1000;}report.push({at:c.createdAt,status:c.status,reason:c.reason,modelMatch:ref?ref.model===c.model:null,score,hasReferenceVideo:!!ref?.referenceVideoPath});}console.log(JSON.stringify({recoveries:report}));},{timeout:30000});}finally{await p.$disconnect()}})().catch(e=>{console.error(e.message);process.exitCode=1});
JSRECOVERY
      exit 0
    fi
    if [[ "$TARGET" == "identity-permissions" ]]; then
      docker exec -i intercity-backend node <<'JSPERMISSIONS'
const {PrismaClient}=require('@prisma/client');(async()=>{const p=new PrismaClient();try{await p.$transaction(async tx=>{await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');console.log(JSON.stringify({admins:await tx.user.count({where:{role:'ADMIN'}}),roles:await tx.adminRole.findMany({select:{code:true,_count:{select:{users:true}}}})}));});}finally{await p.$disconnect()}})().catch(e=>{console.error(e.message);process.exitCode=1});
JSPERMISSIONS
      exit 0
    fi
    if [[ "$TARGET" == "identity-verification" ]]; then
      cat "$APP_ROOT/current_commit"
      docker exec -i intercity-backend node <<'JSIDENTITY'
const {PrismaClient}=require('@prisma/client'),fs=require('fs');
(async()=>{const p=new PrismaClient();try{await p.$transaction(async tx=>{await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');console.log(JSON.stringify({enabled:(await tx.appSettings.findUnique({where:{key:'identityVerificationEnabled'},select:{value:true}}))?.value==='true',profiles:await tx.biometricProfile.count(),profilesWithReferenceVideo:await tx.biometricProfile.count({where:{referenceVideoPath:{not:null}}}),pendingReviews:await tx.biometricChallenge.count({where:{status:'REVIEW'}}),enrollmentReviews:await tx.biometricChallenge.count({where:{purpose:'ENROLL',status:'REVIEW'}}),eligiblePushUsers:await tx.user.count({where:{blockedAt:null,pushToken:{not:null}}}),adminPushDevices:await tx.adminWebPushSubscription.count(),administrativeRoles:await tx.adminUserRole.groupBy({by:['roleId'],_count:true}),permissionPresent:!!await tx.adminPermission.findUnique({where:{key:'identity.review'},select:{id:true}})}));});const root=process.env.TECH_STORAGE_DIR||'/app/technical-data';console.log(JSON.stringify({identityKeyPresent:fs.existsSync(root+'/identity/key.bin'),adminPushKeyPresent:fs.existsSync(root+'/admin-webpush.json')}));const r=await fetch('http://identity:8080/health',{signal:AbortSignal.timeout(10000)});const h=await r.json();console.log(JSON.stringify({engineReady:h.ready,liveness:h.liveness,externalServices:h.externalServices,model:h.model}));if(!h.ready||!h.liveness||h.externalServices!==false)process.exitCode=1;}finally{await p.$disconnect()}})().catch(e=>{console.error(e.message);process.exitCode=1});
JSIDENTITY
      exit 0
    fi
    if [[ "$TARGET" == "notification-dispatch" ]]; then
      cat "$APP_ROOT/current_commit"
      docker exec -i intercity-backend node <<'JSDISPATCH'
const {PrismaClient}=require('@prisma/client');
(async()=>{const p=new PrismaClient();try{await p.$transaction(async tx=>{await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');console.log(JSON.stringify({jobs:await tx.notificationDispatchJob.findMany({orderBy:{queuedAt:'desc'},take:10,select:{id:true,status:true,successCount:true,failCount:true,lastError:true,queuedAt:true,finishedAt:true}}),eligibleUsers:await tx.user.count({where:{blockedAt:null,pushToken:{not:null}}}),platforms:await tx.user.groupBy({by:['pushPlatform'],where:{blockedAt:null,pushToken:{not:null}},_count:true})}));});}finally{await p.$disconnect()}})().catch(e=>{console.error(e.message);process.exitCode=1});
JSDISPATCH
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
   if(t.status==='PENDING'&&t.currency==='KZT'&&['KASSA24','KASSA24_DEMO','ONLINE'].includes(t.provider)){
    try{const state=await gateway.status(t.id);console.log(JSON.stringify({id:t.id,bankStatus:state?.status,bankNotFound:!!state?.notFound,bankDemo:state?.demo,confirmedLive:!!confirmedPayment(state,t.id,t.amount,login,false),confirmedTest:!!confirmedPayment(state,t.id,t.amount,login,true)}));}catch(_){console.log(JSON.stringify({id:t.id,bankStatusUnavailable:true}));}
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
