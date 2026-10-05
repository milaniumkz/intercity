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
