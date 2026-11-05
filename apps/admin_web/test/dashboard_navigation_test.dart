import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_admin/core/api/admin_api_client.dart';
import 'package:intercity_admin/features/admin/widgets/dashboard_statistics.dart';

class _Api implements AdminApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? query}) async =>
      Response(requestOptions: RequestOptions(path: path), data: {
        'range': {
          'from': '2026-11-04T19:00:00.000Z',
          'to': '2026-11-05T19:00:00.000Z'
        },
        'users': {'newPassengers': 3, 'newDrivers': 2},
        'orders': {'completed': 4},
      });
}

void main() {
  testWidgets(
      'dashboard cards preserve the period and category in the opened list',
      (tester) async {
    AdminApiClient.debugOverride(_Api());
    addTearDown(() => AdminApiClient.debugOverride(null));
    tester.view.physicalSize = const Size(1600, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? opened;
    await tester.pumpWidget(MaterialApp(
        home: const Scaffold(
            body: SingleChildScrollView(child: DashboardStatistics())),
        onGenerateRoute: (settings) {
          opened = settings.name;
          return MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('Список')),
              settings: settings);
        }));
    await tester.pumpAndSettle();
    for (final target in [
      ('Пассажиры', '/users', 'kind', 'passenger'),
      ('Водители', '/drivers', null, null),
      ('Завершено из этих заказов', '/trip-register', 'status', 'COMPLETED')
    ]) {
      final tile = find.text(target.$1);
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      final uri = Uri.parse(opened!);
      expect(uri.path, target.$2);
      expect(uri.queryParameters['from'], '2026-11-04T19:00:00.000Z');
      expect(uri.queryParameters['to'], '2026-11-05T19:00:00.000Z');
      if (target.$3 != null) expect(uri.queryParameters[target.$3], target.$4);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
