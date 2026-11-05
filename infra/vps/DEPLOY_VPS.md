# INTERCITY VPS Deploy

Подготовлено для переноса backend с Google Cloud на обычный VPS без изменения логики приложения.

## 1. Сервер

Минимум: Ubuntu 22.04/24.04, 2 CPU, 4 GB RAM, 40 GB SSD.

Установить Docker:

```bash
sudo apt update
sudo apt install -y ca-certificates curl git
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

Перезайти по SSH после `usermod`.

## 2. DNS

Создать A-запись:

```text
api.example.com -> IP_VPS
```

Порты `80` и `443` должны быть открыты.

## 3. Файлы на сервере

```bash
sudo mkdir -p /opt/intercity
sudo chown -R $USER:$USER /opt/intercity
cd /opt/intercity
```

Скопировать проект на сервер, затем:

```bash
cp infra/vps/.env.example infra/vps/.env
nano infra/vps/.env
```

Обязательно заменить:

- `API_DOMAIN`
- `PUBLIC_WEB_URL`
- `POSTGRES_PASSWORD`
- `DATABASE_URL`
- `JWT_SECRET`
- `JWT_REFRESH_SECRET`
- `BACKEND_PUBLIC_URL`
- `PUBLIC_API_URL`
- платежные и push-переменные, если используются

## 4. Запуск

```bash
cd /opt/intercity/infra/vps
docker compose -f docker-compose.prod.yml up -d --build
```

Первичная синхронизация схемы БД:

```bash
docker compose -f docker-compose.prod.yml exec backend npx prisma db push
```

Опционально заполнить базовые данные:

```bash
docker cp bootstrap-production-data.js intercity-backend:/tmp/bootstrap-production-data.js
docker compose -f docker-compose.prod.yml exec -e NODE_PATH=/app/node_modules backend node /tmp/bootstrap-production-data.js
```

## 5. Проверка

```bash
curl -i https://api.example.com/health
curl -i https://api.example.com/api/realtime/health
```

Swagger:

```text
https://api.example.com/api/docs
```

## 6. Пересборка приложений под новый API

Web / Android / iOS собирать с новым API URL:

```bash
--dart-define=INTERCITY_API_BASE_URL=https://api.example.com/api
--dart-define=INTERCITY_PUBLIC_WEB_URL=https://app.example.com
```

Важно: если приложение уже было собрано со старым URL, его нужно пересобрать.

## 7. Бэкап БД

```bash
docker compose -f docker-compose.prod.yml exec postgres pg_dump -U intercity intercity > intercity_backup.sql
```

Восстановление:

```bash
cat intercity_backup.sql | docker compose -f docker-compose.prod.yml exec -T postgres psql -U intercity intercity
```

### Private road routing (existing VPS)

The release bundles checksum-pinned BRouter 1.7.10 (MIT) and the car-fast-nocost
profile. The installer verifies `services/routing/segments-manifest.json`, free
RAM and disk reserve, then downloads about 1.53 GB of preprocessed OSM graph
segments sequentially into `shared/brouter/segments4`. No public demo router is
used. Do not delete this shared directory when retiring application releases.

The internal `routing` container has no published port, 640 MiB memory and one
CPU limit. Backend uses `BROUTER_URL=http://routing:17777`. Public OSRM fallbacks
remain disabled unless separately permitted. Deployment verifies a real car
route before accepting the release. Maps/addresses still use OSM tiles/Photon.

To update the road snapshot, regenerate and review the segment sizes and hashes
from the official download source, test the pinned runtime with the new files,
then deploy. Do not bypass checksum failures or overwrite the manifest on the
server. Very long routes, disconnected roads and high concurrency can exceed the
bounded CPU/time budget; no straight-line fare fallback is allowed.
