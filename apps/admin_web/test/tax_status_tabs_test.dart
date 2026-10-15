import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_admin/core/api/admin_api_client.dart';
import 'package:intercity_admin/features/admin/screens/admin_tax_registry_page.dart';

void main() {
  testWidgets('status tabs and form-free approval update the displayed profile',
      (tester) async {
    tester.view.physicalSize = const Size(2200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ReviewApi();
    AdminApiClient.debugOverride(api);
    addTearDown(() => AdminApiClient.debugOverride(null));
    await tester.pumpWidget(const MaterialApp(home: AdminTaxRegistryPage()));
    await tester.pumpAndSettle();
    expect(find.text('Дмитрий · демонстрация'), findsOneWidget);
    expect(find.text('Активный профиль · демонстрация'), findsNothing);
    await tester
        .ensureVisible(find.widgetWithText(FilledButton, 'Подтвердить'));
    await tester.tap(find.widgetWithText(FilledButton, 'Подтвердить'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Дмитрий · демонстрация'), findsNothing);
    expect(api.lastDecision, {'status': 'VERIFIED', 'quickApproval': true});
    await tester.tap(find.text('Активные (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Дмитрий · демонстрация'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Отклонить').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отклонённые (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Дмитрий · демонстрация'), findsOneWidget);
  });
}

class ReviewApi implements AdminApi {
  dynamic lastDecision;
  final rows = [
    {
      'ownerKey': 'demo-1',
      'profile': {
        'status': 'PENDING',
        'user': {'name': 'Дмитрий · демонстрация', 'phone': '+7 *** *** 7368'}
      },
      'trips': 0
    },
    {
      'ownerKey': 'demo-2',
      'profile': {
        'status': 'VERIFIED',
        'user': {
          'name': 'Активный профиль · демонстрация',
          'phone': '+7 *** *** 2153'
        }
      },
      'trips': 12
    },
    {
      'ownerKey': 'demo-3',
      'profile': {
        'status': 'REJECTED',
        'user': {
          'name': 'Отклонённый профиль · демонстрация',
          'phone': '+7 *** *** 6779'
        }
      },
      'trips': 0
    },
  ];
  @override
  Future<Map<String, dynamic>> login(String p, String s) async =>
      {'role': 'ADMIN'};
  @override
  Future<void> logout() async {}
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? query}) async =>
      Response(
          requestOptions: RequestOptions(path: path),
          data: path == '/admin/tax/registry'
              ? {'rows': rows, 'entries': [], 'payments': []}
              : {});
  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    if (path.endsWith('/verify')) {
      lastDecision = data;
      final row = rows.firstWhere((r) => path.contains('/${r['ownerKey']}/'));
      (row['profile'] as Map)['status'] = data['status'];
    }
    return Response(requestOptions: RequestOptions(path: path), data: {});
  }

  @override
  Future<Response<dynamic>> patch(String path, {dynamic data}) =>
      post(path, data: data);
  @override
  Future<Response<dynamic>> delete(String path) => post(path);
}
