import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/features/passenger/widgets/saved_payment_cards.dart';

class CardsApi extends ApiClient {
  bool configured = true;
  String selected = 'first';
  bool removed = false;
  final requests = <String>[];
  dynamic get data => {
        'configured': configured,
        'message': configured ? null : 'Оплата картой пока недоступна',
        'cards': removed
            ? []
            : [
                {
                  'id': 'first',
                  'last4': '0123',
                  'isDefault': selected == 'first'
                },
                {
                  'id': 'second',
                  'last4': '0456',
                  'isDefault': selected == 'second'
                }
              ]
      };
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(requestOptions: RequestOptions(path: path), data: data);
  @override
  Future<Response<dynamic>> patch(String path,
      {dynamic data, Options? options}) async {
    requests.add(path);
    selected = 'second';
    return Response(requestOptions: RequestOptions(path: path), data: {});
  }

  @override
  Future<Response<dynamic>> delete(String path, {Options? options}) async {
    requests.add(path);
    removed = true;
    return Response(requestOptions: RequestOptions(path: path), data: {});
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
      'saved card selection and deletion use local card IDs and show only last four digits',
      (tester) async {
    final api = CardsApi();
    bool ready = false;
    String? last4;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SavedPaymentCards(
                apiClient: api,
                onReadyChanged: (r, l) {
                  ready = r;
                  last4 = l;
                }))));
    await tester.pumpAndSettle();
    expect(find.text('•••• 0123'), findsOneWidget);
    expect(ready, isTrue);
    expect(last4, '0123');
    await tester.tap(find.text('•••• 0456'));
    await tester.pumpAndSettle();
    expect(api.requests, contains('/payments/cards/second/default'));
    expect(last4, '0456');
    await tester.tap(find.byTooltip('Отвязать карту').last);
    await tester.pumpAndSettle();
    expect(api.requests, contains('/payments/cards/second'));
    expect(ready, isFalse);
  });
  testWidgets('unconfigured provider disables card binding', (tester) async {
    final api = CardsApi()..configured = false;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SavedPaymentCards(apiClient: api))));
    await tester.pumpAndSettle();
    expect(find.text('Добавить карту'), findsNothing);
    expect(find.text('Оплата картой пока недоступна'), findsOneWidget);
  });
  test(
      'cash fallback notification is deduplicated separately for both participants across reloads',
      () async {
    expect(
        await AppPreferences.claimPaymentFallbackNotice('DRIVER:ride'), isTrue);
    expect(await AppPreferences.claimPaymentFallbackNotice('DRIVER:ride'),
        isFalse);
    expect(await AppPreferences.claimPaymentFallbackNotice('PASSENGER:ride'),
        isTrue);
    expect(await AppPreferences.claimPaymentFallbackNotice('PASSENGER:ride'),
        isFalse);
  });
}
