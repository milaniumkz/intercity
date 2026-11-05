import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_admin/core/api/admin_api_client.dart';
import 'package:intercity_admin/features/admin/widgets/finance_dashboard.dart';

class _FinanceApi implements AdminApi {
  final calls = <Map<String, dynamic>>[];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? query}) async {
    calls.add({'path': path, ...?query});
    return Response(
        requestOptions: RequestOptions(path: path),
        data: path.endsWith('finance-dashboard')
            ? {
                'range': {
                  'from': '2026-11-04T19:00:00Z',
                  'to': '2026-11-05T19:00:00Z'
                },
                'groups': [
                  {
                    'currency': 'KZT',
                    'category': 'COMMISSION',
                    'amount': 150,
                    'count': 2,
                    'credit': 0,
                    'debit': 150
                  }
                ],
                'trips': [
                  {
                    'currency': 'KZT',
                    'created': 3,
                    'completed': 2,
                    'turnover': 4000
                  }
                ],
                'days': [],
                'payouts': []
              }
            : {'items': [], 'total': 0});
  }
}

void main() {
  testWidgets(
      'financial cards drill down with the same dates, category and currency',
      (tester) async {
    final api = _FinanceApi();
    AdminApiClient.debugOverride(api);
    addTearDown(() => AdminApiClient.debugOverride(null));
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? route;
    await tester.pumpWidget(MaterialApp(
        home: const Scaffold(
            body: SingleChildScrollView(child: FinanceDashboard())),
        onGenerateRoute: (settings) {
          route = settings.name;
          return MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('Поездки')));
        }));
    await tester.pumpAndSettle();
    final commission = find.text('Списанные комиссии · операций: 2');
    await tester.ensureVisible(commission);
    await tester.tap(commission);
    await tester.pumpAndSettle();
    var query = api.calls.last;
    expect(query['category'], 'COMMISSION');
    expect(query['currency'], 'KZT');
    expect(query['from'], '2026-11-04T19:00:00Z');
    expect(query['to'], '2026-11-05T19:00:00Z');
    await tester.ensureVisible(find.text('Рубли ₽'));
    await tester.tap(find.text('Рубли ₽'));
    await tester.pumpAndSettle();
    expect(api.calls.last['currency'], 'RUB');
    await tester.ensureVisible(find.text('Неделя'));
    await tester.tap(find.text('Неделя'));
    await tester.pumpAndSettle();
    expect(
        api.calls
            .where((c) => c['path'] == '/admin/finance-dashboard')
            .last['period'],
        'week');
    await tester.ensureVisible(find.text('Оборот завершённых поездок'));
    await tester.tap(find.text('Оборот завершённых поездок'));
    await tester.pumpAndSettle();
    final parsed = Uri.parse(route!);
    expect(parsed.path, '/trip-register');
    expect(parsed.queryParameters['currency'], 'RUB');
    expect(parsed.queryParameters['completedInPeriod'], 'true');
    expect(parsed.queryParameters['from'], '2026-11-04T19:00:00Z');
    expect(tester.takeException(), isNull);
  });
}
