import 'package:dio/dio.dart';
import '../support/memory_tile_provider.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/theme/theme_controller.dart';
import 'package:intercity_mobile/core/widgets/ic_premium.dart';
import 'package:intercity_mobile/main.dart';

void main() {
  Finder routeMarker(String text) => text == 'Показатели водителя'
      ? find.byTooltip(text)
      : find.textContaining(text);
  Future<void> pumpProductionRoute(
    WidgetTester tester,
    String route,
  ) async {
    final router = createRouter(
      initialLocation: route,
      disableAuthRedirect: true,
      orderApiClient: _NoActiveOrderApi(),
      mapTileProvider: MemoryTileProvider(),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode:
              route.contains('dark=1') ? ThemeMode.dark : ThemeMode.light,
          locale: const Locale('ru'),
          supportedLocales: const [
            Locale('ru'),
            Locale('kk'),
            Locale('en'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
      'driver metrics open in a compact top window without leaving the map',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpProductionRoute(tester, '/driver/home/driver_home');
    expect(find.text('Баланс'), findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('driver-metrics-popover-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final popup = find.byKey(const ValueKey('driver-metrics-popover'));
    expect(popup, findsOneWidget);
    for (final label in [
      'Баланс',
      'Сегодня',
      'Активность',
      'Рейтинг',
      'Приоритет'
    ]) {
      expect(find.descendant(of: popup, matching: find.text(label)),
          findsOneWidget);
    }
    expect(tester.getRect(popup).top, lessThan(150));
    expect(tester.getRect(popup).height, lessThan(300));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(popup, findsNothing);
    expect(find.byKey(const ValueKey('driver-metrics-popover-button')),
        findsOneWidget);
    expect(find.text('Баланс'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  final cases = <(String, String)>[
    ('/onboarding', 'Поездки'),
    ('/onboarding/intercity', 'Межгород'),
    ('/register', 'Кто вы?'),
    ('/register/driver', 'Регистрация водителя'),
    ('/login', 'Войдите'),
    ('/order/mode', 'Что нужно заказать?'),
    ('/order/address', 'Заказ поездки'),
    ('/order/map', 'Заказ поездки'),
    ('/order/fixed', 'Заказ поездки'),
    ('/order/routeprice', 'Заказ поездки'),
    ('/order/class', 'Заказ поездки'),
    ('/order/payment', 'Заказ поездки'),
    ('/order/confirm', 'Заказ поездки'),
    ('/order/searching', 'Поиск водителя'),
    ('/order/auction', 'Новый аукцион'),
    ('/order/offers_wait', 'Поиск предложений'),
    ('/order/offers_list', 'Выберите лучшее'),
    ('/order/offer_confirm', 'Подтвердите выбор'),
    ('/order/intercity_start', 'Межгород'),
    ('/order/intercity_options', 'Дополнительные опции'),
    ('/order/intercity_manual', 'Укажите адрес вручную'),
    ('/order/intercity_wait', 'Ищем водителей'),
    ('/order/intercity_details', 'Детали поездки'),
    ('/order/manual', 'Заказ поездки'),
    ('/order/offline', 'Нет подключения'),
    ('/order/notfound', 'Адрес не найден'),
    ('/profile', 'Профиль'),
    ('/profile/settings', 'Настройки'),
    ('/profile/support', 'Поддержка'),
    ('/profile/payments', 'Оплата поездок'),
    ('/wallet', 'Бонусы'),
    ('/orders-history', 'Мои поездки'),
    ('/orders-history/seed', 'Мои поездки'),
    ('/driver/verification/personal', 'Личные данные'),
    ('/driver/verification/car', 'Информация'),
    ('/driver/verification/docs', 'Документы'),
    ('/driver/home/driver_home', 'Показатели водителя'),
    ('/driver/home/fixed', 'Фиксированный заказ'),
    ('/driver/home/auction', 'Аукционный заказ'),
    ('/driver/home/offer', 'Предложите свою цену'),
    ('/driver/home/chosen', 'Пассажир выбрал вас'),
    ('/driver/home/active', 'Показатели водителя'),
    ('/driver/trip-create', 'Доступные заказы'),
    ('/driver/trip-create/detail', 'Детали заявки'),
    ('/driver/trip-create/commission', 'Подтверждение'),
    ('/driver/trip-create/insufficient', 'Недостаточно средств'),
    ('/driver/wallet', 'Кошелёк'),
    ('/driver/wallet/seed', 'Кошелёк'),
    ('/driver/profile', 'Профиль'),
  ];

  String withDark(String route) =>
      route.contains('?') ? '$route&dark=1' : '$route?dark=1';

  Future<void> tapTextAndExpect(
    WidgetTester tester, {
    required String startRoute,
    required String tapText,
    required String expectedText,
    bool last = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpProductionRoute(tester, startRoute);
    final matches = find.textContaining(tapText);
    for (var i = 0; i < 6 && matches.evaluate().isEmpty; i++) {
      final scrollables = find.byType(Scrollable);
      if (scrollables.evaluate().isEmpty) break;
      await tester.drag(scrollables.first, const Offset(0, -420));
      await tester.pump();
    }
    final target = last ? matches.last : matches.first;
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      routeMarker(expectedText),
      findsWidgets,
      reason: '$startRoute tap "$tapText" should show "$expectedText"',
    );
  }

  Future<void> tapGradientButtonAndExpect(
    WidgetTester tester, {
    required String startRoute,
    required String label,
    required String expectedText,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpProductionRoute(tester, startRoute);
    final matches = find.byWidgetPredicate(
      (widget) => widget is ICGradientButton && widget.label.contains(label),
    );
    for (var i = 0; i < 6 && matches.evaluate().isEmpty; i++) {
      final scrollables = find.byType(Scrollable);
      if (scrollables.evaluate().isEmpty) break;
      await tester.drag(scrollables.first, const Offset(0, -420));
      await tester.pump();
    }
    final target = matches.first;
    await tester.ensureVisible(target);
    await tester.pump();
    final button = tester.widget<ICGradientButton>(target);
    expect(button.onPressed, isNotNull);
    await tester.tap(target, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(
      routeMarker(expectedText),
      findsWidgets,
      reason: '$startRoute tap "$label" should show "$expectedText"',
    );
  }

  for (final item in cases) {
    testWidgets('production route ${item.$1} renders', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpProductionRoute(tester, item.$1);
      expect(
        routeMarker(item.$2),
        findsWidgets,
        reason: 'Route ${item.$1} should render "${item.$2}"',
      );
    });

    testWidgets('production route ${item.$1} renders dark', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final route = withDark(item.$1);
      await pumpProductionRoute(tester, route);
      expect(
        routeMarker(item.$2),
        findsWidgets,
        reason: 'Route $route should render "${item.$2}"',
      );
    });
  }

  testWidgets('auth flow uses password and no sms code screens',
      (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/login',
      tapText: 'Забыли пароль?',
      expectedText: 'Восстановление доступа',
    );

    expect(find.textContaining('SMS'), findsNothing);
    expect(find.textContaining('СМС'), findsNothing);
    expect(find.textContaining('код из'), findsNothing);

    await tester.ensureVisible(
        find.byKey(const ValueKey('forgot_password_back_button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('forgot_password_back_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Войдите'), findsWidgets);
  });

  testWidgets('passenger fixed fare production flow is connected',
      (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/order/fixed',
      tapText: 'Продолжить',
      expectedText: 'Ваш маршрут',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/order/routeprice',
      tapText: 'Далее',
      expectedText: 'Выберите класс',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/order/class',
      tapText: 'Комфорт',
      expectedText: 'Способ оплаты',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/order/payment',
      tapText: 'Наличными',
      expectedText: 'Подтвердите заказ',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/order/confirm',
      tapText: 'Заказать',
      expectedText: 'Для расчёта стоимости',
      last: true,
    );
  }, skip: true);

  testWidgets('passenger auction production flow is connected', (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/order/auction',
      tapText: 'Создать запрос',
      expectedText: 'Заполните адреса',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/order/offers_list',
      tapText: 'Алексей',
      expectedText: 'Подтвердите выбор',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/order/offer_confirm',
      tapText: 'Подтвердить',
      expectedText: 'Поиск водителя',
      last: true,
    );
  }, skip: true);

  testWidgets('passenger intercity production flow is connected',
      (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/order/intercity_start',
      tapText: 'Далее',
      expectedText: 'Дополнительные опции',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/order/intercity_options',
      tapText: 'Далее',
      expectedText: 'Сначала выберите города',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/order/intercity_wait',
      tapText: 'Обновить предложения',
      expectedText: 'Детали поездки',
    );
  }, skip: true);

  testWidgets('passenger intercity date row opens picker', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpProductionRoute(tester, '/order/intercity_start');
    await tester.tap(find.text('Дата'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CalendarDatePicker), findsOneWidget);
  }, skip: true);

  testWidgets('driver city production flow is connected', (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/driver/home/fixed',
      tapText: 'Принять заказ',
      expectedText: 'Пассажир выбрал вас',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/driver/home/auction',
      tapText: 'Предложить цену',
      expectedText: 'Предложите свою цену',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/driver/home/offer',
      tapText: 'Отправить предложение',
      expectedText: 'Пассажир выбрал вас',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/driver/home/chosen',
      tapText: 'Я на месте',
      expectedText: 'Поездка в пути',
    );
  }, skip: true);

  testWidgets('driver offer quick price updates amount field', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpProductionRoute(tester, '/driver/home/offer');
    await tester.tap(find.text('1 800 ₸'));
    await tester.pump();

    final priceField = tester.widget<TextField>(find.byType(TextField).first);
    expect(priceField.controller?.text, '1800');
  });

  testWidgets('driver intercity wallet production flow is connected',
      (tester) async {
    await tapGradientButtonAndExpect(
      tester,
      startRoute: '/driver/trip-create/commission',
      label: 'Подтвердить и принять',
      expectedText: 'Детали заявки',
    );
  });

  testWidgets('profile settings theme selector is connected', (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/profile/settings',
      tapText: 'Тёмная',
      expectedText: 'Тема изменена: тёмная',
    );
  });

  testWidgets('profile support FAQ opens answers', (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/profile/support',
      tapText: 'Как получить чек?',
      expectedText: 'Чек доступен',
    );
  });

  testWidgets('utility states route to real recovery flows', (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/order/offline',
      tapText: 'Продолжить офлайн',
      expectedText: 'Заказ поездки',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/order/notfound',
      tapText: 'Выбрать на карте',
      expectedText: 'Заказ поездки',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/order/notfound',
      tapText: 'Ввести вручную',
      expectedText: 'Заказ поездки',
    );
  });

  testWidgets('manual address controls are interactive', (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/order/auction',
      tapText: 'Укажите адрес подачи',
      expectedText: 'Введите адрес вручную',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/order/manual',
      tapText: 'Куда',
      expectedText: 'Введите адрес вручную',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/order/manual',
      tapText: 'Аэропорт Пулково',
      expectedText: 'Поиск предложений',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/order/address',
      tapText: 'Адресов пока нет',
      expectedText: 'Выбрать эту точку',
    );
  }, skip: true);

  testWidgets('intercity manual address map action is connected',
      (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/order/intercity_manual',
      tapText: 'Показать на карте',
      expectedText: 'Выбрать эту точку',
    );
  }, skip: true);

  testWidgets('passenger active intercity chat action is connected',
      (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/intercity/request/active',
      tapText: 'Чат',
      expectedText: 'Чат доступен',
    );
  });

  testWidgets('passenger active intercity back opens trips history',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpProductionRoute(tester, '/intercity/request/active');
    await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Мои поездки'), findsWidgets);
  });

  testWidgets('driver registration has no demo prefilled data', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpProductionRoute(tester, '/register/driver');

    expect(find.textContaining('(999) 123-45-67'), findsOneWidget);
    expect(find.textContaining('A 777 AA 77'), findsNothing);
    expect(find.textContaining('Александр'), findsNothing);
  });

  testWidgets('driver docs checklist selects upload document', (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/driver/verification/docs',
      tapText: 'Полис ОСАГО',
      expectedText: 'Выбран документ: Полис ОСАГО',
    );
  }, skip: true);

  testWidgets('driver car selector fields are interactive', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpProductionRoute(tester, '/driver/verification/car');
    await tester.tap(find.text('Марка'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BMW').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Марка: BMW'), findsWidgets);

    await tester.tap(find.text('Цвет'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Белый').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Цвет: Белый'), findsWidgets);
  }, skip: true);

  testWidgets('driver wallet filters and statistics are interactive',
      (tester) async {
    await pumpProductionRoute(tester, '/driver/wallet');
    expect(find.text('Бонусы'), findsWidgets);
    expect(find.textContaining('1 бонус = 1 ₸'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -360));
    await tester.pump();
    expect(find.text('Создать заявку на вывод'), findsWidgets);
    expect(find.textContaining('Выплаты'), findsNothing);
    expect(find.textContaining('Выплата'), findsNothing);

    await tapTextAndExpect(
      tester,
      startRoute: '/driver/wallet/seed',
      tapText: 'Пополнения',
      expectedText: 'Пополнение баланса',
    );
    expect(find.textContaining('Выплата на карту'), findsNothing);

    await tapTextAndExpect(
      tester,
      startRoute: '/driver/wallet',
      tapText: 'Статистика',
      expectedText: 'Доступно к выплате',
    );
  });

  testWidgets('driver intercity request filters are interactive',
      (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/driver/trip-create',
      tapText: 'По городу',
      expectedText: 'Нет заявок по выбранным фильтрам.',
    );
  });

  testWidgets('driver home bottom navigation is interactive', (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/driver/home/driver_home',
      tapText: 'Сообщения',
      expectedText: 'Сообщения доступны',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/driver/home/driver_home',
      tapText: 'Заказы',
      expectedText: 'Доступные заказы',
    );
  });

  testWidgets('driver chosen trip call action is connected', (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/driver/home/chosen',
      tapText: 'Позвонить',
      expectedText: 'Звонок пассажиру',
    );
  });

  testWidgets('driver fixed order close returns to orders list',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpProductionRoute(tester, '/driver/home/fixed');
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(routeMarker('Показатели водителя'), findsWidgets);
  });

  testWidgets('driver profile quick actions are interactive', (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/driver/profile',
      tapText: 'Кошелёк',
      expectedText: 'Кошелёк',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/driver/profile',
      tapText: 'О приложении',
      expectedText: 'InterCity Driver',
    );
  });

  testWidgets('passenger payments method is interactive', (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/profile/payments',
      tapText: 'На карту',
      expectedText: 'Основной способ оплаты: На карту',
    );
  });

  testWidgets('passenger bonus screen is visible and interactive',
      (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/wallet',
      tapText: 'Использовать в поездке',
      expectedText: 'Бонусы можно выбрать на экране оплаты.',
    );
  });

  testWidgets('passenger history route actions are interactive',
      (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/orders-history',
      tapText: 'Завершенные',
      expectedText: 'Завершена',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/orders-history',
      tapText: 'Маршрут',
      expectedText: 'Поездка',
    );
  });

  testWidgets('passenger profile rows open real destinations', (tester) async {
    await tapTextAndExpect(
      tester,
      startRoute: '/profile',
      tapText: 'Способы оплаты',
      expectedText: 'Оплата поездок',
    );
    await tapTextAndExpect(
      tester,
      startRoute: '/profile',
      tapText: 'О приложении',
      expectedText: 'InterCity',
    );
  });

  testWidgets('top back buttons work from direct urls', (tester) async {
    Future<void> tapBackAndExpect(String route, String expectedText) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpProductionRoute(tester, route);
      final backButton = find.byIcon(Icons.arrow_back_rounded);
      expect(backButton, findsWidgets,
          reason: '$route should have back button');
      await tester.tap(backButton.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(routeMarker(expectedText), findsWidgets,
          reason: 'Back from $route should show $expectedText');
    }

    await tapBackAndExpect('/profile/settings', 'Профиль');
    await tapBackAndExpect('/profile/payments', 'Профиль');
    await tapBackAndExpect('/forgot-password', 'Войдите');
    await tapBackAndExpect('/register', 'Войдите');
    await tapBackAndExpect('/intercity/request/active', 'Мои поездки');
    await tapBackAndExpect('/driver/wallet', 'Показатели водителя');
    await tapBackAndExpect('/driver/trip-create/detail', 'Доступные заказы');
    await tapBackAndExpect('/driver/verification/docs', 'Показатели водителя');
    await tapBackAndExpect('/driver/profile', 'Показатели водителя');
  });
}

class _NoActiveOrderApi extends ApiClient {
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    dynamic data = <String, dynamic>{};
    if (path == '/orders/active') data = null;
    if (path == '/geo/cities') data = <dynamic>[];
    if (path == '/app/runtime-settings') {
      data = {'passengerMapHomeEnabled': false};
    }
    return Response(requestOptions: RequestOptions(path: path), data: data);
  }
}
