import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_admin/core/api/admin_api_client.dart';
import 'package:intercity_admin/features/admin/screens/admin_identity_reviews_page.dart';

class IdentityApi implements AdminApi {
  IdentityApi(this.vehicle);
  final bool vehicle;
  bool fail = true;
  final decisions = <Map<String, dynamic>>[];
  static const image = <int>[
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    4,
    0,
    0,
    0,
    4,
    8,
    2,
    0,
    0,
    0,
    38,
    147,
    9,
    41,
    0,
    0,
    0,
    20,
    73,
    68,
    65,
    84,
    120,
    156,
    99,
    252,
    255,
    255,
    63,
    3,
    12,
    48,
    49,
    32,
    1,
    220,
    28,
    0,
    150,
    110,
    3,
    5,
    242,
    37,
    190,
    249,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    174,
    66,
    96,
    130
  ];
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? query}) async {
    dynamic data = [];
    if (path == '/admin/identity/reviews') {
      data = decisions.isEmpty
          ? [
              {
                'id': 'review',
                'purpose': vehicle ? 'VEHICLE' : 'ENROLL',
                'reason': 'Нужна проверка',
                'actions': ['TURN_LEFT'],
                'user': {'name': 'Локальный пример', 'phone': '+70000000000'}
              }
            ]
          : [];
    }
    if (path.endsWith('/candidate') || path.endsWith('/reference')) {
      data = image;
    }
    if (path.endsWith('/video') || path.endsWith('/back')) {
      throw DioException(requestOptions: RequestOptions(path: path));
    }
    return Response(requestOptions: RequestOptions(path: path), data: data);
  }

  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    if (fail) {
      fail = false;
      throw DioException(requestOptions: RequestOptions(path: path));
    }
    decisions.add(Map<String, dynamic>.from(data as Map));
    return Response(
        requestOptions: RequestOptions(path: path), data: {'success': true});
  }

  @override
  Future<Response<dynamic>> patch(String path, {dynamic data}) async =>
      throw UnimplementedError();
  @override
  Future<Response<dynamic>> delete(String path) async =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> login(String phone, String password) async => {};
  @override
  Future<void> logout() async {}
}

void main() {
  Future<IdentityApi> open(WidgetTester tester, bool vehicle) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = IdentityApi(vehicle);
    AdminApiClient.debugOverride(api);
    addTearDown(() => AdminApiClient.debugOverride(null));
    await tester
        .pumpWidget(const MaterialApp(home: AdminIdentityReviewsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Проверить'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(milliseconds: 400));
    return api;
  }

  testWidgets(
      'missing review video cannot be approved and rejection requires explanation',
      (tester) async {
    final api = await open(tester, false);
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Подтвердить'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Отказать'));
    await tester.pump();
    expect(
        find.text('Укажите основание решения, от 10 символов'), findsOneWidget);
    expect(api.decisions, isEmpty);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
  });
  testWidgets(
      'vehicle review submits all four document fields and retains failed decision for retry',
      (tester) async {
    final api = await open(tester, true);
    final values = ['BMW', 'X5', '2020', 'A123BC77'];
    for (var i = 0; i < 4; i++) {
      final field = find.byType(TextField).at(i);
      await tester.ensureVisible(field);
      await tester.enterText(field, values[i]);
    }
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    final reason = find.byType(TextField).last;
    await tester.ensureVisible(reason);
    await tester.enterText(reason, 'Сведения прочитаны из техпаспорта');
    await tester.tap(find.text('Подтвердить'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(api.decisions, isEmpty);
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(api.decisions.single['vehicle'], {
      'brand': 'BMW',
      'model': 'X5',
      'year': 2020,
      'plateNumber': 'A123BC77'
    });
  });
}
