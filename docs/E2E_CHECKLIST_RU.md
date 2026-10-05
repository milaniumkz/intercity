# E2E чек-лист INTERCITY (пассажир / водитель / админ)

## 1. Подготовка окружения
1. Поднять backend и БД.
2. Выполнить `prisma generate`, `prisma db push`, `prisma:seed`.
3. Проверить admin аккаунт из seed.
4. Для `apps/mobile_flutter` и `apps/admin_web` выставить одинаковый `INTERCITY_API_BASE_URL`.
5. Не использовать placeholder fallback `https://api.intercity.invalid/api` в реальном окружении.
6. Для Android release подготовить env vars signing:
   - `INTERCITY_ANDROID_RELEASE_KEYSTORE_PATH`
   - `INTERCITY_ANDROID_RELEASE_STORE_PASSWORD`
   - `INTERCITY_ANDROID_RELEASE_KEY_ALIAS`
   - `INTERCITY_ANDROID_RELEASE_KEY_PASSWORD`
7. Подготовить 3 аккаунта: `admin`, `passenger`, `driver`.

## 2. Авторизация и роли
1. Регистрация пассажира, вход, выход, повторный вход.
2. Регистрация водителя, вход, переход в верификацию.
3. Проверка редиректов ролей после логина (`/order`, `/driver/home`, `/admin/dashboard`).
4. Проверка refresh token: истечение access token и автоматическое обновление.
5. Негативный refresh сценарий: invalid refresh token очищает токены и переводит пользователя в управляемую ошибку авторизации без бесконечных retry.

## 3. Пассажирский поток
1. Создать заказ CITY:
   - выбрать точки,
   - получить preview,
   - создать заказ,
   - проверить статус `SEARCHING_DRIVER`.
2. Проверить экран поиска водителя:
   - отображение карты,
   - обновление статуса заказа,
   - при работающем SSE нет постоянного дублирующего polling,
   - polling поднимается только как fallback при недоступном или оборванном SSE,
   - отображение данных водителя после назначения.
3. Отменить заказ до принятия и после принятия (проверка бизнес-ограничений).
4. Завершить поездку и поставить оценку водителю.
5. История заказов:
   - корректная сортировка,
   - корректные статусы,
   - наличие id/цены/маршрута.

## 4. Водительский поток
1. Создать профиль водителя (авто/номер).
2. Проверить multi-word марки авто:
   - `Land Rover Range Rover • Черный` корректно разбирается на make/model/color.
3. Загрузить документы через `/driver/docs/upload-url` + `complete`.
4. Проверить, что до одобрения нельзя уйти в Online.
5. После одобрения админом:
   - включить Online,
   - обновить геолокацию,
   - увидеть nearby orders.
6. Принять заказ, пройти статусы:
   - `DRIVER_ASSIGNED` -> `DRIVER_EN_ROUTE` -> `DRIVER_ARRIVED` -> `IN_PROGRESS` -> `COMPLETED`.
7. Проверить автопринятие:
   - `driverAutoAcceptEnabled=true`,
   - `driverAutoAcceptRadiusKm` установлен,
   - при появлении заказа в радиусе заказ принимается автоматически.
8. Проверить отклонение заказов и штраф активности.

## 5. Кошелек и деньги
1. Пассажир: topup request создается.
2. Админ: approve/reject topup.
3. Проверить изменение `wallet.money` после approve.
4. Водитель: payout request создается.
5. Админ: approve/reject payout.
6. Проверить rollback денег при reject payout.
7. Бонус-перевод между пользователями по номеру телефона.

## 6. Админка
1. Вход admin, загрузка dashboard без ошибок.
2. Модерация водителей:
   - approve,
   - reject,
   - флаги приоритета,
   - fuel bonus.
3. CRUD городов.
4. CRUD тарифов (city/cargo/delivery).
5. Настройки приложения:
   - `searchRadiusKm`,
   - `driverAutoAcceptEnabled`,
   - `driverAutoAcceptRadiusKm`.
6. Универсальный CRUD коллекций:
   - list collections,
   - list items,
   - create,
   - update by id,
   - delete by id.

## 7. Негативные сценарии
1. Неверный token / истекший token.
2. Доступ без роли admin к `/admin/*`.
3. Водитель без online вызывает `/driver/orders/nearby`.
4. Принятие уже занятого заказа.
5. Некорректные суммы в wallet (0/отрицательные/слишком большие).
6. Некорректный JSON в admin collections CRUD.

## 8. UX и стабильность
1. Проверить ключевые экраны на маленьком экране (Android 5.5") и большом (6.7").
2. Проверить pull-to-refresh и индикаторы загрузки.
3. Проверить, что после ошибок пользователь получает понятные сообщения.
4. Проверить восстановление состояния после перезапуска приложения.

## 9. Критерии готовности релиза
1. Все сценарии выше пройдены без блокирующих дефектов P0/P1.
2. Нет падений приложения на основных потоках.
3. Нет регрессий по auth/orders/wallet/admin.
4. Логика автопринятия совпадает с настройками в админке.
