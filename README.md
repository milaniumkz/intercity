# 🚀 INTERCITY - Ride Sharing Platform

Full-stack ride-sharing platform with Flutter mobile app, Flutter web admin panel, and NestJS backend.

## 📁 Project Structure

```
INTERCITY/
├── apps/
│   ├── mobile_flutter/     # Flutter Mobile App (Russian/Kazakh)
│   └── admin_web/          # Flutter Web Admin Panel
├── packages/
│   ├── intercity_shared/           # Shared Flutter config + value objects
│   ├── flutter_secure_storage_native/ # Native-only secure storage fork
│   └── flutter_tts_native/         # Native-only TTS fork
├── backend/                # NestJS Backend API
│   ├── src/
│   │   ├── auth/          # JWT auth with refresh tokens
│   │   ├── geo/           # Nominatim + OSRM
│   │   ├── orders/        # Auto-dispatch service
│   │   ├── driver/
│   │   ├── intercity/     # Intercity requests/offers
│   │   ├── ridesharing/   # Ride sharing trips
│   │   ├── wallet/        # Topups & payouts
│   │   └── admin/         # Admin panel API
│   └── prisma/           # Database schema + seed
├── infra/                  # Docker & Cloud Run
└── README.md
```

## 🛠 Tech Stack

- **Backend**: Node.js 20, NestJS, PostgreSQL, Prisma ORM
- **Mobile**: Flutter 3.x, Riverpod, flutter_map (OSM)
- **Auth**: JWT access + refresh tokens

## 🚀 Quick Start (Local)

### Backend
```bash
cd backend
npm install
npx prisma generate
npx prisma db push
npm run prisma:seed
npm run start:dev
```

### Docker
```bash
cd infra
docker-compose up -d
```

---

## ☁️ Deploy to Google Cloud Run

### 1. Prerequisites
- Google Cloud Platform account
- Cloud SQL (PostgreSQL) instance
- gcloud CLI installed

### 2. Set Environment
```bash
export PROJECT_ID="your-project-id"
export DATABASE_URL="postgresql://user:pass@/cloudsql/project:region:instance"
export JWT_SECRET="your-secret-key"
export JWT_REFRESH_SECRET="your-refresh-secret"
export CORS_ORIGINS="https://admin.example.com,https://app.example.com"
```

### 3. Deploy (Choose one)

#### Option A: Deploy Script
```bash
chmod +x infra/deploy.sh
./infra/deploy.sh $PROJECT_ID
```

#### Option B: Cloud Build
```bash
gcloud builds submit --config=infra/cloudbuild.yaml \
  --substitutions _DATABASE_URL="$DATABASE_URL",_JWT_SECRET="$JWT_SECRET"
```

### 4. Get API URL
```bash
gcloud run services describe intercity-backend \
  --platform managed --region us-central1 \
  --format 'value(status.url)'
```

---

## 📱 Mobile App - Languages

Supported languages: **Russian** (Русский), **Kazakh** (Қазақша)

Default: Russian

Switch language via [`LocalizationService`](apps/mobile_flutter/lib/core/utils/localization_service.dart)

---

## Flutter App Configuration

### Валюта поездок и городские тарифы

- Страна города хранится в `City.countryCode`: `RU` — рубли (`RUB`, ₽), `KZ` — тенге (`KZT`, ₸).
- В админке выберите страну в разделе «Города». В «Тарифах» выберите город и задайте базовую стоимость, цену за км, за минуту и минимум в валюте этого города. Нажмите строку тарифа для редактирования.
- Для городских поездок используются только активные тарифы города отправления. Если своего тарифа нет, чужой тариф не подставляется.
- Межгород, включая Россия ↔ Казахстан, использует валюту города отправления. Валюта сохраняется в заказе/заявке/поездке и не меняется при редактировании города. Числовые суммы не конвертируются автоматически.
- Кошельки имеют независимые денежные и бонусные балансы KZT/RUB. Старые балансы остаются в KZT; новые RUB-балансы начинаются с нуля. В приложении выберите «Тенге» или «Рубли». Оплата бонусами, комиссии, переводы и возвраты используют валюту операции. Автоматической конвертации нет.
- Онлайн-платежи Kassa24 используются только для KZT; рублёвые заявки на пополнение/вывод обрабатываются администратором вручную.
- Для RUB доступны отдельные настройки `driverMinOnlineBalanceRub`, `minPayoutAmountRub`, `intercityCommissionByDistanceKmRub`, `intercityAcceptedRequestFeeRub`. Городская комиссия использует общий процент; межгородская комиссия RUB задаётся отдельно и до настройки равна нулю. Настроенная комиссия списывается на этапах принятия и завершения согласно существующей модели комиссий. Настройки KZT не применяются к RUB.

