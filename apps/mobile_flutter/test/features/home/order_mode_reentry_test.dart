import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/core/utils/browser_location_model.dart';
import 'package:intercity_mobile/core/utils/location_session.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';

class _SlowRestoredRouteApi extends ApiClient {
  final route = Completer<Response<dynamic>>();
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    if (path == '/route') return route.future;
    return Response(
        requestOptions: RequestOptions(path: path),
        data: path == '/geo/cities'
            ? <dynamic>[]
            : path == '/app/runtime-settings'
                ? {'passengerMapHomeEnabled': true}
                : path == '/geo/reverse'
                    ? {
                        'cityId': 'ust',
                        'city': 'Усть-Каменогорск',
                        'address': 'Шакарима 143',
                        'countryCode': 'KZ',
                        'cityResolved': true,
                        'addressResolved': true
                      }
                    : <String, dynamic>{});
  }
}

void main() {
  testWidgets(
      'restoring auction does not hold current location behind a slow previous route',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await AppPreferences.setOrderDraft(jsonEncode({
      'modeIndex': 0,
      'cityModeIndex': 1,
      'fromLat': 49.97,
      'fromLng': 82.61,
      'toLat': 49.94,
      'toLng': 82.62,
      'fromText': 'Шакарима 143',
      'toText': 'Ленина 10',
      'auctionPrice': '4000'
    }));
    final api = _SlowRestoredRouteApi();
    var locations = 0;
    await tester.pumpWidget(MaterialApp(
        home: OrderScreen(
            routeStage: 'auction',
            enableLiveMap: false,
            apiClient: api,
            locationSession: LocationSession(),
            locationProvider: () async {
              locations++;
              return const BrowserLocation(
                  latitude: 49.97, longitude: 82.61, accuracy: 10);
            })));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    final observed = locations;
    api.route.complete(Response(
        requestOptions: RequestOptions(path: '/route'),
        data: {'distance': 3, 'duration': 5}));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    expect(observed, 1,
        reason:
            'a cached draft must not wait for road calculation before positioning the map');
  });
}
