import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';

class _CargoApi extends ApiClient {
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
    if (path == '/orders/preview') {
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
  testWidgets(
      'cargo draft preserves freight details and submits a fixed cargo order',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await AppPreferences.setOrderDraft(jsonEncode({
      'modeIndex': 3,
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
    expect(api.created!['mode'], 'CARGO');
    expect(api.created!['itemWeightKg'], 25);
    expect(api.created!['itemDescription'], 'Шкаф');
    expect(api.created!['itemDimensions'], '80x60x100');
    expect(api.created!['recipientContact'], '+77000000000');
    expect(tester.takeException(), isNull);
  });
}
