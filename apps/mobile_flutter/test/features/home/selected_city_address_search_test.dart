import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';

class _AddressApi extends ApiClient {
  Map<String, dynamic>? search;
  int calls = 0;
  bool fail = false;
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    dynamic data = <String, dynamic>{};
    if (path == '/geo/cities') data = <dynamic>[];
    if (path == '/app/runtime-settings') {
      data = {'passengerMapHomeEnabled': false};
    }
    if (path == '/geo/search') {
      calls++;
      search = queryParameters;
      if (fail) throw Exception('offline');
      data = [
        {
          'displayName': 'Омск, улица Ленина, 10',
          'lat': 54.99,
          'lng': 73.37,
          'countryCode': 'RU'
        }
      ];
    }
    return Response(
        requestOptions: RequestOptions(path: path),
        data: data,
        statusCode: 200);
  }
}

void main() {
  testWidgets(
      'typing is debounced and a failed search can recover without direct providers',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await AppPreferences.setOrderCity(
        {'name': 'Омск', 'lat': 54.989, 'lng': 73.368, 'countryCode': 'RU'});
    final api = _AddressApi()..fail = true;
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: OrderScreen(
            routeStage: 'address',
            apiClient: api,
            enableLiveMap: false,
            autoLocateOnStart: false)));
    await tester.pumpAndSettle();
    final field = find.byType(TextField).first;
    await tester.enterText(field, 'Лен');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, 'Ленина');
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.calls, 0);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    expect(find.textContaining('Не удалось выполнить поиск адреса.'),
        findsWidgets);
    api.fail = false;
    await tester.enterText(field, 'Ленина 10');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(api.calls, 2);
    expect(find.text('Омск, улица Ленина, 10'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'address search uses selected Omsk instead of the stored Tyumen city',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await AppPreferences.setCurrentCityId('old-tyumen-id');
    await AppPreferences.setOrderCity(
        {'name': 'Омск', 'lat': 54.989, 'lng': 73.368, 'countryCode': 'RU'});
    final api = _AddressApi();
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: OrderScreen(
            routeStage: 'address',
            apiClient: api,
            enableLiveMap: false,
            autoLocateOnStart: false)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ленина 10');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(api.search, isNotNull);
    expect(api.search!['lat'], 54.989);
    expect(api.search!['lng'], 73.368);
    expect(api.search!.containsKey('cityId'), isFalse);
    expect(find.text('Омск, улица Ленина, 10'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
