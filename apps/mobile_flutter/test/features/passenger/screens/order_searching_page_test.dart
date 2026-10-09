import 'dart:async';
import 'package:go_router/go_router.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/sse_service.dart';
import 'package:intercity_mobile/features/passenger/screens/order_searching_page.dart';

void main() {
  testWidgets('opening a cancelled order redirects to the new booking form',
      (tester) async {
    final router =
        GoRouter(initialLocation: '/order/searching/order-1', routes: [
      GoRoute(
          path: '/order/searching/:id',
          builder: (_, state) => OrderSearchingPage(
              orderId: 'order-1',
              apiClient: _FakeApiClient(status: 'CANCELLED'),
              enableLiveMap: false,
              realtimeConnector: (String path,
                      {Map<String, dynamic>? queryParameters}) async =>
                  null)),
      GoRoute(
          path: '/order',
          builder: (_, state) => const Text('New booking form')),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('New booking form'), findsOneWidget);
    expect(find.text('Поиск водителя...'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('ongoing city trip has a cancellation action', (tester) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: OrderSearchingPage(
      orderId: 'order-1',
      apiClient: _FakeApiClient(status: 'IN_PROGRESS'),
      enableLiveMap: false,
      realtimeConnector:
          (String path, {Map<String, dynamic>? queryParameters}) async => null,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Отменить заказ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final currency in ['RUB', 'KZT']) {
    testWidgets('passenger order displays its saved $currency currency',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: OrderSearchingPage(
        orderId: 'order-1',
        apiClient: _FakeApiClient(currency: currency),
        enableLiveMap: false,
        realtimeConnector: (String path,
                {Map<String, dynamic>? queryParameters}) async =>
            null,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1500 ${currency == 'RUB' ? '₽' : '₸'}'), findsWidgets);
      expect(find.text('1500 ${currency == 'RUB' ? '₸' : '₽'}'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'recovers accepted driver when connected realtime delivers no event',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    final api = _FakeApiClient();

    await tester.pumpWidget(
      MaterialApp(
        home: OrderSearchingPage(
          orderId: 'order-1',
          apiClient: api,
          pollingInterval: const Duration(seconds: 1),
          enableLiveMap: false,
          realtimeConnector: (
            String path, {
            Map<String, dynamic>? queryParameters,
          }) async {
            return SseConnection(
              stream: controller.stream,
              close: () async {},
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(api.getCalls, 1);

    api.status = 'DRIVER_EN_ROUTE';
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(api.getCalls, greaterThan(1));
    expect(find.text('Водитель едет'), findsWidgets);
    expect(find.text('Тестовый водитель'), findsWidgets);
    expect(find.text('Ищем водителя'), findsNothing);
    api.status = 'DRIVER_ARRIVED';
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Водитель на месте'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.close();
  });

  testWidgets('starts polling when realtime stream is unavailable',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _FakeApiClient();

    await tester.pumpWidget(
      MaterialApp(
        home: OrderSearchingPage(
          orderId: 'order-1',
          apiClient: api,
          pollingInterval: const Duration(seconds: 1),
          enableLiveMap: false,
          realtimeConnector: (
            String path, {
            Map<String, dynamic>? queryParameters,
          }) async {
            return null;
          },
        ),
      ),
    );
    await tester.pump();

    expect(api.getCalls, 1);

    await tester.pump(const Duration(seconds: 3));

    expect(api.getCalls, greaterThan(1));
  });
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.currency = 'KZT', this.status = 'SEARCHING_DRIVER'})
      : super(
          dio: Dio(),
          refreshDio: Dio(),
          tokenStore: _MemoryTokenStore(),
          baseUrl: 'https://api.intercity.invalid/api',
        );

  int getCalls = 0;
  final String currency;
  String status;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    getCalls++;
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      data: <String, dynamic>{
        'id': 'order-1',
        'status': status,
        if (status != 'SEARCHING_DRIVER' && status != 'CANCELLED')
          'driver': {
            'carModel': 'Toyota',
            'carNumber': 'TEST',
            'user': {'name': 'Тестовый водитель', 'phone': '+70000000001'}
          },
        'currency': currency,
        'price': 1500,
        'fromAddress': 'Точка A',
        'toAddress': 'Точка B',
        'fromLat': 43.238949,
        'fromLng': 76.889709,
        'toLat': 43.25667,
        'toLng': 76.92861,
      },
      statusCode: 200,
    );
  }
}

class _MemoryTokenStore implements ApiTokenStore {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}
