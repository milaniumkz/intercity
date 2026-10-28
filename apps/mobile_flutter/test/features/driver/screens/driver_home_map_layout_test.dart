import 'dart:async';
import 'package:intercity_mobile/core/services/sse_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/driver/screens/driver_home_page.dart';
import '../../../support/memory_tile_provider.dart';

class _HomeApi extends ApiClient {
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    dynamic data = <String, dynamic>{};
    if (path == '/driver/profile') {
      data = {
        'id': 'driver',
        'status': 'ACTIVE',
        'acceptIntercity': false,
        'online': {'isOnline': true},
        'todayCompletedOrders': 8,
        'performance': {
          'activity': {'score': 88, 'level': 'green'},
          'rating': {'average': 5, 'count': 10},
          'priority': {'total': 28}
        },
      };
    }
    if (path == '/wallet') data = {'money': 12500};
    if (path == '/orders/my' ||
        path == '/driver/intercity/active' ||
        path == '/driver/orders/nearby') {
      data = [];
    }
    return Response(requestOptions: RequestOptions(path: path), data: data);
  }
}

void main() {
  testWidgets(
      'accepted intercity restores even while both optional feeds never respond',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
        home: DriverHomePage(
            apiClient: _UnavailableFeedsApi(),
            mapTileProvider: MemoryTileProvider(),
            realtimeConnector: (_) async => null)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('driver-primary-ride-action')),
        findsOneWidget);
    expect(find.text('Начать поездку'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'registered route request appears on the map and accepts a price offer',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = _MatchingRouteApi();
    await tester.pumpWidget(MaterialApp(
        home: DriverHomePage(
            apiClient: api,
            mapTileProvider: MemoryTileProvider(),
            realtimeConnector: (_) async => null)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Усть-Каменогорск, Назарбаева 8/1'), findsOneWidget);
    expect(find.text('Семей, Абая 10'), findsOneWidget);
    await tester.ensureVisible(find.text('Предложить цену'));
    await tester.tap(find.text('Предложить цену'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '7500');
    await tester.tap(find.text('Отправить предложение'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.sentPrice, 7500);
    expect(api.sentSeats, 2);
    expect(find.textContaining('Моё предложение: 7500'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'intercity leaving reaches a driver on the map without opening the trip',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final events = StreamController<Map<String, dynamic>>.broadcast();
    final api = _IntercityApi();
    await tester.pumpWidget(MaterialApp(
        home: DriverHomePage(
            apiClient: api,
            mapTileProvider: MemoryTileProvider(),
            realtimeConnector: (_) async =>
                SseConnection(stream: events.stream, close: () async {}))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(events.hasListener, isTrue);
    expect(find.text('Активный заказ'), findsOneWidget);
    api.leaving = '2026-10-12T08:00:00Z';
    events.add({
      'event': 'driver-event',
      'data': {
        'type': 'driver.passenger.leaving',
        'payload': {
          'tripId': 'intercity',
          'isIntercity': true,
          'passengerLeavingAt': api.leaving
        }
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Пассажир выходит к машине'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await events.close();
  });
  testWidgets(
      'passenger leaving reaches driver immediately and polling does not repeat it',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final events = StreamController<Map<String, dynamic>>.broadcast();
    final api = _ArrivedApi();
    await tester.pumpWidget(MaterialApp(
        home: DriverHomePage(
            apiClient: api,
            mapTileProvider: MemoryTileProvider(),
            realtimeConnector: (_) async =>
                SseConnection(stream: events.stream, close: () async {}))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(events.hasListener, isTrue);
    expect(find.text('Пассажир выходит к машине'), findsNothing);
    api.leaving = '2026-10-12T08:00:00Z';
    final event = {
      'event': 'driver-event',
      'data': {
        'type': 'driver.passenger.leaving',
        'payload': {'tripId': 'arrived', 'passengerLeavingAt': api.leaving}
      }
    };
    events.add(event);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Пассажир выходит к машине'), findsOneWidget);
    events.add(event);
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Пассажир выходит к машине'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await events.close();
  });
  testWidgets(
      'passenger rejection closes price wait immediately despite a stale poll',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final events = StreamController<Map<String, dynamic>>.broadcast();
    final api = _WaitingApi();
    await tester.pumpWidget(MaterialApp(
        home: DriverHomePage(
            apiClient: api,
            mapTileProvider: MemoryTileProvider(),
            realtimeConnector: (_) async =>
                SseConnection(stream: events.stream, close: () async {}))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ждём подтверждения пассажира'), findsOneWidget);
    expect(events.hasListener, isTrue);
    events.add({
      'event': 'order-event',
      'data': {
        'type': 'order.offer.rejected',
        'entityId': 'auction',
        'payload': {
          'orderId': 'auction',
          'offerId': 'price-offer',
          'driverId': 'driver'
        }
      }
    });
    await tester.pump();
    await tester.pump();
    expect(find.text('Ждём подтверждения пассажира'), findsNothing);
    api.pending.complete(Response(
        requestOptions: RequestOptions(path: '/orders/auction'),
        data: {
          'id': 'auction',
          'status': 'SEARCHING_DRIVER',
          'offers': [
            {'id': 'price-offer', 'status': 'PENDING'}
          ]
        }));
    await tester.pump();
    await tester.pump();
    expect(find.text('Ждём подтверждения пассажира'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await events.close();
  });

  for (final size in [const Size(360, 740), const Size(320, 568)]) {
    testWidgets(
        'full screen driver map and anchored metrics remain usable at $size',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: DriverHomePage(
              apiClient: _HomeApi(), mapTileProvider: MemoryTileProvider())));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      final mapFinder = find.byType(FlutterMap);
      expect(tester.getRect(mapFinder),
          Rect.fromLTWH(0, 0, size.width, size.height));
      expect(find.byKey(const ValueKey('driver-online-toggle')).hitTestable(),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('driver-metric-Активность')), findsNothing);
      final controller = tester.widget<FlutterMap>(mapFinder).mapController;
      final old = MapCamera.of(tester.element(find.byType(TileLayer))).center;
      await tester.drag(mapFinder, const Offset(70, 20));
      await tester.pump(const Duration(milliseconds: 300));
      final moved = MapCamera.of(tester.element(find.byType(TileLayer))).center;
      expect(moved, isNot(old));
      expect(
          tester.widget<FlutterMap>(mapFinder).mapController, same(controller));
      await tester
          .tap(find.byKey(const ValueKey('driver-metrics-popover-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final panel = find.byKey(const ValueKey('driver-metrics-popover'));
      expect(panel, findsOneWidget);
      final rect = tester.getRect(panel);
      expect(
          rect.top,
          greaterThan(tester
              .getRect(find.byKey(const ValueKey('driver-online-toggle')))
              .bottom));
      expect(rect.bottom, lessThan(size.height - 20));
      for (final title in [
        'Баланс',
        'Сегодня',
        'Активность',
        'Рейтинг',
        'Приоритет'
      ]) {
        expect(find.byKey(ValueKey('driver-metric-$title')).hitTestable(),
            findsOneWidget);
      }
      await tester.tap(find.byTooltip('Закрыть'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(panel, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}

class _WaitingApi extends _HomeApi {
  final pending = Completer<Response<dynamic>>();
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    if (path == '/orders/auction') return pending.future;
    final response = await super
        .get(path, queryParameters: queryParameters, options: options);
    if (path == '/driver/profile') {
      response.data['pendingAuctionOffer'] = {
        'id': 'price-offer',
        'orderId': 'auction',
        'expiresAt':
            DateTime.now().add(const Duration(seconds: 30)).toIso8601String()
      };
    }
    return response;
  }
}

class _ArrivedApi extends _HomeApi {
  String? leaving;
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    final order = {
      'id': 'arrived',
      'status': 'DRIVER_ARRIVED',
      'passengerLeavingAt': leaving,
      'fromLat': 49.95,
      'fromLng': 82.6,
      'toLat': 49.96,
      'toLng': 82.61,
      'fromAddress': 'A',
      'toAddress': 'B',
      'price': 700,
      'currency': 'KZT',
      'passenger': {'name': 'Passenger', 'phone': '+70000000000'}
    };
    if (path == '/driver/orders/active') {
      return Response(requestOptions: RequestOptions(path: path), data: order);
    }
    if (path == '/orders/arrived') {
      return Response(requestOptions: RequestOptions(path: path), data: order);
    }
    return super.get(path, queryParameters: queryParameters, options: options);
  }
}

class _IntercityApi extends _HomeApi {
  String? leaving;
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    if (path == '/driver/profile') {
      final res = await super.get(path);
      (res.data as Map)['acceptIntercity'] = true;
      return res;
    }
    if (path == '/ridesharing/trips/my') {
      return Response(requestOptions: RequestOptions(path: path), data: []);
    }
    if (path == '/driver/intercity/active') {
      return Response(requestOptions: RequestOptions(path: path), data: [
        {
          'id': 'intercity',
          'status': 'DRIVER_ARRIVED',
          'requestType': 'INTERCITY',
          'passengerLeavingAt': leaving,
          'fromCity': 'A',
          'toCity': 'B',
          'price': 700,
          'currency': 'KZT'
        }
      ]);
    }
    return super.get(path, queryParameters: queryParameters, options: options);
  }
}

class _MatchingRouteApi extends _HomeApi {
  num? sentPrice;
  dynamic sentSeats;
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    if (path == '/driver/profile') {
      final result = await super.get(path);
      (result.data as Map)['acceptIntercity'] = true;
      return result;
    }
    if (path == '/ridesharing/trips/my') {
      return Response(requestOptions: RequestOptions(path: path), data: []);
    }
    if (path == '/driver/intercity/matching') {
      return Response(requestOptions: RequestOptions(path: path), data: [
        {
          'id': 'planned',
          'fromCity': 'Усть-Каменогорск',
          'toCity': 'Семей',
          'fromManualAddress': 'Назарбаева 8/1',
          'toAddressLabel': 'Абая 10',
          'date': '2026-10-15T05:00:00Z',
          'seats': 2,
          'price': 7000,
          'currency': 'KZT',
          if (sentPrice != null)
            'myOffer': {'price': sentPrice, 'status': 'PENDING'},
        }
      ]);
    }
    return super.get(path, queryParameters: queryParameters, options: options);
  }

  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data, Options? options}) async {
    if (path == '/intercity/requests/planned/offers') {
      sentPrice = data['price'];
      sentSeats = data['seats'];
    }
    return Response(requestOptions: RequestOptions(path: path), data: {});
  }
}

class _UnavailableFeedsApi extends _IntercityApi {
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) {
    if (path == '/ridesharing/trips/my' ||
        path == '/driver/intercity/matching') {
      return Completer<Response<dynamic>>().future;
    }
    return super.get(path, queryParameters: queryParameters, options: options);
  }
}
