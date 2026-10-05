[mcp_servers.figma]
url = "https://mcp.figma.com/mcp"

отвечай коротко и понятно

Всегда применяй навык `limit-efficient-quality`: максимально экономь лимиты токенов, инструментов, времени и контекста, но не снижай качество результата.

## Проект

- `backend/` — NestJS API, Prisma, PostgreSQL.
- `apps/mobile_flutter/` — пассажир/водитель Flutter app + web build.
- `apps/admin_web/` — Flutter web админка.
- `packages/` — локальные Flutter packages.
- `infra/vps/` — production Docker Compose + Caddy для VPS.

## Проверки

```bash
cd backend && npm ci && npm run build
cd apps/mobile_flutter && flutter pub get && flutter analyze && flutter test
cd apps/admin_web && flutter pub get && flutter analyze && flutter test
```

Быстрая Flutter-проверка:

```bash
bash scripts/verify_flutter_apps.sh
```

## Деплой

Production запускается через `infra/vps/docker-compose.prod.yml`.
База хранится в Docker volume `postgres_data`, пользовательские файлы — в `uploads/`.
Не коммитить `.env`, ключи подписи, дампы БД, `output/`, `uploads/`, `node_modules/`, `build/`.

Перед изменением production нужно сравнить сервер с локальной версией и сделать backup.
