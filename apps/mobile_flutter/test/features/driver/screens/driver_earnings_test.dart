import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/driver/screens/driver_earnings_page.dart';

class EarningsApi extends ApiClient {
  bool fail = false, empty = false;
  Completer<Response<dynamic>>? delayed;
  final queries = <Map<String, dynamic>>[];

  Map<String, dynamic> data(String currency) => {
        'currency': currency,
        'profile': {'kind': currency == 'KZT' ? 'SELF_EMPLOYED' : 'INDIVIDUAL'},
        'trips': {
          'total': empty ? 0 : 4,
          'city': empty ? 0 : 3,
          'intercity': empty ? 0 : 1,
          'legacyDates': 0
        },
        'gross': empty ? '0' : '20000',
        'cash': empty ? '0' : '10000',
        'card': empty ? '0' : '5000',
        'pendingCard': empty ? '0' : '5000',
        'commission': empty ? '0' : '2000',
        'net': empty ? '0' : '12400',
        'afterCommission': empty ? '0' : '13000',
        'tax': {
          'showSocialPayments': currency == 'KZT',
          'enabled': true,
          'opv': '200',
          'opvr': '200',
          'so': '200',
          'osms': '200',
          'accrued': '800',
          'withheld': '500',
          'debt': '300',
          'remitted': '100',
          'payable': '700',
          'rideAccrued': '600',
          'referralAccrued': '200',
          'reviewCount': 0,
          'unaccountedTrips': 0
        },
      };

  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    queries.add(Map.from(queryParameters!));
    if (delayed != null && queries.length == 1) return delayed!.future;
    if (fail) {
      throw DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.connectionError);
    }
    return Response(
        requestOptions: RequestOptions(path: path),
        data: data(queryParameters['currency'] as String));
  }
}

void main() {
  testWidgets(
      'earnings shows actual trip result and four social components on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = EarningsApi();
    await tester
        .pumpWidget(MaterialApp(home: DriverEarningsPage(apiClient: api)));
    await tester.pumpAndSettle();
    expect(find.text('12 400,00 ₸'), findsOneWidget);
    expect(find.text('После комиссии и соцплатежей'), findsOneWidget);
    expect(api.queries.single['currency'], 'KZT');
    await tester.scrollUntilVisible(find.text('Всего начислено'), 300);
    expect(find.text('ОПВ · пенсионные взносы'), findsOneWidget);
    expect(find.text('ОПВР · взносы работодателя'), findsOneWidget);
    expect(find.text('СО · социальные отчисления'), findsOneWidget);
    expect(find.text('ОСМС · медстрахование'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Осталось перечислить'), 300);
    expect(find.text('Удержано платформой'), findsOneWidget);
    expect(find.text('Перечислено по платёжным документам'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'currency and month selectors refetch separate totals; RUB has no KZ social section',
      (tester) async {
    final api = EarningsApi();
    await tester
        .pumpWidget(MaterialApp(home: DriverEarningsPage(apiClient: api)));
    await tester.pumpAndSettle();
    final firstPeriod = api.queries.single['period'];
    await tester.tap(find.text('Рубли · ₽'));
    await tester.pumpAndSettle();
    expect(api.queries.last['currency'], 'RUB');
    expect(find.text('13 000,00 ₽'), findsOneWidget);
    expect(find.text('Налоги и социальные платежи'), findsNothing);
    await tester.tap(find.byTooltip('Предыдущий месяц'));
    await tester.pumpAndSettle();
    expect(api.queries.last['period'], isNot(firstPeriod));
    expect(api.queries.last['currency'], 'RUB');
    expect(tester.takeException(), isNull);
  });

  testWidgets('network failure is not a zero income report and can be retried',
      (tester) async {
    final api = EarningsApi()..fail = true;
    await tester
        .pumpWidget(MaterialApp(home: DriverEarningsPage(apiClient: api)));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить заработок'), findsOneWidget);
    expect(find.text('0,00 ₸'), findsNothing);
    api.fail = false;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('12 400,00 ₸'), findsOneWidget);
  });

  testWidgets(
      'late response for previous currency cannot overwrite current report',
      (tester) async {
    final api = EarningsApi()..delayed = Completer<Response<dynamic>>();
    await tester
        .pumpWidget(MaterialApp(home: DriverEarningsPage(apiClient: api)));
    await tester.pump();
    await tester.tap(find.text('Рубли · ₽'));
    await tester.pumpAndSettle();
    api.delayed!.complete(Response(
        requestOptions: RequestOptions(path: '/driver/earnings'),
        data: api.data('KZT')));
    await tester.pumpAndSettle();
    expect(find.text('13 000,00 ₽'), findsOneWidget);
    expect(find.text('После комиссии и соцплатежей'), findsNothing);
  });

  testWidgets('empty month has an explicit empty state', (tester) async {
    final api = EarningsApi()..empty = true;
    await tester
        .pumpWidget(MaterialApp(home: DriverEarningsPage(apiClient: api)));
    await tester.pumpAndSettle();
    expect(find.text('За этот месяц завершённых поездок пока нет.'),
        findsOneWidget);
  });
}
