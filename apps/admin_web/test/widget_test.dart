import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_admin/core/api/admin_api_client.dart';
import 'package:intercity_admin/main.dart';

void main() {
  late _FakeAdminApi api;

  setUp(() {
    api = _FakeAdminApi();
    AdminApiClient.debugOverride(api);
  });

  tearDown(() {
    AdminApiClient.debugOverride(null);
  });

  testWidgets('admin interface main buttons are wired', (tester) async {
    tester.view.physicalSize = const Size(1600, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const IntercityAdminApp());
    await tester.pumpAndSettle();

    expect(find.text('INTERCITY Admin'), findsWidgets);

    await tester.tap(_buttonFinder('Войти'));
    await tester.pumpAndSettle();

    expect(find.text('Панель'), findsWidgets);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Обновить').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Пользователи').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Поиск'), '+700');
    await tester.enterText(find.widgetWithText(TextField, 'Роль'), 'ADMIN');
    await tester.tap(_buttonFinder('Загрузить пользователей'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Загружено'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Выбрать').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Причина удаления'),
      'Тестовое удаление',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить пользователя'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Водители').last);
    await tester.pumpAndSettle();
    await tester.tap(_buttonFinder('Подтвердить').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Отклонить').first);
    await tester.pumpAndSettle();
    await tester.tap(_buttonFinder('Сохранить флаги'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Для этого действия нужен ID водителя'),
        findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'ID водителя'), 'driver-1');
    await tester.tap(_buttonFinder('Сохранить флаги'));
    await tester.pumpAndSettle();
    await tester.tap(_buttonFinder('Топливо +24ч'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Получить приоритет'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Приоритет:'), findsOneWidget);

    await tester.tap(find.text('Города').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'ID города для обновления'), 'city-1');
    await tester.enterText(
        find.widgetWithText(TextField, 'Название города'), 'Astana');
    await tester.enterText(find.widgetWithText(TextField, 'Регион'), 'Akmola');
    await tester.tap(_buttonFinder('Создать город'));
    await tester.pumpAndSettle();
    await tester.tap(_buttonFinder('Обновить город'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Удалить').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Тарифы').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'City ID for city tariff'), 'city-1');
    await tester.enterText(
        find.widgetWithText(TextField, 'City tariff ID to deactivate'), 'ct-1');
    await tester.enterText(
        find.widgetWithText(TextField, 'Cargo tariff ID to deactivate'),
        'cg-1');
    await tester.enterText(
        find.widgetWithText(TextField, 'Delivery tariff ID to deactivate'),
        'dl-1');
    await tester.tap(_buttonFinder('Create city tariff'));
    await tester.pumpAndSettle();
    await tester.tap(_buttonFinder('Create cargo tariff'));
    await tester.pumpAndSettle();
    await tester.tap(_buttonFinder('Create delivery tariff'));
    await tester.pumpAndSettle();
    await tester.tap(_buttonFinder('Deactivate city'));
    await tester.pumpAndSettle();
    await tester.tap(_buttonFinder('Deactivate cargo'));
    await tester.pumpAndSettle();
    await tester.tap(_buttonFinder('Deactivate delivery'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Настройки').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Key'), 'featureFlag');
    await tester.enterText(find.widgetWithText(TextField, 'Value'), 'on');
    await tester.tap(_buttonFinder('Save setting'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Пополнения').last);
    await tester.pumpAndSettle();
    await tester.tap(_buttonFinder('Approve').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Выплаты').last);
    await tester.pumpAndSettle();
    await tester.tap(_buttonFinder('Approve').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Уведомления').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Заголовок'), 'Promo');
    await tester.enterText(find.widgetWithText(TextField, 'Текст'), 'Body');
    await tester.tap(_buttonFinder('Создать кампанию'));
    await tester.pumpAndSettle();
    await tester.tap(_buttonFinder('В очередь').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Повторить').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Финансовый аудит').last);
    await tester.pumpAndSettle();
    await tester.tap(_buttonFinder('Обновить'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Экспорт CSV'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CSV готов'), findsOneWidget);

    await tester.tap(find.text('Заказы').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Таймлайн').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Таймлайн заказа'), findsOneWidget);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    await tester.tap(find
        .byWidgetPredicate((widget) => widget is PopupMenuButton<String>)
        .first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('COMPLETED').last);
    await tester.pumpAndSettle();

    expect(api.calls, contains('POST /admin/drivers/driver-1/flags'));
    expect(api.calls, contains('GET /admin/users'));
    expect(
      api.calls,
      contains(
        'DELETE /admin/users/user-1?reason=%D0%A2%D0%B5%D1%81%D1%82%D0%BE%D0%B2%D0%BE%D0%B5+%D1%83%D0%B4%D0%B0%D0%BB%D0%B5%D0%BD%D0%B8%D0%B5',
      ),
    );
    expect(api.calls, contains('POST /admin/drivers/driver-1/fuel-bonus'));
    expect(api.calls, contains('POST /admin/cities'));
    expect(api.calls, contains('PATCH /admin/cities/city-1'));
    expect(api.calls, contains('POST /admin/tariffs/city'));
    expect(api.calls, contains('POST /admin/topups/topup-1/approve'));
    expect(api.calls, contains('POST /admin/payouts/payout-1/approve'));
    expect(api.calls, contains('POST /admin/notifications/campaign-1/send'));
    expect(api.calls, contains('POST /admin/notifications/jobs/job-1/requeue'));
    expect(api.calls, contains('PATCH /admin/orders/order-1'));
  });
}