Перед запуском новой версии примените миграции `20261006120000_ride_currency` и `20261006130000_wallet_currency` через обычный процесс миграций БД. Она заполняет страну известных российских городов и валюту существующих поездок без изменения сумм. Проверьте страну остальных существующих городов в админке; заново задавать валюту у каждой поездки не нужно.

Проверка backend: `cd backend && npm run test:currency`. Интеграционная проверка БД запускается только с `CURRENCY_TEST_DATABASE_URL`, указывающим на отдельную локальную БД `intercity_currency_test`; обычная команда эту проверку пропускает. Проверку SQL миграции `backend/test/ride-currency-migration.sql` выполняйте только в отдельной пустой тестовой БД.

Both Flutter apps now resolve API base URL through the same environment variable:

```bash
export INTERCITY_API_BASE_URL="https://your-api-host.example/api"
```

- `apps/mobile_flutter`
- `apps/admin_web`

If the variable is not set, both apps fall back to the same safe placeholder:

```text
https://api.intercity.invalid/api
```

That placeholder is intentional. Real environments should always provide
`INTERCITY_API_BASE_URL` explicitly instead of relying on fallback behavior.

---

## Android Release Signing

`apps/mobile_flutter` release builds no longer use debug signing. Provide release
credentials through environment variables before the release wrapper or raw
Flutter Android builds:

```bash
export INTERCITY_ANDROID_RELEASE_KEYSTORE_PATH="/absolute/path/to/release.keystore"
export INTERCITY_ANDROID_RELEASE_STORE_PASSWORD="..."
export INTERCITY_ANDROID_RELEASE_KEY_ALIAS="..."
export INTERCITY_ANDROID_RELEASE_KEY_PASSWORD="..."
```

CI/manual workflows can provide the keystore as base64 instead of a file path:

```bash
export INTERCITY_ANDROID_RELEASE_KEYSTORE_BASE64="base64-encoded-keystore"
```

For GitHub Actions manual release builds, configure these repository secrets:

- `INTERCITY_ANDROID_RELEASE_KEYSTORE_BASE64`
- `INTERCITY_ANDROID_RELEASE_STORE_PASSWORD`
- `INTERCITY_ANDROID_RELEASE_KEY_ALIAS`
- `INTERCITY_ANDROID_RELEASE_KEY_PASSWORD`

Release builds also enable `minify` and `shrinkResources`, so signing config must
be valid before producing production artifacts.

---

## Repository Hygiene

- Do not commit local outputs such as `build/`, `.dart_tool/`, `Pods/`, or
  `android/local.properties`.
- Do not commit Android signing material such as `*.jks`, `*.keystore`, or
  `android/key.properties`.
- `apps/mobile_flutter/web_deploy/` should be treated as a generated web release
  output, not as a hand-maintained source directory.
- Generated deploy/build artifacts should be reproducible from source and CI; they
  should not be hand-edited in version control.
- Avoid committing regenerated platform artifacts unless the change is intentional
  and reviewed.

For reproducible mobile web deploy artifacts, rebuild them explicitly:

```bash
bash scripts/build_mobile_web_deploy.sh
docker build -f apps/mobile_flutter/deploy/web.Dockerfile \
  -t intercity-mobile-web apps/mobile_flutter/web_deploy
```

For reproducible Flutter verification across both apps:

```bash
bash scripts/verify_flutter_apps.sh
```

For a live production API smoke run with fresh `QA_TEST_*` accounts:

```bash
bash scripts/smoke_prod_core.sh
CLEANUP_USERS=1 bash scripts/smoke_prod_core.sh
```

With `CLEANUP_USERS=1`, the smoke script first attempts admin safe-delete for
fresh `QA_TEST_*` users and falls back to admin-side anonymization if legacy
production relations prevent a hard delete.

To clean older production `QA_TEST_*` accounts in batch:

```bash
bash scripts/cleanup_prod_qa_users.sh
DRY_RUN=1 bash scripts/cleanup_prod_qa_users.sh
```

For Android release preflight verification:

```bash
bash scripts/verify_release_readiness.sh
```

For a reproducible Android release build wrapper:

```bash
bash scripts/build_mobile_android_release.sh
```

