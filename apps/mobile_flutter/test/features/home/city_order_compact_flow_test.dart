import 'dart:async';
import 'dart:convert';
import '../../support/memory_tile_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/core/utils/location_session.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';

class _FlowApi extends ApiClient {
  final previews = <Map<String, dynamic>>[];
  final orders = <Map<String, dynamic>>[];
  final reverses = <double, Completer<Response<dynamic>>>{};
  bool delayReverse = false;
  Completer<Response<dynamic>>? create;
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    dynamic data = <String, dynamic>{};
    if (path == '/geo/cities') data = [];
    if (path == '/app/runtime-settings') {
      data = {'passengerMapHomeEnabled': false};
    }
    if (path == '/payments/cards') data = {'configured': false, 'cards': []};
    if (path == '/geo/search') {
      data = [
        {
          'displayName': 'Серикбаева 8/1А',
          'lat': 49.96,
          'lng': 82.61,
          'countryCode': 'KZ'
        }
      ];
    }
    if (path == '/geo/reverse') {
      if (delayReverse) {
        final c = Completer<Response<dynamic>>();
        reverses[(queryParameters!['lat'] as num).toDouble()] = c;
        return c.future;
      }
      data = {
        'address': 'Назарбаева 8/1',
        'city': 'Усть-Каменогорск',
        'cityId': 'kz-osk',
        'countryCode': 'KZ',
        'addressResolved': true,
        'cityResolved': true
      };
    }
    if (path == '/route') {
      data = {
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [82.6, 49.95],
            [82.605, 49.955],
            [82.61, 49.96]
          ]
        },
        'duration': 4
      };
    }
    return Response(requestOptions: RequestOptions(path: path), data: data);
  }

  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data,
      Map<String, dynamic>? queryParameters,
      Options? options}) async {
    final body = Map<String, dynamic>.from(data as Map);
    if (path == '/orders/preview') {
      previews.add(body);
      return Response(requestOptions: RequestOptions(path: path), data: {
        'price': body['vehicleClass'] == 'COMFORT' ? 900 : 700,
        'currency': 'KZT',
        'distance': 2.1,
        'duration': 4
      });
    }
    orders.add(body);
    if (create != null) return create!.future;
    return Response(
        requestOptions: RequestOptions(path: path), data: {'id': 'new-ride'});
  }
}

Future<GoRouter> _open(WidgetTester tester, _FlowApi api,
    {bool destination = true,
    bool live = false,
    Size size = const Size(360, 740),
    String payment = 'CASH'}) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await AppPreferences.setOrderDraft(jsonEncode({
    'fromLat': 49.95,
    'fromLng': 82.6,
    'fromAddress': 'Шакарима 10',
    if (destination) ...{
      'toLat': 49.96,
      'toLng': 82.61,
      'toAddress': 'Серикбаева 8/1А',
      'boardPrice': 700
    },
    'rideCurrency': 'KZT',
    'paymentMethod': payment,
  }));
  final router = GoRouter(initialLocation: '/order/fixed', routes: [
    GoRoute(
        path: '/order/searching/:id',
        builder: (_, __) => const Scaffold(body: Text('Поиск водителя'))),
    GoRoute(
        path: '/order/:stage',
        builder: (_, state) => OrderScreen(
            routeStage: state.pathParameters['stage'],
            apiClient: api,
            enableLiveMap: live,
            autoLocateOnStart: false,
            mapTileProvider: MemoryTileProvider(),
            locationSession: LocationSession())),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets(
      'default economy prices the selected destination on the same screen',
      (tester) async {
    final api = _FlowApi();
    final router = await _open(tester, api, destination: false);
    expect(find.text('Заказ поездки'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('city-payment-CARD_TRANSFER')), findsNothing);
    await tester.enterText(
        find.byKey(const ValueKey('city-address-to')), 'Серикбаева');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('city-suggestion-0')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(api.previews.last['vehicleClass'], 'ECONOMY');
    expect(find.text('700 ₸'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/order/fixed');
    expect(find.text('Оплата'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'tariff changes reprice inline and duplicate submission is disabled',
      (tester) async {
    final api = _FlowApi();
    api.create = Completer();
    await _open(tester, api, payment: 'CARD_TRANSFER');
    await tester.tap(find.byKey(const ValueKey('city-class-COMFORT')));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('900 ₸'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('city-order-submit')));
    await tester.pump();
    expect(api.orders.single['vehicleClass'], 'COMFORT');
    expect(api.orders.single['paymentMethod'], 'CASH');
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('city-order-submit')))
            .onPressed,
        isNull);
    api.create!.complete(Response(
        requestOptions: RequestOptions(path: '/orders'),
        data: {'id': 'new-ride'}));
    await tester.pumpAndSettle();
    expect(find.text('Поиск водителя'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'small screen keeps map, payment and order button visible; typed edits invalidate the price',
      (tester) async {
    tester.view.padding = const FakeViewPadding(bottom: 24);
    final api = _FlowApi();
    await _open(tester, api, size: const Size(320, 568));
    expect(
        tester.getRect(find.byKey(const ValueKey('city-order-submit'))).bottom,
        lessThanOrEqualTo(544));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('city-payment-CASH')).hitTestable(),
        findsOneWidget);
    expect(find.byKey(const ValueKey('city-order-submit')).hitTestable(),
        findsOneWidget);
    expect(tester.getRect(find.byKey(const ValueKey('city-address-from'))).top,
        greaterThan(80));
    await tester.enterText(
        find.byKey(const ValueKey('city-address-to')), 'Другой адрес');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('city-order-submit')))
            .onPressed,
        isNull);
    expect(find.text('700 ₸'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'map taps fill the chosen field and late reverse results cannot overwrite a newer point',
      (tester) async {
    final api = _FlowApi();
    await _open(tester, api, live: true);
    api.delayReverse = true;
    final map =
        tester.widget<FlutterMap>(find.byKey(const ValueKey('city-live-map')));
    map.options.onTap!(const TapPosition(Offset.zero, Offset.zero),
        const LatLng(49.97, 82.62));
    await tester.pump();
    map.options.onTap!(const TapPosition(Offset.zero, Offset.zero),
        const LatLng(49.98, 82.63));
    await tester.pump();
    api.reverses[49.98]!.complete(Response(
        requestOptions: RequestOptions(path: '/geo/reverse'),
        data: {'address': 'Новый адрес 24', 'addressResolved': true}));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    api.reverses[49.97]!.complete(Response(
        requestOptions: RequestOptions(path: '/geo/reverse'),
        data: {'address': 'Старый адрес 10', 'addressResolved': true}));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('city-address-to')))
            .controller!
            .text,
        contains('Новый адрес 24'));
    expect(api.previews.last['toLat'], 49.98);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('city-address-from')))
            .controller!
            .text,
        'Шакарима 10');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
