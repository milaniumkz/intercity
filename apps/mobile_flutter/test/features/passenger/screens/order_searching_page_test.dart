import 'dart:async';
import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/sse_service.dart';
import 'package:intercity_mobile/features/passenger/screens/order_searching_page.dart';

void main() {
  testWidgets('auction offers stay at the top and leave the map visible',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _FakeApiClient()
      ..offers = [
        {
          'id': 'offer-1',
          'status': 'PENDING',
          'price': 1500,
          'driver': {
            'user': {'name': 'Алексей'},
            'carModel': 'Toyota',
            'rating': {'ratingAvg': 4.9}
          }
        }
      ];
    await tester.pumpWidget(MaterialApp(
        home: OrderSearchingPage(
      orderId: 'order-1',
      apiClient: api,
      enableLiveMap: false,
      realtimeConnector:
          (String path, {Map<String, dynamic>? queryParameters}) async => null,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final panel = tester
        .getRect(find.byKey(const ValueKey('passenger-top-auction-offers')));
    expect(panel.top, lessThan(30));
    expect(panel.bottom, lessThan(844 * .5));
    expect(find.text('Алексей'), findsOneWidget);
    expect(find.text('Принять'), findsOneWidget);
    expect(find.text('Отклонить'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'pickup ETA and route update from the moving driver, then hide on arrival',
      (tester) async {
    tester.view.physicalSize = const Size(400, 832);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _FakeApiClient(status: 'DRIVER_EN_ROUTE');
    await tester.pumpWidget(MaterialApp(
        home: OrderSearchingPage(
      orderId: 'order-1',
      apiClient: api,
      mapTileProvider: _TestTiles(),
      pollingInterval: const Duration(seconds: 1),
      realtimeConnector:
          (String path, {Map<String, dynamic>? queryParameters}) async => null,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('~ 7 мин'), findsOneWidget);
    expect(api.routeQueries.last['fromLat'], api.driverLat);
    expect(api.routeQueries.last['toLat'], 43.238949);
    api.driverLat = 43.242;
    api.routeMinutes = 3;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('~ 3 мин'), findsOneWidget);
    expect(api.routeQueries.last['fromLat'], 43.242);
    api.status = 'DRIVER_ARRIVED';
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('passenger-arrival-estimate')), findsNothing);
    api.status = 'IN_PROGRESS';
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.routeQueries.last['fromLat'], 43.242);
    expect(api.routeQueries.last['toLat'], 43.25667);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'driver card uses numeric rating and fits a phone without exposing rating IDs',
      (tester) async {
    tester.view.physicalSize = const Size(400, 832);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: OrderSearchingPage(
      orderId: 'order-1',
      apiClient: _FakeApiClient(status: 'DRIVER_EN_ROUTE'),
      enableLiveMap: false,
      realtimeConnector:
          (String path, {Map<String, dynamic>? queryParameters}) async => null,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('4.92'), findsOneWidget);
    expect(find.textContaining('private-rating-id'), findsNothing);
    final car = find.textContaining('Volkswagen Passat');
    expect(tester.getSize(car).width, greaterThan(150));
    final card = tester
        .getRect(find.byKey(const ValueKey('passenger-active-driver-card')));
    final nav = tester.getRect(find.text('Главная'));
    expect(nav.top - card.bottom, lessThan(65));
    expect(card.top, greaterThan(300));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('arrival estimate disappears as soon as driver arrives',
      (tester) async {
    final api = _FakeApiClient(status: 'DRIVER_EN_ROUTE');
    await tester.pumpWidget(MaterialApp(
        home: OrderSearchingPage(
      orderId: 'order-1',
      apiClient: api,
      enableLiveMap: false,
      pollingInterval: const Duration(seconds: 1),
      realtimeConnector:
          (String path, {Map<String, dynamic>? queryParameters}) async => null,
    )));
    await tester.pump();
    expect(find.byKey(const ValueKey('passenger-arrival-estimate')),
        findsOneWidget);
    api.status = 'DRIVER_ARRIVED';
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('passenger-arrival-estimate')), findsNothing);
    expect(find.text('Водитель на месте'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
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

  List<Map<String, dynamic>> offers = [];
  int getCalls = 0;
  final String currency;
  String status;
  double driverLat = 43.24;
  int routeMinutes = 7;
  final routeQueries = <Map<String, dynamic>>[];

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (path == '/route') {
      final q = Map<String, dynamic>.from(queryParameters!);
      routeQueries.add(q);
      return Response(requestOptions: RequestOptions(path: path), data: {
        'duration': routeMinutes,
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [q['fromLng'], q['fromLat']],
            [76.89, 43.245],
            [q['toLng'], q['toLat']],
          ]
        },
      });
    }
    getCalls++;
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      data: <String, dynamic>{
        'id': 'order-1',
        'offers': offers,
        'status': status,
        if (status != 'SEARCHING_DRIVER' && status != 'CANCELLED')
          'driver': {
            'online': {'lastLat': driverLat, 'lastLng': 76.889},
            'carModel': 'Volkswagen Passat с длинным названием модели',
            'rating': {
              'id': 'private-rating-id',
              'ratingAvg': 4.92,
              'ratingCount': 7
            },
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

class _TestTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='));
}
