import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/referral/screens/referral_account_page.dart';
import 'package:intercity_mobile/features/referral/widgets/tax_status_panel.dart';

class TaxApi extends ApiClient {
  Map<String, dynamic>? payload;
  String? posted;
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(
          requestOptions: RequestOptions(path: path),
          data: path == '/tax/me'
              ? {
                  'enabled': true,
                  'profile': {'kind': 'SELF_EMPLOYED', 'status': 'VERIFIED'},
                  'referralBalance': '6240',
                  'minPayout': '5000',
                  'income': []
                }
              : {
                  'refCode': 'TEST',
                  'refLink': 'https://example.test/#/ref/TEST',
                  'invitedCount': 0
                });
  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data, Options? options}) async {
    posted = path;
    payload = Map<String, dynamic>.from(data);
    if (path == '/wallet/payout-request') {
      throw DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.badResponse,
          response: Response(
              requestOptions: RequestOptions(path: path),
              statusCode: 400,
              data: {'message': 'Недостаточно средств'}));
    }
    return Response(
        requestOptions: RequestOptions(path: path),
        data: {'status': 'PENDING'});
  }
}

void main() {
  testWidgets(
      'withdrawal uses only referral source and retains an actionable server error',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = TaxApi();
    await tester
        .pumpWidget(MaterialApp(home: ReferralAccountPage(apiClient: api)));
    await tester.pumpAndSettle();
    expect(find.text('Обычные бонусы и бонусы акций не доступны для вывода.'),
        findsOneWidget);
    await tester.tap(find.text('Вывести на карту'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Номер карты'), '4000000000000002');
    await tester.tap(find.text('Создать заявку'));
    await tester.pumpAndSettle();
    expect(api.posted, '/wallet/payout-request');
    expect(api.payload?['source'], 'REFERRAL');
    expect(api.payload?['currency'], 'KZT');
    expect(api.payload?['amount'], 6240);
    expect(find.textContaining('Недостаточно'), findsOneWidget);
    expect(find.text('Создать заявку'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'tax declaration requires explicit status and consent; no client exemptions can be submitted',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = TaxApi();
    var saved = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(children: [
      TaxStatusPanel(apiClient: api, driver: true, onSaved: () => saved++)
    ]))));
    await tester.ensureVisible(find.text('Сохранить статус'));
    await tester.tap(find.text('Сохранить статус'));
    await tester.pumpAndSettle();
    expect(api.posted, isNull);
    await tester.ensureVisible(find.text('ИП'));
    await tester.tap(find.text('ИП'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '900101300010');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Сохранить статус'));
    await tester.tap(find.text('Сохранить статус'));
    await tester.pumpAndSettle();
    expect(api.payload?['kind'], 'IE');
    expect(api.payload?['countryCode'], 'KZ');
    expect(api.payload?['consent'], true);
    expect(api.payload?['activities'], ['49320', '82990']);
    expect(api.payload?.containsKey('exemptions'), false);
    expect(saved, 1);
    expect(tester.takeException(), isNull);
  });
}