class _FakeAdminApi implements AdminApi {
  final List<String> calls = [];

  @override
  Future<Response<dynamic>> delete(String path) async {
    calls.add('DELETE $path');
    return _response(path, {'ok': true});
  }

  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? query}) async {
    calls.add('GET $path');
    if (path == '/admin/drivers/pending') {
      return _response(path, [
        {
          'id': 'driver-pending-1',
          'status': 'PENDING',
          'user': {'phone': '+70000000001'}
        }
      ]);
    }
    if (path == '/admin/users') {
      return _response(path, {
        'items': [
          {
            'id': 'user-1',
            'phone': '+70000000003',
            'name': 'Admin One',
            'role': 'ADMIN',
            'cityId': 'city-1',
            'city': {'id': 'city-1', 'name': 'Almaty'},
          }
        ],
        'total': 1,
        'take': 100,
        'skip': 0,
      });
    }
    if (path == '/admin/topups') {
      return _response(path, [
        {'id': 'topup-1', 'amount': 1000, 'status': 'PENDING'}
      ]);
    }
    if (path == '/admin/payouts') {
      return _response(path, [
        {'id': 'payout-1', 'amount': 500, 'status': 'PENDING'}
      ]);
    }
    if (path == '/admin/orders') {
      return _response(path, [
        {
          'id': 'order-1',
          'mode': 'CITY',
          'status': 'SEARCHING_DRIVER',
          'price': 2500
        }
      ]);
    }
    if (path == '/admin/dashboard/kpis') {
      return _response(path, {
        'notificationDispatchDegraded24h': false,
        'activeOrders': 4,
        'onlineDrivers': 12,
        'problemOrders': 1,
        'notificationDispatchQueued': 2,
        'notificationDispatchRunning': 1,
        'notificationDispatchFailed': 0,
        'notificationDispatchDone24h': 11,
        'notificationDispatchFailed24h': 1,
        'notificationDispatchSuccessRate24h': 91,
        'notificationDispatchRetries24h': 3,
        'notificationDispatchRetryDone24h': 2,
      });
    }
    if (path == '/admin/drivers/driver-1/priority') {
      return _response(path, 'priority-score-1');
    }
    if (path == '/admin/cities') {
      return _response(path, [
        {
          'id': 'city-1',
          'name': 'Almaty',
          'region': 'South',
          'lat': 43.2,
          'lng': 76.8
        }
      ]);
    }
    if (path == '/admin/tariffs/city') {
      return _response(path, [
        {
          'id': 'ct-1',
          'name': 'City Standard',
          'isActive': true,
          'city': {'name': 'Almaty'}
        }
      ]);
    }
    if (path == '/admin/tariffs/cargo') {
      return _response(path, [
        {'id': 'cg-1', 'name': 'Cargo Standard', 'isActive': true}
      ]);
    }
    if (path == '/admin/tariffs/delivery') {
      return _response(path, [
        {'id': 'dl-1', 'name': 'Delivery Standard', 'isActive': true}
      ]);
    }
    if (path == '/admin/settings') {
      return _response(path, [
        {'key': 'searchRadiusKm', 'value': '5'}
      ]);
    }
    if (path == '/admin/notifications') {
      return _response(path, [
        {'id': 'campaign-1', 'title': 'Sale', 'body': 'Today', 'isSent': false}
      ]);
    }
    if (path == '/admin/notifications/jobs') {
      return _response(path, [
        {
          'id': 'job-1',
          'campaignId': 'campaign-1',
          'status': 'FAILED',
          'queuedAt': '2026-03-13T10:00:00Z',
        }
      ]);
    }
    if (path == '/admin/wallet-transactions') {
      return _response(path, [
        {
          'type': 'TOPUP',
          'direction': 'IN',
          'amount': 1000,
          'balanceSource': 'CARD',
          'createdAt': '2026-03-13T10:00:00Z',
          'wallet': {
            'user': {'phone': '+70000000002'}
          }
        }
      ]);
    }
    if (path == '/admin/reports/wallet-transactions/csv') {
      return _response(path, {'csv': 'a,b\n1,2'});
    }
    if (path == '/admin/orders/order-1/events') {
      return _response(path, [
        {
          'fromStatus': 'SEARCHING_DRIVER',
          'toStatus': 'DRIVER_ASSIGNED',
          'createdAt': '2026-03-13T10:05:00Z',
          'source': 'SYSTEM',
        }
      ]);
    }
    throw UnimplementedError('Unhandled GET $path');
  }

  @override
  Future<Map<String, dynamic>> login(String phone, String password) async {
    calls.add('LOGIN');
    return {'role': 'ADMIN'};
  }

  @override
  Future<void> logout() async {
    calls.add('LOGOUT');
  }

  @override
  Future<Response<dynamic>> patch(String path, {data}) async {
    calls.add('PATCH $path');
    return _response(path, {'ok': true});
  }

  @override
  Future<Response<dynamic>> post(String path, {data}) async {
    calls.add('POST $path');
    return _response(path, {'ok': true});
  }

  Response<dynamic> _response(String path, dynamic data) {
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      data: data,
      statusCode: 200,
    );
  }
}

Finder _buttonFinder(String label) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is ButtonStyleButton &&
        widget.child is Text &&
        (widget.child as Text).data == label,
  );
}
