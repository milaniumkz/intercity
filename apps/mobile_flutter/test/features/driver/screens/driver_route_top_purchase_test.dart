import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/driver/screens/driver_trip_create_page.dart';

void main() {
  testWidgets(
      'route top purchase uses the quoted currency and disables repeated payment',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _RouteApi();
    await tester
        .pumpWidget(MaterialApp(home: DriverTripCreatePage(apiClient: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мои маршруты (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('В топ · 142.86 руб.'));
    await tester.pumpAndSettle();
    expect(find.textContaining('12 часов'), findsOneWidget);
    await tester.tap(find.text('Оплатить 142.86 руб.'));
    await tester.pump();
    expect(api.payments, hasLength(1));
    expect(api.payments.single['expectedPrice'], 142.86);
    expect(api.payments.single['currency'], 'RUB');
    expect(api.payments.single['requestKey'], isNotEmpty);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Оплачиваем…'))
            .onPressed,
        isNull);
    api.done.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('В топе до'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _RouteApi extends ApiClient {
  final payments = <Map>[];
  final done = Completer<void>();
  String? topUntil;
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(
          requestOptions: RequestOptions(path: path),
          data: path == '/driver/intercity/routes'
              ? [
                  {
                    'id': 'route',
                    'fromCity': 'Омск',
                    'toCity': 'Тюмень',
                    'seatsAvailable': 4,
                    'currency': 'RUB',
                    'topPrice': 142.86,
                    'topDurationHours': 12,
                    'firstAccessSeconds': 30,
                    'topUntil': topUntil,
                  }
                ]
              : []);
  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data, Options? options}) async {
    if (path.endsWith('/promote')) {
      payments.add(Map.from(data));
      await done.future;
      topUntil =
          DateTime.now().add(const Duration(hours: 12)).toIso8601String();
    }
    return Response(requestOptions: RequestOptions(path: path), data: {});
  }
}