The wrapper is the canonical entrypoint. It runs preflight first and also
recovers from a known Flutter false-negative on machines where Android
`cmdline-tools/apkanalyzer` are missing but the `.aab` already contains
`BUNDLE-METADATA` debug symbols.

## GitHub, Codex Cloud, CI/CD

Main branch: `main`.

Production VPS:

- Web: `https://intercity.89-207-255-27.sslip.io`
- API: `https://api.intercity.89-207-255-27.sslip.io/api`
- Admin: `https://admin.intercity.89-207-255-27.sslip.io`

GitHub Actions:

- `Backend CI` builds NestJS and Prisma.
- `Flutter Verify` analyzes/tests/builds mobile and admin Flutter apps.
- `Mobile Android Release` builds signed Android artifacts only by manual run.
- `Deploy VPS` builds a release bundle and deploys a checked commit to the VPS.
- `VPS Ops` provides limited manual operations: status, logs, restart, redeploy current, rollback.

Required repository secrets for deploy:

```text
INTERCITY_API_BASE_URL=https://api.intercity.89-207-255-27.sslip.io/api
INTERCITY_FIREBASE_WEB_VAPID_KEY=
INTERCITY_API_HEALTH_URL=https://api.intercity.89-207-255-27.sslip.io/health
VPS_HOST=89.207.255.27
VPS_USER=root
VPS_SSH_PRIVATE_KEY=<deploy key>
VPS_KNOWN_HOSTS=<ssh-keyscan output for the server>
```

Server runtime secrets stay on the VPS in:

```text
/opt/intercity/shared/.env
```

They are copied into each release during deploy and must not be committed.

Codex Cloud setup after GitHub push:

1. Open Codex Cloud and connect GitHub repository `milaniumkz/intercity`.
2. Use branch `main`.
3. Configure setup command:
   ```bash
   cd backend && npm ci && npx prisma generate
   cd ../apps/mobile_flutter && flutter pub get
   cd ../admin_web && flutter pub get
   ```
4. Use a separate test database/env for cloud development, not production.

Deploy flow:

```bash
git checkout -b feature/name
git commit -m "..."
git push -u origin feature/name
```

Open a Pull Request. After checks pass and PR is merged to `main`, `Deploy VPS`
updates production. Manual deploy is available from GitHub Actions.

Rollback:

Run `VPS Ops` with:

```text
action=rollback
target=<previous commit sha from /opt/intercity/releases>
```

Data locations on VPS:

- PostgreSQL: Docker volume `postgres_data`.
- User uploads: `/opt/intercity/shared/uploads`.
- Backups created before deploy: `/opt/intercity/backups`.

GitHub Actions release automation lives in
`.github/workflows/mobile_android_release.yml`.

Optional toggles:

```bash
RUN_MACOS_SMOKE=0 bash scripts/verify_flutter_apps.sh
VERIFY_ADMIN=0 bash scripts/verify_flutter_apps.sh
bash scripts/smoke_prod_core.sh
ALLOW_MISSING_SIGNING=1 bash scripts/verify_release_readiness.sh
RUN_APPBUNDLE_BUILD=1 bash scripts/verify_release_readiness.sh
RELEASE_TARGET=apk bash scripts/build_mobile_android_release.sh
RUN_FLUTTER_BUILD=0 ALLOW_MISSING_SIGNING=1 bash scripts/build_mobile_android_release.sh
```

CI uses the same entrypoint through `.github/workflows/flutter_verify.yml`, so
local and hosted verification stay aligned.

---

## 🔑 Admin Credentials

After seeding:
- **Phone**: +7 000 000 00 00
- **Password**: 123456

---

## 📄 API Documentation

Swagger UI available at: `/api/docs`

### Key Endpoints
- `POST /api/auth/register` - Register
- `POST /api/auth/login` - Login
- `POST /api/orders` - Create order
- `POST /api/driver/location` - Update driver location
- `POST /api/driver/online` - Set online status
- `GET /api/admin/orders/:id/events` - Timeline событий по заказу
- `GET /api/realtime/orders/:id/stream` - SSE поток событий по заказу
- `GET /api/realtime/driver/me/stream` - SSE поток событий текущего водителя

---

## Security Notes

- `JWT_SECRET` and `JWT_REFRESH_SECRET` are mandatory in production.
- Restrict CORS in production via `CORS_ORIGINS` (comma-separated list).
- For DB schema updates (including `RideEvent`), run:
  - `npx prisma generate`
  - `npx prisma db push` (or migrations in your CI/CD flow)

---

## License

MIT
