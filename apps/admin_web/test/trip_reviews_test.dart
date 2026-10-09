import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_admin/core/api/admin_api_client.dart';
import 'package:intercity_admin/features/admin/screens/admin_trip_reviews_page.dart';

class ReviewApi implements AdminApi {
  final decisions = <Map<String, dynamic>>[];
  bool fail = true;
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? query}) async =>
      Response(
          requestOptions: RequestOptions(path: path),
          data: path == '/admin/trip-reviews'
              ? [
                  {
                    'id': 'CITY:ride',
                    'tripId': 'ride',
                    'kind': 'CITY',
                    'status': decisions.isEmpty ? 'REVIEW' : 'APPROVED',
                    'summary': {
                      'durationSec': 90,
                      'samples': 2,
                      'travelledMeters': 10
                    },
                    'reasons': ['Недостаточно движения']
                  }
                ]
              : []);
  @override
  Future<Response<dynamic>> patch(String path, {dynamic data}) async {
    expect(path, '/admin/trip-reviews/CITY%3Aride');
    if (fail) {
      fail = false;
      throw Exception('Ошибка сервера');
    }
    decisions.add(Map<String, dynamic>.from(data));
    return Response(requestOptions: RequestOptions(path: path), data: {});
  }

  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async =>
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
  testWidgets(
      'review decision validates explanation, keeps failed dialog open and refreshes saved status',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ReviewApi();
    AdminApiClient.debugOverride(api);
    addTearDown(() => AdminApiClient.debugOverride(null));
    await tester.pumpWidget(const MaterialApp(home: AdminTripReviewsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Подтвердить'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Минимум 5 символов'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField), 'Поездка подтверждена по записи и пояснениям');
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(api.decisions, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(api.decisions.single['decision'], 'APPROVE');
    expect(find.textContaining('Статус: APPROVED'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
