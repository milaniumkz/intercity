# Load test 1000 concurrent users

## Что подготовлено
- Скрипт: `backend/scripts/load-test-1000.js`
- npm команда: `npm run load:test:1000`
- Тестовые сценарии:
  1. `POST /auth/login` (1000 concurrent)
  2. `GET /me` (1000 concurrent)
  3. `GET /admin/collections/User` (1000 concurrent)

## Внесенные изменения стабильности
- Глобальный throttling сделал настраиваемым через env:
  - `THROTTLE_TTL_MS` (default `60000`)
  - `THROTTLE_LIMIT` (default `1500`)
- Оптимизация refresh token:
  - при выдаче нового токена удаляются старые токены пользователя,
  - добавлен индекс на `RefreshToken.userId`.
- Генерация `refCode` теперь устойчивее при высокой параллельности (retry + fallback).

## Как запускать у себя
1. Поднять Postgres и backend.
2. Выполнить:
   - `cd backend`
   - `npx prisma generate`
   - `npx prisma db push`
   - `npm run prisma:seed`
   - `THROTTLE_LIMIT=1500 npm run start:dev`
3. В другом терминале:
   - `cd backend`
   - `API_URL=http://localhost:3000/api LOAD_USERS=1000 npm run load:test:1000`

## Минимальные целевые SLA для стабильности
- Success rate >= 99.0%
- p95 < 1000ms
- p99 < 2000ms
- 0 падений процесса backend

## Если видите 429
- Увеличить `THROTTLE_LIMIT` (например `2000`) для нагрузочного профиля.
- Для production оставить профиль безопасности и вынести балансировку/лимиты на edge.
