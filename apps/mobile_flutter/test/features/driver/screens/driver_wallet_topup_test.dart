import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/driver/screens/driver_wallet_page.dart';

class _Api extends ApiClient {
  Map? created;
  bool pending = false;
  bool approved = true;
  bool demo = false;
  bool demoEnabled = false;
  double money = 200;
  int checks = 0;
  bool credited = false;
  String currentId = 'one';
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(requestOptions: RequestOptions(path: path), data: {
        'money': money,
        'bonus': 0,
        'withdrawable': money,
        'transactions': [],
        'topups': pending
            ? [
                {'id': currentId, 'provider': 'KASSA24', 'status': 'PENDING'}
              ]
            : [],
      });
  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data,
      Map<String, dynamic>? queryParameters,
      Options? options}) async {
    if (path == '/wallet/topup-request') {
      created = data as Map;
      if (pending) currentId = 'two';
      pending = true;
      return Response(requestOptions: RequestOptions(path: path), data: {
        'id': currentId,
        'provider': 'KASSA24',
        'paymentUrl': 'https://example.test/pay'
      });
    }
    checks++;
    if (approved && (!demo || demoEnabled) && !credited) {
      money += (created?['amount'] as num? ?? 1500).toDouble();
      credited = true;
      pending = false;
    }
    return Response(requestOptions: RequestOptions(path: path), data: {
      'id': currentId,
      'status': approved && (!demo || demoEnabled || credited)
          ? 'APPROVED'
          : 'PENDING',
      'provider': 'KASSA24',
      'currency': 'KZT',
      'amount': created?['amount'] ?? 1500,
      if (demo) 'paymentMode': 'TEST',
      'demoCreditsEnabled': demoEnabled
    });
  }
}

void main() {
  Future<void> open(WidgetTester tester, _Api api,
      {void Function(String)? opened}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final router = GoRouter(initialLocation: '/driver/wallet', routes: [
      GoRoute(
          path: '/driver/wallet',
          builder: (_, __) => DriverWalletPage(
              apiClient: api,
              paymentOpener: (_, url) async {
                opened?.call(url);
                return true;
              }))
    ]);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      tester.view.reset();
    });
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'entering an amount is required and closing payment checks actual credit',
      (tester) async {
    final api = _Api();
    String? opened;
    await open(tester, api, opened: (url) => opened = url);
    await tester.tap(find.text('Пополнить'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '');
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(api.created, isNull);
    await tester.enterText(find.byType(TextFormField), '1500,50');
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(api.created!['amount'], 1500.5);
    expect(api.created!['currency'], 'KZT');
    expect(opened, 'https://example.test/pay');
    expect(api.checks, 1);
    expect(api.money, 1700.5);
    expect(find.textContaining('зачислено на баланс'), findsOneWidget);
  });

  testWidgets('cancel before payment does not create a topup', (tester) async {
    final api = _Api();
    await open(tester, api);
    await tester.tap(find.text('Пополнить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(api.created, isNull);
    expect(api.checks, 0);
  });

  testWidgets(
      'provider demo success is explained without showing credited money',
      (tester) async {
    final api = _Api()
      ..pending = true
      ..demo = true;
    await open(tester, api);
    expect(api.money, 200);
    expect(find.textContaining('тестовой оплате'), findsOneWidget);
    expect(find.textContaining('зачислено на баланс.'), findsNothing);
    expect(find.text('Проверить платёж'), findsOneWidget);
  });

  testWidgets(
      'enabled demo payment credits the same wallet and is labelled as test',
      (tester) async {
    final api = _Api()
      ..pending = true
      ..demo = true
      ..demoEnabled = true;
    await open(tester, api);
    expect(api.money, 1700);
    expect(find.textContaining('Тестовое пополнение'), findsOneWidget);
    expect(find.textContaining('зачислено на баланс'), findsOneWidget);
  });

  testWidgets(
      'previously credited demo still shows credited after switching test mode off',
      (tester) async {
    final api = _Api()
      ..pending = true
      ..demo = true
      ..credited = true
      ..money = 1700;
    await open(tester, api);
    expect(api.money, 1700);
    expect(find.textContaining('зачислено на баланс'), findsOneWidget);
    expect(find.textContaining('деньги не зачислены'), findsNothing);
  });

  testWidgets(
      'new payment is checked even while an older pending payment has a poll timer',
      (tester) async {
    final api = _Api()
      ..pending = true
      ..approved = false;
    await open(tester, api);
    api.approved = true;
    await tester.tap(find.text('Пополнить'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '750');
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(api.currentId, 'two');
    expect(api.money, 950);
    expect(find.textContaining('зачислено на баланс'), findsOneWidget);
  });

  testWidgets(
      'returning to app refreshes an existing pending payment without another topup',
      (tester) async {
    final api = _Api()
      ..pending = true
      ..approved = false;
    await open(tester, api);
    expect(api.money, 200);
    api.approved = true;
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(api.money, 1700);
    expect(api.created, isNull);
    expect(find.textContaining('зачислено на баланс'), findsOneWidget);
  });
}
