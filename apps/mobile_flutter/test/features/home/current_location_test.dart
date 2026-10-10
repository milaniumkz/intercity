import 'dart:convert';
import 'dart:async';
import 'package:intercity_mobile/core/utils/browser_location_error.dart';
import 'package:go_router/go_router.dart';
import 'package:intercity_mobile/core/utils/location_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/core/utils/browser_location_model.dart';
import 'package:intercity_mobile/core/utils/current_location.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';

class _LocationApi extends ApiClient {
  int reverseCalls = 0;
  bool confirmed = true;
  bool mapHomeEnabled = false;
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    dynamic data = <String, dynamic>{};
    if (path == '/geo/cities') {
      data = [
        {
          'id': 'almaty',
          'name': 'Алматы',
          'countryCode': 'KZ',
          'lat': 43.238949,
          'lng': 76.889709
        }
      ];
    }
    if (path == '/app/runtime-settings') {
      data = {'passengerMapHomeEnabled': mapHomeEnabled};
    }
    if (path == '/geo/reverse') {
      reverseCalls++;
      expect(queryParameters?['lat'], 49.902631);
      expect(queryParameters?['lng'], 82.609936);
      data = {
        'cityId': 'ust',
        'city': 'Усть-Каменогорск',
        'countryCode': 'KZ',
        'currency': 'KZT',
        'address': 'улица Оралхана Бокея, 24',
        'cityResolved': confirmed,
        'addressResolved': confirmed
      };
    }
    return Response(
        requestOptions: RequestOptions(path: path),
        data: data,
        statusCode: 200);
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    sharedLocationSession.clear();
  });
  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('pickup stays above the order panel at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _LocationApi()..mapHomeEnabled = true;
      await tester.pumpWidget(MaterialApp(
        home: OrderScreen(
          apiClient: api,
          enableLiveMap: false,
          locationProvider: () async => const BrowserLocation(
              latitude: 49.902631, longitude: 82.609936, accuracy: 10),
        ),
      ));
      await tester.pumpAndSettle();
      final marker =
          tester.getRect(find.byKey(const ValueKey('passenger-map-location')));
      final map =
          tester.getRect(find.byKey(const ValueKey('passenger-visible-map')));
      final panel =
          tester.getRect(find.byKey(const ValueKey('passenger-order-panel')));
      expect(find.byKey(const ValueKey('city-ride-selector')), findsNothing);
      expect(map.contains(marker.center), isTrue);
      expect(marker.bottom, lessThan(panel.top));
      expect(marker.center.dy, closeTo(map.center.dy, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final entry in {
    'Город': '/order/fixed',
    'Аукцион': '/order/auction',
    'Межгород': '/order/intercity_start',
    'Доставка': '/order'
  }.entries) {
    testWidgets('home only chooses mode and opens ${entry.key}',
        (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _LocationApi()..mapHomeEnabled = true;
      final router = GoRouter(initialLocation: '/order', routes: [
        GoRoute(
            path: '/order',
            builder: (c, s) => OrderScreen(
                apiClient: api,
                enableLiveMap: false,
                autoLocateOnStart: false)),
        GoRoute(
            path: '/order/:stage',
            builder: (c, s) => OrderScreen(
                routeStage: s.pathParameters['stage'],
                apiClient: api,
                enableLiveMap: false,
                autoLocateOnStart: false)),
      ]);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('Выберите режим'), findsOneWidget);
      expect(find.text('Указать куда'), findsNothing);
      expect(find.text('Моё местоположение'), findsNothing);
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, entry.value);
      expect(find.text('Выберите режим'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    });
  }
  testWidgets('GPS completing after navigation fills the new booking pickup',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fix = Completer<BrowserLocation?>();
    final session = LocationSession();
    var calls = 0;
    Future<BrowserLocation?> provider() {
      calls++;
      return fix.future;
    }

    final api = _LocationApi()..mapHomeEnabled = true;
    await tester.pumpWidget(MaterialApp(
        home: OrderScreen(
            key: const ValueKey('home'),
            apiClient: api,
            enableLiveMap: false,
            locationSession: session,
            locationProvider: provider)));
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(MaterialApp(
        home: OrderScreen(
            key: const ValueKey('booking'),
            routeStage: 'fixed',
            apiClient: api,
            enableLiveMap: false,
            locationSession: session,
            locationProvider: provider)));
    await tester.pump();
    await tester.pump();
    fix.complete(const BrowserLocation(
        latitude: 49.902631, longitude: 82.609936, accuracy: 10));
    await tester.pumpAndSettle();
    final draft = jsonDecode((await AppPreferences.getOrderDraft())!);
    expect(draft['fromLat'], 49.902631);
    expect(draft['fromAddress'], contains('Оралхана Бокея'));
    expect(calls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'GPS error retry requests location again and preserves destination',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await AppPreferences.setOrderDraft(jsonEncode({
      'modeIndex': 0,
      'cityModeIndex': 0,
      'toLat': 49.95,
      'toLng': 82.65,
      'toAddress': 'Сатпаева, 10',
      'toText': 'Сатпаева, 10'
    }));
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: OrderScreen(
            routeStage: 'fixed',
            apiClient: _LocationApi(),
            enableLiveMap: false,
            locationProvider: () async {
              calls++;
              if (calls == 1) {
                throw const BrowserLocationException(
                    BrowserLocationFailure.permissionDenied);
              }
              return const BrowserLocation(
                  latitude: 49.902631, longitude: 82.609936, accuracy: 10);
            })));
    await tester.pumpAndSettle();
    final message = find.textContaining('Браузер запретил местоположение');
    await tester.ensureVisible(message);
    await tester.pumpAndSettle();
    expect(message, findsOneWidget);
    final retry = find.byIcon(Icons.refresh_rounded);
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(calls, 2);
    final draft = jsonDecode((await AppPreferences.getOrderDraft())!);
    expect(draft['fromLat'], 49.902631);
    expect(draft['toLat'], 49.95);
    expect(draft['toAddress'], 'Сатпаева, 10');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('old, invalid and inaccurate fixes are not precise pickup coordinates',
      () {
    final now = DateTime(2026, 10, 6);
    expect(
        isReliableCurrentLocation(
            const BrowserLocation(
                latitude: 49.9, longitude: 82.6, accuracy: 15),
            now: now),
        isTrue);
    expect(
        isReliableCurrentLocation(
            const BrowserLocation(
                latitude: 49.9, longitude: 82.6, accuracy: 1200),
            now: now),
        isFalse);
    expect(
        isReliableCurrentLocation(
            BrowserLocation(
                latitude: 49.9,
                longitude: 82.6,
                accuracy: 10,
                timestamp: now.subtract(const Duration(minutes: 10))),
            now: now),
        isFalse);
    expect(
        isReliableCurrentLocation(
            const BrowserLocation(latitude: 100, longitude: 82.6, accuracy: 10),
            now: now),
        isFalse);
  });
  for (final precise in [true, false]) {
    testWidgets('default location uses fresh device position; precise=$precise',
        (tester) async {
      await AppPreferences.setCurrentCityId('old-almaty');
      await AppPreferences.setCurrentCityName('Алматы');
      final api = _LocationApi();
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: OrderScreen(
              routeStage: 'mode',
              apiClient: api,
              enableLiveMap: false,
              locationProvider: () async => BrowserLocation(
                  latitude: 49.902631,
                  longitude: 82.609936,
                  accuracy: precise ? 10 : 1200))));
      await tester.pumpAndSettle();
      expect(find.text('Город: Алматы · ₸'), findsNothing);
      if (precise) {
        expect(find.text('Город: Усть-Каменогорск · ₸'), findsOneWidget);
        final draft = jsonDecode((await AppPreferences.getOrderDraft())!);
        expect(draft['fromLat'], 49.902631);
        expect(draft['fromLng'], 82.609936);
        expect(draft['fromAddress'], contains('Оралхана Бокея'));
        expect(api.reverseCalls, greaterThan(0));
      } else {
        expect(find.text('Выбрать город поездки'), findsOneWidget);
        expect(api.reverseCalls, 0);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
      'confirmed city survives returning to a new order without forging a GPS pickup',
      (tester) async {
    final session = LocationSession();
    session.city = {
      'id': 'ust',
      'name': 'Усть-Каменогорск',
      'lat': 49.902631,
      'lng': 82.609936,
      'currency': 'KZT'
    };
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: OrderScreen(
            routeStage: 'mode',
            apiClient: _LocationApi(),
            locationSession: session,
            enableLiveMap: false,
            autoLocateOnStart: false)));
    await tester.pumpAndSettle();
    expect(find.text('Город: Усть-Каменогорск · ₸'), findsOneWidget);
    expect(await AppPreferences.getOrderDraft(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'stored city does not suppress default GPS pickup in city booking',
      (tester) async {
    await AppPreferences.setOrderCity(
        {'name': 'Жетекші', 'lat': 52.3, 'lng': 77.0, 'countryCode': 'KZ'});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: OrderScreen(
            routeStage: 'fixed',
            apiClient: _LocationApi(),
            enableLiveMap: false,
            locationProvider: () async {
              calls++;
              return const BrowserLocation(
                  latitude: 49.902631, longitude: 82.609936, accuracy: 10);
            })));
    await tester.pumpAndSettle();
    final draft = jsonDecode((await AppPreferences.getOrderDraft())!);
    expect(calls, 1);
    expect(draft['fromLat'], 49.902631);
    expect(draft['fromAddress'], contains('Оралхана Бокея'));
    expect(await AppPreferences.getOrderCity(), isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('automatic location preserves an explicitly saved pickup',
      (tester) async {
    await AppPreferences.setOrderCity(
        {'name': 'Омск', 'lat': 54.989, 'lng': 73.368, 'countryCode': 'RU'});
    await AppPreferences.setOrderDraft(jsonEncode({
      'modeIndex': 0,
      'cityModeIndex': 0,
      'fromLat': 54.99,
      'fromLng': 73.37,
      'fromAddress': 'Ленина, 10',
      'fromText': 'Ленина, 10'
    }));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: OrderScreen(
            routeStage: 'fixed',
            apiClient: _LocationApi(),
            enableLiveMap: false,
            locationProvider: () async {
              calls++;
              return const BrowserLocation(
                  latitude: 49.902631, longitude: 82.609936, accuracy: 10);
            })));
    await tester.pumpAndSettle();
    expect(calls, 0);
    final draft = jsonDecode((await AppPreferences.getOrderDraft())!);
    expect(draft['fromLat'], 54.99);
    expect(draft['fromText'], 'Ленина, 10');
    expect((await AppPreferences.getOrderCity())?['name'], 'Омск');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'manual city selection is preserved instead of being replaced by GPS',
      (tester) async {
    await AppPreferences.setOrderCity(
        {'name': 'Омск', 'lat': 54.989, 'lng': 73.368, 'countryCode': 'RU'});
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    int calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: OrderScreen(
            routeStage: 'mode',
            apiClient: _LocationApi(),
            enableLiveMap: false,
            locationProvider: () async {
              calls++;
              return const BrowserLocation(
                  latitude: 49.902631, longitude: 82.609936, accuracy: 10);
            })));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Город: Омск · ₽'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
