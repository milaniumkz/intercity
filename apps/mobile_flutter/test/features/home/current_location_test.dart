import 'dart:convert';
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
      data = {'passengerMapHomeEnabled': false};
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
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
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
