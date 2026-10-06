import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';

class _OrderApi extends ApiClient {
  _OrderApi(this.status, this.failure);
  final int status;
  final Map<String, dynamic> failure;
  int creates = 0;
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    return Response(
        requestOptions: RequestOptions(path: path),
        data: path == '/geo/cities'
            ? <dynamic>[]
            : <String, dynamic>{'passengerMapHomeEnabled': false});
  }

  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data,
      Map<String, dynamic>? queryParameters,
      Options? options}) async {
    expect(path, '/orders');
    expect(data['paymentMethod'], 'CASH');
    expect(data['vehicleClass'], 'ECONOMY');
    creates++;
    final request = RequestOptions(path: path);
    throw DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(
            requestOptions: request, statusCode: status, data: failure));
  }
}

void main() {
  for (final type in ['CITY', 'INTERCITY', 'BONUS']) {
    testWidgets('order submission handles $type server response',
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
        'fromAddress': 'проспект Шакарима, 10',
        'toAddress': 'улица Серикбаева, 8/1А',
        'boardPrice': 700,
        'boardDistance': 2.1,
        'boardDuration': 4,
        'rideCurrency': 'KZT'
      }));
      final api = _OrderApi(
          type == 'BONUS' ? 400 : 409,
          type == 'BONUS'
              ? {'message': 'Insufficient bonus balance'}
              : {
                  'code': 'ACTIVE_ORDER_EXISTS',
                  'activeOrderId': 'existing',
                  'activeOrderType': type
                });
      final router = GoRouter(initialLocation: '/confirm', routes: [
        GoRoute(
            path: '/confirm',
            builder: (context, state) => OrderScreen(
                routeStage: 'confirm',
                apiClient: api,
                enableLiveMap: false,
                autoLocateOnStart: false)),
        GoRoute(
            path: '/order/searching/:id',
            builder: (_, state) =>
                Text('Active city ${state.pathParameters['id']}')),
        GoRoute(
            path: '/market/request/:id',
            builder: (_, state) =>
                Text('Active intercity ${state.pathParameters['id']}')),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      final submit = find.text('Заказать');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(api.creates, 1);
      if (type == 'CITY') {
        expect(find.text('Active city existing'), findsOneWidget);
      } else if (type == 'INTERCITY') {
        expect(find.text('Active intercity existing'), findsOneWidget);
      } else {
        expect(find.textContaining('Недостаточно бонусов'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
