import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';
import 'package:intercity_mobile/features/driver/widgets/route_departure_field.dart';

class _CargoApi extends ApiClient {
  Map? created;
  bool missingTariff = false;
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
    if (path == '/orders/preview') {
      if (missingTariff) {
        throw DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.badResponse,
          response: Response(
              requestOptions: RequestOptions(path: path),
              statusCode: 400,
              data: {
                'message':
                    'Грузовой тариф для страны отправления не настроен. Обратитесь в поддержку'
              }),
        );
      }
      return Response(requestOptions: RequestOptions(path: path), data: {
        'price': 1500,
        'currency': 'KZT',
        'distance': 2,
        'duration': 3
      });
    }
    expect(path, '/orders');
    created = data as Map;
    return Response(
        requestOptions: RequestOptions(path: path), data: {'id': 'cargo-id'});
  }
}

void main() {
  testWidgets('cargo exposes tariff error and retries calculation',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(AppPreferences.clearOrderDraft);
    await AppPreferences.setOrderDraft(jsonEncode({
      'modeIndex': 3,
      'fromLat': 43.24,
      'fromLng': 76.94,
      'toLat': 43.25,
      'toLng': 76.95,
      'fromText': 'Точка А',
      'toText': 'Точка Б',
      'fromAddress': 'Точка А',
      'toAddress': 'Точка Б',
      'cargoScheduledFor':
          DateTime.now().add(const Duration(days: 2)).toUtc().toIso8601String(),
      'itemDescription': 'Шкаф',
      'itemWeightKg': '25',
    }));
    final api = _CargoApi()..missingTariff = true;
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => OrderScreen(
              initialStep: 2,
              apiClient: api,
              enableLiveMap: false,
              autoLocateOnStart: false))
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(
        find.textContaining(
            'Грузовой тариф для страны отправления не настроен'),
        findsWidgets);
    expect(api.created, isNull);
    api.missingTariff = false;
    await tester.ensureVisible(find.text('Повторить расчёт'));
    await tester.tap(find.text('Повторить расчёт'));
    await tester.pumpAndSettle();
    expect(find.text('Расчётная цена'), findsOneWidget);
    expect(find.text('Повторить расчёт'), findsNothing);
  });
  testWidgets(
      'cargo draft preserves freight details and submits a fixed cargo order',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await AppPreferences.setOrderDraft(jsonEncode({
      'modeIndex': 3,
      'intercityDate':
          DateTime.now().add(const Duration(days: 1)).toUtc().toIso8601String(),
      'cargoScheduledFor': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toUtc()
          .toIso8601String(),
      'fromLat': 43.24,
      'fromLng': 76.94,
      'toLat': 43.25,
      'toLng': 76.95,
      'fromAddress': 'Точка А',
      'toAddress': 'Точка Б',
      'fromText': 'Точка А',
      'toText': 'Точка Б',
      'boardPrice': 1500,
      'boardDistance': 2,
      'boardDuration': 3,
      'itemDescription': 'Шкаф',
      'itemWeightKg': '25',
      'itemDimensions': '80x60x100',
      'recipientContact': '+77000000000'
    }));
    final api = _CargoApi();
    final router = GoRouter(initialLocation: '/order', routes: [
      GoRoute(
          path: '/order',
          builder: (_, __) => OrderScreen(
              initialStep: 1,
              apiClient: api,
              enableLiveMap: false,
              autoLocateOnStart: false)),
      GoRoute(
          path: '/order/searching/:id',
          builder: (_, __) => const Scaffold(body: Text('Cargo created')))
    ]);
    addTearDown(router.dispose);
    addTearDown(AppPreferences.clearOrderDraft);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'route step');
    expect(
        tester
            .widget<RouteDepartureField>(
                find.byKey(const ValueKey('cargo-departure')))
            .value,
        isNull);
    expect(find.text('Выбрать дату и время'), findsOneWidget);
    expect(api.created, isNull);
    await tester.ensureVisible(find.text('Далее'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();
    expect(find.text('Параметры груза'), findsNothing);
    expect(api.created, isNull);
    await tester.ensureVisible(find.text('Выбрать дату и время'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать дату и время'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(DatePickerDialog), matching: find.text('Далее')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(TimePickerDialog), matching: find.text('Отмена')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<RouteDepartureField>(
                find.byKey(const ValueKey('cargo-departure')))
            .value,
        isNull);
    final now = DateTime.now();
    final selected = DateTime(now.year, now.month, now.day + 2, 17, 45);
    tester
        .widget<RouteDepartureField>(
            find.byKey(const ValueKey('cargo-departure')))
        .onChanged(selected);
    await tester.pumpAndSettle();

    for (var step = 0; step < 2; step++) {
      final next = find.text('Далее');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'step $step');
    }
    expect(find.text('Класс'), findsNothing);
    expect(find.text('25'), findsOneWidget);
    expect(find.text('Шкаф'), findsOneWidget);
    await tester.tap(find.text('Создать заказ'));
    await tester.pumpAndSettle();
    expect(find.text('Cargo created'), findsOneWidget);
    expect(api.created!['requestType'], 'CARGO');
    expect(api.created!['scheduledFor'], selected.toUtc().toIso8601String());
    expect(api.created!['mode'], 'CARGO');
    expect(api.created!['itemWeightKg'], 25);
    expect(api.created!['itemDescription'], 'Шкаф');
    expect(api.created!['itemDimensions'], '80x60x100');
    expect(api.created!['recipientContact'], '+77000000000');
    expect(tester.takeException(), isNull);
  });
}
