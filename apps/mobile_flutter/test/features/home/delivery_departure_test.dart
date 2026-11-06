import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';

class DeliveryApi extends ApiClient {
  Map? created;
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(
          requestOptions: RequestOptions(path: path),
          data:
              path == '/geo/cities' ? [] : {'passengerMapHomeEnabled': false});
  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data,
      Map<String, dynamic>? queryParameters,
      Options? options}) async {
    if (path == '/intercity/requests') created = data as Map;
    return Response(
        requestOptions: RequestOptions(path: path),
        data: {'id': 'delivery-test'});
  }
}

void main() {
  testWidgets(
      'delivery date and time are explicitly selected, survive steps and reach creation',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(600, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await AppPreferences.setOrderCity({
      'id': 'ust',
      'name': 'Усть-Каменогорск',
      'lat': 49.95,
      'lng': 82.6,
      'countryCode': 'KZ'
    });
    await AppPreferences.setOrderDraft(jsonEncode({
      'modeIndex': 2,
      'deliveryModeIndex': 0,
      'fromLat': 49.95,
      'fromLng': 82.6,
      'toLat': 49.96,
      'toLng': 82.61,
      'fromText': 'Шакарима 143',
      'toText': 'Сатпаева 1',
      'itemDescription': 'Кровать',
      'paymentMethod': 'CASH'
    }));
    final api = DeliveryApi();
    final router = GoRouter(initialLocation: '/order', routes: [
      GoRoute(
          path: '/order',
          builder: (_, __) => OrderScreen(
              initialStep: 2,
              apiClient: api,
              enableLiveMap: false,
              autoLocateOnStart: false)),
      GoRoute(
          path: '/market/request/:id',
          builder: (_, __) => const Text('Delivery created'))
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        locale: const Locale('ru'),
        supportedLocales: const [
          Locale('ru')
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ]));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('delivery-departure'));
    expect(field, findsOneWidget);
    expect(find.text('Выбрать дату и время'), findsOneWidget);
    await tester.ensureVisible(field);
    await tester.tap(find.text('Выбрать дату и время'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Переключиться на ручной ввод'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final selected = DateTime(now.year, now.month, now.day + 2, 17, 45);
    String two(int n) => n.toString().padLeft(2, '0');
    await tester.enterText(
        find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.byType(TextField)),
        '${two(selected.day)}.${two(selected.month)}.${selected.year}');
    await tester.tap(find.text('Далее').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Перейти в режим ввода текста'));
    await tester.pumpAndSettle();
    final times = find.descendant(
        of: find.byType(TimePickerDialog), matching: find.byType(TextField));
    await tester.enterText(times.first, '17');
    await tester.enterText(times.last, '45');
    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();
    final saved = jsonDecode((await AppPreferences.getOrderDraft())!);
    expect(DateTime.parse(saved['intercityDate']).toLocal(), selected);
    await tester.ensureVisible(find.text('Далее'));
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Опубликовать доставку'));
    await tester.tap(find.text('Опубликовать доставку'));
    await tester.pumpAndSettle();
    expect(api.created, isNotNull);
    expect(api.created!['fromCity'], 'Усть-Каменогорск');
    expect(DateTime.parse(api.created!['date']).toLocal(), selected);
    expect(find.text('Delivery created'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
