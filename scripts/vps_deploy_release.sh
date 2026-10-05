#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="${APP_ROOT:-/opt/intercity}"
BUNDLE_PATH="${1:?Usage: vps_deploy_release.sh /tmp/intercity-vps-commit.tar.gz commit_sha}"
COMMIT_SHA="${2:?commit sha is required}"
RELEASE_DIR="$APP_ROOT/releases/$COMMIT_SHA"
SHARED_DIR="$APP_ROOT/shared"
BACKUP_DIR="$APP_ROOT/backups/$(date +%Y%m%d-%H%M%S)-$COMMIT_SHA"

mkdir -p "$APP_ROOT/releases" "$SHARED_DIR/uploads" "$APP_ROOT/backups"

if [[ -d "$RELEASE_DIR" ]]; then
  rm -rf "$RELEASE_DIR"
fi
mkdir -p "$RELEASE_DIR"
tar -xzf "$BUNDLE_PATH" -C "$RELEASE_DIR" --strip-components=1

if [[ -f "$APP_ROOT/infra/vps/.env" && ! -f "$SHARED_DIR/.env" ]]; then
  cp "$APP_ROOT/infra/vps/.env" "$SHARED_DIR/.env"
fi
if [[ ! -f "$SHARED_DIR/.env" ]]; then
  echo "Missing $SHARED_DIR/.env. Create it from infra/vps/.env.example first." >&2
  exit 1
fi
cp "$SHARED_DIR/.env" "$RELEASE_DIR/infra/vps/.env"
ln -sfn "$SHARED_DIR/uploads" "$RELEASE_DIR/uploads"

mkdir -p "$BACKUP_DIR"
cp "$SHARED_DIR/.env" "$BACKUP_DIR/env.backup"
if docker ps --format '{{.Names}}' | grep -qx intercity-postgres; then
  docker exec intercity-postgres pg_dump \
    -U "$(grep '^POSTGRES_USER=' "$SHARED_DIR/.env" | cut -d= -f2-)" \
    "$(grep '^POSTGRES_DB=' "$SHARED_DIR/.env" | cut -d= -f2-)" \
    > "$BACKUP_DIR/postgres.sql" || true
fi
if [[ -d "$SHARED_DIR/uploads" ]]; then
  tar -C "$SHARED_DIR" -czf "$BACKUP_DIR/uploads.tar.gz" uploads || true
fi

cd "$RELEASE_DIR/infra/vps"
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml exec -T backend npx prisma migrate deploy || \
  docker compose -f docker-compose.prod.yml exec -T backend npx prisma db push

ln -sfn "$RELEASE_DIR" "$APP_ROOT/current"
printf '%s\n' "$COMMIT_SHA" > "$APP_ROOT/current_commit"
docker compose -f docker-compose.prod.yml ps
