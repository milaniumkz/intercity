import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';

Map<String, dynamic> intercityDraft() => {
      'modeIndex': 1,
      'intercityFromCityId': 'from',
      'intercityToCityId': 'to',
      'intercityFromCityName': 'Жетекши',
      'intercityToCityName': 'Усть-Каменогорск',
      'fromText': 'Ауэзова 8',
      'toText': 'Назарбаева 8/1',
      'fromAddress': 'Ауэзова 8',
      'toAddress': 'Назарбаева 8/1',
      'fromLat': 52.3,
      'fromLng': 76.9,
      'toLat': 49.96,
      'toLng': 82.61,
      'intercityTripDate': '2030-10-15T12:45:00.000Z',
      'intercityDateConfirmed': true,
      'intercitySeats': 2,
      'intercityBaggage': 2,
      'comment': 'С чемоданом',
      'paymentMethod': 'CASH',
    };
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
      'explicit next retains chosen day, time and options through route recreation and submission',
      (tester) async {
    tester.view.physicalSize = const Size(392, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await AppPreferences.setOrderDraft(jsonEncode(intercityDraft()));
    final api = IntercityFlowApi();
    final router = GoRouter(initialLocation: '/order/intercity_start', routes: [
      for (final stage in ['intercity_start', 'intercity_options'])
        GoRoute(
            path: '/order/$stage',
            builder: (_, state) => OrderScreen(
                key: ValueKey(stage),
                routeStage: stage,
                apiClient: api,
                enableLiveMap: false,
                autoLocateOnStart: false)),
      GoRoute(
          path: '/market/request/:id',
          builder: (_, state) =>
              const Scaffold(body: Text('Запрос опубликован'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('15.10.2030'), findsOneWidget);
    expect(find.text('12:45'), findsOneWidget);
    await tester.tap(find.text('Далее: параметры поездки'));
    await tester.pumpAndSettle();
    expect(find.text('Параметры поездки'), findsOneWidget);
    expect(find.text('15.10.2030'), findsOneWidget);
    final saved = jsonDecode((await AppPreferences.getOrderDraft())!) as Map;
    expect(saved['intercityTripDate'], '2030-10-15T12:45:00.000Z');
    expect(saved['intercitySeats'], 2);
    expect(saved['comment'], 'С чемоданом');
    await tester.tap(find.text('Найти водителя'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.created, hasLength(1));
    expect(api.created.single['date'], '2030-10-15T12:45:00.000Z');
    expect(api.created.single['fromCity'], 'Жетекши');
    expect(api.created.single['toCity'], 'Усть-Каменогорск');
    expect(api.created.single['seats'], 2);
    expect(find.text('Запрос опубликован'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'selecting destination search result stays on route step for date selection',
      (tester) async {
    final draft = intercityDraft()
      ..remove('toLat')
      ..remove('toLng');
    await AppPreferences.setOrderDraft(jsonEncode(draft));
    final api = IntercityFlowApi();
    await tester.pumpWidget(MaterialApp(
        home: OrderScreen(
            routeStage: 'intercity_start',
            apiClient: api,
            enableLiveMap: false,
            autoLocateOnStart: false)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Найти адрес').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Маршрут и время'), findsOneWidget);
    expect(find.text('Дата и время отправления'), findsOneWidget);
    expect(api.created, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}

class IntercityFlowApi extends ApiClient {
  final created = <Map>[];
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    dynamic data = [];
    if (path == '/app/runtime-settings') data = {};
    if (path == '/geo/cities') {
      data = [
        {
          'id': 'from',
          'name': 'Жетекши',
          'lat': 52.3,
          'lng': 76.9,
          'countryCode': 'KZ'
        },
        {
          'id': 'to',
          'name': 'Усть-Каменогорск',
          'lat': 49.96,
          'lng': 82.61,
          'countryCode': 'KZ'
        }
      ];
    }
    if (path.contains('/geo/search')) {
      data = [
        {
          'label': 'Назарбаева 8/1',
          'lat': 49.96,
          'lng': 82.61,
          'city': 'Усть-Каменогорск',
          'cityId': 'to'
        }
      ];
    }
    if (path == '/route') {
      data = {'distanceKm': 360, 'durationMinutes': 300, 'points': []};
    }
    return Response(requestOptions: RequestOptions(path: path), data: data);
  }

  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data, Options? options}) async {
    if (path == '/intercity/requests') {
      created.add(Map.from(data));
      return Response(
          requestOptions: RequestOptions(path: path),
          data: {'id': 'published'});
    }
    return Response(
        requestOptions: RequestOptions(path: path),
        data: {'price': 7000, 'distanceKm': 360, 'durationMinutes': 300});
  }
}
