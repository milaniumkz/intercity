#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="${APP_ROOT:-/opt/intercity}"
BUNDLE_PATH="${1:?Usage: vps_deploy_release.sh bundle.tar.gz commit_sha}"
COMMIT_SHA="${2:?commit sha is required}"
GEOCODER_CONFIG="${3:-}"
[[ "$COMMIT_SHA" =~ ^[a-f0-9]{40}$ ]] || { echo 'Invalid release commit' >&2; exit 1; }
[[ -z "$GEOCODER_CONFIG" || "$GEOCODER_CONFIG" == "/tmp/intercity-yandex-$COMMIT_SHA.json" ]] || { echo 'Invalid geocoder configuration path' >&2; exit 1; }
trap 'if [[ -n "$GEOCODER_CONFIG" ]]; then rm -f "$GEOCODER_CONFIG"; fi' EXIT
RELEASE_DIR="$APP_ROOT/releases/$COMMIT_SHA"
SHARED_DIR="$APP_ROOT/shared"
BACKUP_DIR="$APP_ROOT/backups/$(date +%Y%m%d-%H%M%S)-$COMMIT_SHA"
PREVIOUS_RELEASE="$(readlink -f "$APP_ROOT/current")"
[[ -d "$PREVIOUS_RELEASE" && -f "$SHARED_DIR/.env" ]] || { echo 'Current release or shared environment is missing' >&2; exit 1; }
[[ ! -e "$RELEASE_DIR" ]] || { echo 'Release directory already exists; refusing to overwrite it' >&2; exit 1; }
PROJECT_NAME="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' intercity-postgres)"
[[ -n "$PROJECT_NAME" ]] || { echo 'Cannot identify the existing database Compose project' >&2; exit 1; }
PREVIOUS_IMAGE="$(docker inspect --format '{{.Image}}' intercity-backend)"

mkdir -p "$RELEASE_DIR"
tar -xzf "$BUNDLE_PATH" -C "$RELEASE_DIR" --strip-components=1
python3 "$RELEASE_DIR/scripts/vps_release_manifest.py" check \
  "$RELEASE_DIR/.release-manifest.json" "$PREVIOUS_RELEASE" "$COMMIT_SHA"

# Keep backups on the VPS; never include runtime secrets in the release bundle.
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
cp "$SHARED_DIR/.env" "$BACKUP_DIR/env.backup"
chmod 600 "$BACKUP_DIR/env.backup"
printf '%s\n' "$PREVIOUS_RELEASE" > "$BACKUP_DIR/previous-release"
docker exec intercity-postgres sh -c 'exec pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$BACKUP_DIR/postgres.sql"
test -s "$BACKUP_DIR/postgres.sql"
rg_footer='PostgreSQL database dump complete'
grep -q "$rg_footer" "$BACKUP_DIR/postgres.sql"
tar -C "$SHARED_DIR" -czf "$BACKUP_DIR/uploads.tar.gz" uploads
tar -tzf "$BACKUP_DIR/uploads.tar.gz" >/dev/null
printf 'Verified database and uploads backups: %s\n' "$BACKUP_DIR"

cp "$SHARED_DIR/.env" "$RELEASE_DIR/infra/vps/.env"
chmod 600 "$RELEASE_DIR/infra/vps/.env"
ln -s "$SHARED_DIR/uploads" "$RELEASE_DIR/uploads"

compose() {
  docker compose -p "$PROJECT_NAME" -f docker-compose.prod.yml "$@"
}

env_changed=0
switch_started=0
response_file=""
rollback_on_failure() {
  status=$?
  trap - EXIT
  if [[ -n "$GEOCODER_CONFIG" ]]; then rm -f "$GEOCODER_CONFIG"; fi
  if [[ "$status" -ne 0 && "$env_changed" -eq 1 ]]; then cp "$BACKUP_DIR/env.backup" "$SHARED_DIR/.env"; fi
  if [[ -n "$response_file" ]]; then rm -f "$response_file"; fi
  if [[ "$status" -ne 0 && "$switch_started" -eq 1 ]]; then
    echo 'Release health check failed; restoring the previous application release' >&2
    docker tag "$PREVIOUS_IMAGE" intercity-backend:prod
    cd "$PREVIOUS_RELEASE/infra/vps"
    compose up -d --no-build backend caddy
    ln -sfn "$PREVIOUS_RELEASE" "$APP_ROOT/current"
  fi
  exit "$status"
}
trap rollback_on_failure EXIT

# Optional credential is transported separately, never bundled or printed.
if [[ -n "$GEOCODER_CONFIG" && -f "$GEOCODER_CONFIG" ]]; then
  env_changed=1
  python3 - "$GEOCODER_CONFIG" "$SHARED_DIR/.env" <<'PYKEY'
import json, os, re, sys
from pathlib import Path
key = json.loads(Path(sys.argv[1]).read_text()).get('key', '').strip()
if not re.fullmatch(r'[a-zA-Z0-9._-]{10,250}', key):
    raise SystemExit('Invalid geocoder credential format')
path = Path(sys.argv[2]); lines = path.read_text().splitlines()
lines = [line for line in lines if not re.match(r'^\s*YANDEX_GEOCODER_API_KEY\s*=', line)]
temporary = path.with_suffix('.geocoder.tmp')
fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w') as file:
    file.write('\n'.join(lines) + '\nYANDEX_GEOCODER_API_KEY=' + key + '\n')
os.replace(temporary, path)
PYKEY
  cp "$SHARED_DIR/.env" "$RELEASE_DIR/infra/vps/.env"
  chmod 600 "$RELEASE_DIR/infra/vps/.env"
  rm -f "$GEOCODER_CONFIG"
  echo 'Geocoder credential configured'
fi

cd "$RELEASE_DIR/infra/vps"
# Build while the previous backend continues running. Additive migrations run
# before the new application starts; never fall back to an unrestricted db push.
compose build backend
compose run --rm --no-deps backend npx prisma migrate deploy
compose run --rm --no-deps backend node dist/src/geo/import-city-catalog.js
switch_started=1
compose up -d --no-build backend caddy

# /health is a Caddy response. Verify an actual API/database request as well.
response_file="$(mktemp)"
curl -fsS --retry 20 --retry-delay 2 --retry-all-errors --max-time 10 \
  https://api.intercity.89-207-255-27.sslip.io/api/geo/cities > "$response_file"
python3 - "$response_file" <<'PY'
import json, sys
assert isinstance(json.load(open(sys.argv[1])), list), 'Invalid cities API response'
PY
for site in intercity.89-207-255-27.sslip.io admin.intercity.89-207-255-27.sslip.io; do
  curl -fsS --retry 10 --retry-delay 2 --retry-all-errors --max-time 10 \
    "https://$site/version.json" > "$response_file"
  python3 - "$response_file" "$COMMIT_SHA" <<'PY'
import json, sys
assert json.load(open(sys.argv[1]))['commit'] == sys.argv[2], 'Wrong published web release'
PY
done
ln -sfn "$RELEASE_DIR" "$APP_ROOT/current"
printf '%s\n' "$COMMIT_SHA" > "$APP_ROOT/current_commit"
compose ps
printf 'Published and verified release: %s\n' "$COMMIT_SHA"
