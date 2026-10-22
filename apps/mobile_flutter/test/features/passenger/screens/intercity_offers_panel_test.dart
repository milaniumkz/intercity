import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/passenger/screens/intercity_request_page.dart';

void main() {
  for (final accept in [false, true]) {
    testWidgets(
        'top intercity offer shows driver and sends ${accept ? 'accept' : 'reject'} immediately',
        (tester) async {
      tester.view.physicalSize = const Size(392, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = OfferApi();
      await tester.pumpWidget(MaterialApp(
          home: IntercityRequestPage(
              requestId: 'trip', apiClient: api, enableLiveMap: false)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final panel =
          find.byKey(const ValueKey('passenger-top-intercity-offers'));
      expect(panel, findsOneWidget);
      expect(tester.getTopLeft(panel).dy, lessThan(150));
      expect(find.descendant(of: panel, matching: find.text('Олег')),
          findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('Toyota Camry')),
          findsOneWidget);
      await tester.tap(find.descendant(
          of: panel, matching: find.text(accept ? 'Принять' : 'Отклонить')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(api.actions,
          ['/intercity/offers/offer/${accept ? 'accept' : 'reject'}']);
      expect(find.byKey(const ValueKey('passenger-top-intercity-offers')),
          findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('expired intercity offers are not actionable', (tester) async {
    final api = OfferApi(expired: true);
    await tester.pumpWidget(MaterialApp(
        home: IntercityRequestPage(
            requestId: 'trip', apiClient: api, enableLiveMap: false)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('passenger-top-intercity-offers')),
        findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

class OfferApi extends ApiClient {
  OfferApi({this.expired = false});
  final bool expired;
  final actions = <String>[];
  String status = 'OPEN';
  bool pending = true;
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(requestOptions: RequestOptions(path: path), data: {
        'id': 'trip',
        'requestType': 'INTERCITY',
        'status': status,
        'fromCity': 'Усть-Каменогорск',
        'toCity': 'Семей',
        'fromManualAddress': 'Назарбаева 8/1',
        'toManualAddress': 'Абая 10',
        'date': '2026-10-16T05:00:00Z',
        'price': 7000,
        'currency': 'KZT',
        'seats': 2,
        'paymentMethod': 'CASH',
        'offers': pending
            ? [
                {
                  'id': 'offer',
                  'status': 'PENDING',
                  'price': 7500,
                  'seats': 2,
                  'updatedAt': DateTime.now()
                      .subtract(Duration(seconds: expired ? 31 : 2))
                      .toIso8601String(),
                  'driver': {
                    'name': 'Олег',
                    'driverProfile': {
                      'carModel': 'Toyota Camry',
                      'carNumber': '123 ABC',
                      'rating': {'ratingAvg': 4.9, 'ratingCount': 15}
                    }
                  }
                }
              ]
            : []
      });
  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data, Options? options}) async {
    actions.add(path);
    pending = false;
    if (path.endsWith('/accept')) status = 'DRIVER_ASSIGNED';
    return Response(requestOptions: RequestOptions(path: path), data: {});
  }
}
