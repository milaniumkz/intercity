import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';
import 'package:intercity_mobile/features/passenger/screens/order_page.dart';

class _EntryApi extends ApiClient {
  _EntryApi(this.type);
  final String type;
  int checks = 0;
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    dynamic data = <String, dynamic>{};
    if (path == '/orders/active') {
      checks++;
      data = type == 'NONE' ? null : {'id': 'existing', 'type': type};
    }
    if (path == '/geo/cities') data = <dynamic>[];
    if (path == '/app/runtime-settings') {
      data = {'passengerMapHomeEnabled': false};
    }
    return Response(requestOptions: RequestOptions(path: path), data: data);
  }
}

void main() {
  for (final type in ['CITY', 'INTERCITY', 'NONE']) {
    testWidgets('entry opens $type or a new order form', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _EntryApi(type);
      final router = GoRouter(initialLocation: '/order', routes: [
        GoRoute(
            path: '/order', builder: (_, state) => OrderPage(apiClient: api)),
        GoRoute(
            path: '/order/searching/:id',
            builder: (_, state) => const Text('Existing city order')),
        GoRoute(
            path: '/market/request/:id',
            builder: (_, state) => const Text('Existing intercity order')),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(api.checks, 1);
      if (type == 'NONE') {
        expect(find.byType(OrderScreen), findsOneWidget);
      } else {
        expect(
            find.text(type == 'CITY'
                ? 'Existing city order'
                : 'Existing intercity order'),
            findsOneWidget);
        expect(find.byType(OrderScreen), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 20));
    });
  }
}
