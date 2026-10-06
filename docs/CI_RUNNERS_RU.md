# InterCity CI на Mac

Base: `b6ae1d7500b22ae6da04cb8bedcea00e80572b54`. Исходный cumulative patch проверен по SHA-256 `1c74a5063b5a7019ae5b275e221e7311ea11fb3b7bac5e56b180ed50e0ca32ed` и применён в отдельной ветке. Новые коммиты remote не перезаписывались.

## Переключаемые gates

| Workflow/job | Trusted push main/master | Pull request |
|---|---|---|
| Backend CI / Build backend | Mac: install, Prisma generate, build, unit | Ubuntu: прежние команды |
| Flutter Verify / Analyze, test, and web-build both apps | Mac: selector, analyze, unit, web для затронутых apps | Ubuntu: те же проверки |
| Flutter Verify / macOS smoke test for mobile app | Mac, после успешного Flutter gate | hosted macOS, после успешного Flutter gate |
| Native macOS Verify | Только ручной dispatch, полный native прогон | Не запускается автоматически |

Имена существующих checks сохранены. Path selector включает обе apps при неизвестном baseline. Его ошибка завершает gate ошибкой; admin-only изменения не запускают mobile smoke. Backend workflow-level paths сохранены.

Runner labels должны быть ровно `milanium-mac-arm64` + `repo-intercity`: стандартные labels намеренно отключены при регистрации. Добавлять self-hosted/macOS/ARM64 в runs-on нельзя: такой job останется queued.

## Toolchain и выполнение

Mac: Apple M1, 8 GB RAM, macOS 26.0.1, Xcode 26.0.1, CocoaPods 1.16.2. Установленные Node20.20.2 и Flutter3.41.1 выбираются через PATH; общий SDK не обновляется. Hosted PR использует setup actions. Checkout credentials не сохраняются.

Native local command:

```bash
PATH=/opt/homebrew/opt/node@20/bin:$PATH \
FLUTTER_BIN=/Volumes/PD1000/job/flutter/bin/flutter \
bash scripts/verify_native_macos.sh
```

Скрипт исключает CURRENCY_TEST_DATABASE_URL, очищает DATABASE_URL/REDIS_URL и не делает миграций. Backend DB integration tests поэтому отмечаются skipped, а не считаются пройденными. Mobile smoke использует fake backend и mock secure storage.

Runners запускаются только общим manual-run.py launcher. Один listener держит host lock до завершения child; прямой run.sh обходит ограничитель. Native проверки не запускать одновременно с GitHub job. При offline Mac jobs ожидают; автоматического fallback нет.

## Проверки

- actionlint1.7.7: все workflows, включая custom labels.
- Python9 tests: selector, release SHA identity и deployment rollback с fake Docker/curl. Fixture paths канонизированы для macOS /var -> /private/var.
- bash -n и git diff --check.
- Полный native script и логи сохраняются в workspace pilot-evidence; результат фиксируется отдельно перед публикацией.

## Оставшиеся hosted jobs

Все PR jobs остаются hosted, включая same-repository PR. Android preflight/signed release, production release bundle/deploy и VPS operations остаются Ubuntu. Docker images, Linux services, PostgreSQL integration и signing этим native прогоном не проверяются.

Это перенос трёх проверенных push gates, а не устранение всех hosted минут. Для остальных gates нужны отдельные подтверждённые эквиваленты; отключение или объявление skipped как успешной проверки запрещено. Production web build с dart-defines не заменяется общим CI artifact.

## Release SHA fix из исходного патча

После checkout manual ref определяется git rev-parse HEAD. Один release-sha используется для bundle, upload/download artifact, deploy checkout и аргумента release commit. Production triggers, environment, backup/manifest checks и cancel-in-progress:false сохранены. Сами release/deploy команды в Mac задаче не выполнялись.

## Публикация

До команды владельца ничего не push/merge/dispatch. Перед публикацией fetch актуальной main и проверка применимости полного patch обязательны; при продвижении main использовать отдельную ветку и 3-way review, не force push.

GitHub branch protection/rulesets API вернул 403 с требованием GitHub Pro для private repo. Это не подтверждение отсутствия правил; владелец проверяет их отдельно. Имена checks сохранены.

Откат маршрутизации: вернуть Build backend/Flutter verify на ubuntu-latest, smoke на macos-latest, сохранив сами checks. Публикация workflow не равна успешному GitHub run: нужен фактический dispatch и результаты jobs на согласованном SHA.
