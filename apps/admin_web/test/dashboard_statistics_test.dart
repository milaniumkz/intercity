import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_admin/core/api/admin_api_client.dart';
import 'package:intercity_admin/features/admin/widgets/dashboard_statistics.dart';

Map<String, dynamic> fixture(int count) => {
      'users': {
        'newTotal': count,
        'newDrivers': 2,
        'newPassengers': 3,
        'total': 134,
        'drivers': 40,
        'passengers': 94
      },
      'drivers': {'online': 12, 'newProfiles': 2},
      'orders': {'total': 73, 'completed': 60, 'cancelled': 13},
      'byMode': [
        {
          'mode': 'CARGO',
          'total': 73,
          'completed': 60,
          'cancelled': 13,
          'active': 0,
          'expired': 0
        }
      ],
      'daily': [
        {'date': '2026-11-04', 'users': count, 'orders': 73}
      ],
      'finance': [
        {'currency': 'KZT', 'turnover': 12345}
      ],
      'commissions': [
        {'currency': 'RUB', 'amount': 500}
      ],
      'recentOrders': [],
      'recentUsers': []
    };

class Api implements AdminApi {
  final queries = <Map<String, dynamic>>[];
  Completer<Response<dynamic>>? first;
  bool fail = false;
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? query}) async {
    expect(path, '/admin/dashboard/statistics');
    queries.add(Map.from(query!));
    if (first != null && queries.length == 1) {
      return first!.future;
    }
    if (fail) {
      throw Exception('unavailable');
    }
    return Response(
        requestOptions: RequestOptions(path: path),
        data: fixture(query['period'] == 'week' ? 927 : 518));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Api api;
  setUp(() {
    api = Api();
    AdminApiClient.debugOverride(api);
  });
  tearDown(() => AdminApiClient.debugOverride(null));
  testWidgets(
      'period filters replace statistics and preserve currency separation',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: DashboardStatistics()))));
    await tester.pumpAndSettle();
    expect(api.queries.single['period'], '24h');
    expect(find.text('518'), findsOneWidget);
    await tester.tap(find.text('7 дней'));
    await tester.pumpAndSettle();
    expect(api.queries.last['period'], 'week');
    expect(find.text('927'), findsOneWidget);
    expect(find.text('518'), findsNothing);
    expect(find.text('KZT'), findsOneWidget);
    expect(find.text('RUB'), findsOneWidget);
    expect(find.text('Грузовые'), findsOneWidget);
  });
  testWidgets('late response cannot overwrite a newly selected period',
      (tester) async {
    api.first = Completer<Response<dynamic>>();
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: DashboardStatistics()))));
    await tester.pump();
    await tester.tap(find.text('7 дней'));
    await tester.pumpAndSettle();
    expect(find.text('927'), findsOneWidget);
    api.first!.complete(Response(
        requestOptions: RequestOptions(path: 'stats'), data: fixture(111)));
    await tester.pumpAndSettle();
    expect(find.text('927'), findsOneWidget);
    expect(find.text('111'), findsNothing);
  });
  testWidgets('failure is visible and can be retried', (tester) async {
    api.fail = true;
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: DashboardStatistics()))));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Не удалось загрузить статистику'), findsOneWidget);
    expect(find.text('Всего регистраций'), findsNothing);
    api.fail = false;
    await tester.tap(find.text('Повторить загрузку'));
    await tester.pumpAndSettle();
    expect(find.text('518'), findsOneWidget);
  });
}
