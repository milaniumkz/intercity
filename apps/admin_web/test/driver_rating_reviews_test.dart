import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_admin/core/api/admin_api_client.dart';
import 'package:intercity_admin/features/admin/screens/admin_rating_reviews_page.dart';

class _ReviewApi implements AdminApi {
  final decisions = <Map<String, dynamic>>[];
  bool resolved = false;
  bool failNext = false;
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? query}) async =>
      Response(
          requestOptions: RequestOptions(path: path),
          data: resolved && query?['status'] == 'NEW'
              ? []
              : [
                  {
                    'id': 'review',
                    'type': 'LOW_DRIVER_RATING',
                    'status': resolved ? 'RESOLVED' : 'NEW',
                    'orderId': 'ride',
                    'text': jsonEncode({
                      'rating': 1,
                      'reason': 'Водитель ехал опасно',
                      'automation': {'text': 'Проверьте факты поездки'}
                    }),
                    'driver': {
                      'user': {'name': 'Водитель'}
                    },
                    'user': {'name': 'Пассажир'},
                    'order': {
                      'driverRating': 1,
                      'driverRatingStatus': resolved
                          ? (decisions.last['ratingDecision'] == 'REJECT'
                              ? 'REJECTED'
                              : 'COUNTED')
                          : 'PENDING',
                      'price': 700,
                      'currency': 'KZT'
                    }
                  }
                ]);
  @override
  Future<Response<dynamic>> patch(String path, {dynamic data}) async {
    if (failNext) {
      failNext = false;
      throw DioException(
          requestOptions: RequestOptions(path: path),
          response: Response(
              requestOptions: RequestOptions(path: path),
              statusCode: 400,
              data: {'message': 'Проверьте пояснение решения'}));
    }
    decisions.add(Map<String, dynamic>.from(data));
    resolved = true;
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
      'invalid explanation and server errors keep the decision dialog open for retry',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _ReviewApi()..failNext = true;
    AdminApiClient.debugOverride(api);
    addTearDown(() => AdminApiClient.debugOverride(null));
    await tester.pumpWidget(const MaterialApp(home: AdminRatingReviewsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Не учитывать'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Укажите пояснение не менее 5 символов'), findsOneWidget);
    expect(api.decisions, isEmpty);
    await tester.enterText(
        find.byType(TextField), 'Причина не связана с водителем');
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Проверьте пояснение решения'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();
    expect(api.decisions.single['ratingDecision'], 'REJECT');
    expect(find.text('Решение сохранено'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Статус: REJECTED'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'administrator gets a pending notification and can change rating with explanation',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _ReviewApi();
    AdminApiClient.debugOverride(api);
    addTearDown(() => AdminApiClient.debugOverride(null));
    await tester.pumpWidget(const MaterialApp(home: AdminRatingReviewsPage()));
    await tester.pumpAndSettle();
    expect(find.text('Водитель ехал опасно'), findsOneWidget);
    expect(find.textContaining('Новые оценки на разбор'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Изменить'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4 звёзд').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField), 'Проверили факты, уточнили оценку');
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();
    expect(api.decisions.single, containsPair('ratingDecision', 'CHANGE'));
    expect(api.decisions.single, containsPair('rating', 4));
    expect(api.decisions.single,
        containsPair('resolutionNote', 'Проверили факты, уточнили оценку'));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
