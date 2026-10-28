import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/driver/screens/driver_trip_create_page.dart';

void main() {
  testWidgets(
      'offer explains missing price, bounds seats, shows server errors and prevents duplicate sends',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = OfferApi();
    await tester
        .pumpWidget(MaterialApp(home: DriverTripCreatePage(apiClient: api)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Предложить цену').first, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Предложить цену').first);
    await tester.pumpAndSettle();
    Future<void> send() async {
      await tester.ensureVisible(find.text('Отправить'));
      await tester.tap(find.text('Отправить'));
      await tester.pumpAndSettle();
    }

    await send();
    expect(find.text('Введите вашу цену за поездку'), findsOneWidget);
    expect(api.calls, isEmpty);
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    final price = find.byType(TextField).first;
    await tester.ensureVisible(price);
    await tester.enterText(price, '4000');
    await send();
    expect(
        find.textContaining('Недостаточно средств на балансе'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    api.reject = false;
    await tester.ensureVisible(find.text('Отправить'));
    await tester.tap(find.text('Отправить'));
    await tester.pump();
    expect(api.calls, hasLength(2));
    expect(api.calls.last['price'], 4000);
    expect(api.calls.last['seats'], 1);
    expect(
        tester
            .widget<DropdownButtonFormField<int>>(
                find.byType(DropdownButtonFormField<int>))
            .onChanged,
        isNull);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    api.done.complete();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Отклик на заявку отправлен'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class OfferApi extends ApiClient {
  bool reject = true;
  final calls = <Map>[];
  final done = Completer<void>();
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(
          requestOptions: RequestOptions(path: path),
          data: path.endsWith('/matching')
              ? [
                  {
                    'id': 'request',
                    'requestType': 'INTERCITY',
                    'fromCity': 'Усть-Каменогорск',
                    'toCity': 'Риддер',
                    'price': 3000,
                    'seats': 1,
                    'currency': 'KZT',
                    'paymentMethod': 'CASH',
                    'date': DateTime.now()
                        .add(const Duration(hours: 2))
                        .toIso8601String()
                  }
                ]
              : path.endsWith('/routes')
                  ? [
                      {
                        'id': 'route',
                        'fromCity': 'Усть-Каменогорск',
                        'toCity': 'Риддер',
                        'seatsAvailable': 4
                      }
                    ]
                  : []);
  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data, Options? options}) async {
    calls.add(Map.from(data));
    if (reject) {
      throw DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.badResponse,
          response: Response(
              requestOptions: RequestOptions(path: path),
              statusCode: 400,
              data: {
                'message': 'Недостаточно средств на балансе. Пополните баланс.'
              }));
    }
    await done.future;
    return Response(requestOptions: RequestOptions(path: path), data: {});
  }
}
