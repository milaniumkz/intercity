import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';

class _FlowApi extends ApiClient {
  final calls = <String>[];
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
    calls.add(path);
    expect(data['vehicleClass'], 'COMFORT');
    return Response(
        requestOptions: RequestOptions(path: path),
        data: path == '/orders/preview'
            ? {'price': 900, 'currency': 'KZT', 'distance': 2.1, 'duration': 4}
            : {'id': 'new-ride'});
  }
}

void main() {
  testWidgets(
      'class precedes addresses with price, then payment submits directly',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await AppPreferences.setOrderDraft(jsonEncode({
      'fromLat': 49.95,
      'fromLng': 82.6,
      'toLat': 49.96,
      'toLng': 82.61,
      'fromAddress': 'Шакарима 10',
      'toAddress': 'Серикбаева 8/1А',
      'boardPrice': 700,
      'rideCurrency': 'KZT'
    }));
    final api = _FlowApi();
    final router = GoRouter(initialLocation: '/order/class', routes: [
      GoRoute(
          path: '/order/:stage',
          builder: (_, state) => OrderScreen(
              routeStage: state.pathParameters['stage'],
              apiClient: api,
              enableLiveMap: false,
              autoLocateOnStart: false)),
      GoRoute(
          path: '/order/searching/:id',
          builder: (_, __) => const Text('Поиск водителя'))
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Комфорт'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Заказ поездки'), findsOneWidget);
    expect(find.text('900 ₸'), findsOneWidget);
    await tester.ensureVisible(find.text('Продолжить'));
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(find.text('Способ оплаты'), findsOneWidget);
    expect(find.text('Подтвердите заказ'), findsNothing);
    await tester.ensureVisible(find.text('Заказать'));
    await tester.tap(find.text('Заказать'));
    await tester.pumpAndSettle();
    expect(api.calls.where((e) => e == '/orders').length, 1);
    expect(find.text('Поиск водителя'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
