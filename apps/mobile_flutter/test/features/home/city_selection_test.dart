import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';

class _CityApi extends ApiClient {
  final queries = <String>[];
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    return Response(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: path == '/geo/cities'
            ? <dynamic>[]
            : path == '/app/runtime-settings'
                ? {'passengerMapHomeEnabled': false}
                : <String, dynamic>{});
  }

  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data,
      Map<String, dynamic>? queryParameters,
      Options? options}) async {
    queries.add(data['q'] as String);
    final ru = data['q'] == 'Омск';
    return Response(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: [
          {
            'name': ru ? 'Омск' : 'Алматы',
            'displayName': ru ? 'Омск, Россия' : 'Алматы, Казахстан',
            'countryCode': ru ? 'RU' : 'KZ',
            'lat': ru ? 54.989 : 43.222,
            'lng': ru ? 73.368 : 76.851
          },
        ]);
  }
}

void main() {
  testWidgets(
      'city search selects Omsk in RUB, persists it, and switches to KZT',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = _CityApi();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> show({bool locate = false}) async {
      await tester.pumpWidget(MaterialApp(
          home: OrderScreen(
              key: UniqueKey(),
              routeStage: 'mode',
              apiClient: api,
              enableLiveMap: false,
              autoLocateOnStart: locate)));
      await tester.pumpAndSettle();
    }

    Future<void> choose(String city) async {
      await tester.tap(find.byKey(const ValueKey('city-ride-selector')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), city);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).last);
      await tester.pumpAndSettle();
    }

    await show();
    await choose('Омск');
    expect(find.text('Город: Омск · ₽'), findsOneWidget);
    expect(api.queries.last, 'Омск');
    expect((await AppPreferences.getOrderCity())!['lng'], 73.368);
    final draft = jsonDecode((await AppPreferences.getOrderDraft())!);
    expect(draft['fromLat'], isNull);
    expect(draft['toLat'], isNull);
    await show(locate: true);
    expect(find.text('Город: Омск · ₽'), findsOneWidget);
    await choose('Алматы');
    expect(find.text('Город: Алматы · ₸'), findsOneWidget);
    expect((await AppPreferences.getOrderCity())!['countryCode'], 'KZ');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
