import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/core/services/vtb_sandbox_checkout.dart';
import 'package:intercity_mobile/features/driver/screens/driver_wallet_page.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';
import 'package:intercity_mobile/features/home/widgets/city_order_composer.dart';
import '../../support/memory_tile_provider.dart';

class _VtbApi extends ApiClient {
  String country = 'RU';
  String purpose = 'TOPUP';
  double walletRub = 0;
  bool bankCredited = false;
  bool latestPending = false;
  final payments = <Map<String, dynamic>>[];
  final realOrders = <String>[];
  Map<String, dynamic> result({String status = 'PENDING'}) => {
    'id': '11111111-2222-3333-4444-555555555555',
    'amount': 100, 'currency': 'RUB', 'bankAmount': 700,
    'bankCurrency': 'KZT', 'conversionRate': 7,
    'paymentMode': 'TEST', 'purpose': purpose, 'creditsWallet': purpose == 'TOPUP', 'status': status,
    'creditedAt': purpose == 'TOPUP' && bankCredited ? '2026-11-20T12:00:00Z' : null,
    'paymentUrl': 'https://vtbkz.rbsuat.com/payment/merchants/ecom/payment.html',
  };
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    dynamic data = <String, dynamic>{};
    if (path.startsWith('/wallet?')) {
      data = {'countryCode': country, 'money': walletRub, 'bonus': 0, 'transactions': [], 'topups': [], 'payouts': []};
    } else if (path == '/wallet/vtb/sandbox') {
      data = {'eligible': country == 'RU', 'available': country == 'RU', 'latestPayment': latestPending ? result(status: bankCredited ? 'SUCCEEDED' : 'PENDING') : null};
    } else if (path == '/geo/cities') {
      data = [];
    } else if (path == '/app/runtime-settings') {
      data = {'passengerMapHomeEnabled': false};
    } else if (path == '/payments/cards') {
      data = {'configured': false, 'cards': []};
    } else if (path == '/route') {
      data = {'distance': 2.1, 'duration': 4};
    }
    return Response(requestOptions: RequestOptions(path: path), data: data);
  }
  @override
  Future<Response<dynamic>> post(String path, {dynamic data,
      Map<String, dynamic>? queryParameters, Options? options}) async {
    if (path == '/wallet/vtb/sandbox/payments') {
      purpose = (data as Map)['purpose'].toString();
      payments.add(Map<String, dynamic>.from(data));
      return Response(requestOptions: RequestOptions(path: path), data: result());
    }
    if (path.endsWith('/check')) {
      if (purpose == 'TOPUP' && !bankCredited) {
        walletRub += 100;
        bankCredited = true;
      }
      return Response(requestOptions: RequestOptions(path: path), data: result(status: 'SUCCEEDED'));
    }
    if (path == '/orders/preview') {
      return Response(requestOptions: RequestOptions(path: path),
          data: {'price': 100, 'currency': 'RUB', 'distance': 2.1, 'duration': 4});
    }
    realOrders.add(path);
    return Response(requestOptions: RequestOptions(path: path), data: {'id': 'must-not-be-created'});
  }
}

void main() {
  setUp(() { FlutterSecureStorage.setMockInitialValues({}); });
  Future<void> prepare(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  testWidgets('Russian top-up goes directly to VTB with RUB display and locked KZT charge', (tester) async {
    await prepare(tester);
    final api = _VtbApi();
    var opened = 0;
    final router = GoRouter(initialLocation: '/driver/wallet', routes: [
      GoRoute(path: '/driver/wallet', builder: (_, __) => DriverWalletPage(
        apiClient: api, paymentOpener: (_, url) async { opened++; return true; })),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Пополнить').first);
    await tester.tap(find.text('Пополнить').first);
    await tester.pumpAndSettle();
    expect(find.text('Способ пополнения'), findsNothing);
    expect(find.text('Тестовая оплата ВТБ · RUB'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '100');
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('700.00 ₸'), findsOneWidget);
    expect(find.textContaining('1 ₽ = 7 ₸'), findsOneWidget);
    await tester.tap(find.text('Перейти в ВТБ'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(api.payments.single['currency'], 'RUB');
    expect(api.payments.single['purpose'], 'TOPUP');
    expect(find.textContaining('100.00 ₽ зачислено на баланс'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^100(?:[.,]00)?\s*₽$')), findsOneWidget);
    expect(api.realOrders, isEmpty);
  });

  testWidgets('bank return refreshes the visible rouble balance after credit', (tester) async {
    await prepare(tester);
    final api = _VtbApi()..latestPending = true;
    final router = GoRouter(
      initialLocation: '/driver/wallet?vtbSandboxPaymentId=11111111-2222-3333-4444-555555555555',
      routes: [
        GoRoute(path: '/driver/wallet', builder: (_, __) => DriverWalletPage(apiClient: api)),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.textContaining('100.00 ₽ зачислено на баланс'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^100(?:[.,]00)?\s*₽$')), findsOneWidget);
    expect(api.walletRub, 100);
  });

  testWidgets('Kazakhstan keeps Kaspi and Kassa24 and does not open VTB', (tester) async {
    await prepare(tester);
    final api = _VtbApi()..country = 'KZ';
    final router = GoRouter(initialLocation: '/driver/wallet', routes: [
      GoRoute(path: '/driver/wallet', builder: (_, __) => DriverWalletPage(apiClient: api)),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Пополнить').first);
    await tester.tap(find.text('Пополнить').first);
    await tester.pumpAndSettle();
    expect(find.text('Способ пополнения'), findsOneWidget);
    expect(find.text('Kassa24'), findsOneWidget);
    expect(find.text('Kaspi'), findsOneWidget);
    expect(api.payments, isEmpty);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
  });

  testWidgets('Russian trip card opens VTB test checkout and cannot publish a real paid order', (tester) async {
    await prepare(tester);
    final api = _VtbApi();
    var opened = 0;
    await AppPreferences.setOrderCity({'id': 'ru-city', 'name': 'Екатеринбург',
      'lat': 56.83, 'lng': 60.6, 'countryCode': 'RU', 'currency': 'RUB'});
    await AppPreferences.setOrderDraft(jsonEncode({
      'fromLat': 56.83, 'fromLng': 60.6, 'fromAddress': 'Ленина 1',
      'toLat': 56.84, 'toLng': 60.61, 'toAddress': 'Малышева 2',
      'boardPrice': 100, 'rideCurrency': 'RUB', 'cityModeIndex': 0,
      'modeIndex': 0, 'paymentMethod': 'CASH',
    }));
    final router = GoRouter(initialLocation: '/order/fixed', routes: [
      GoRoute(path: '/order/:stage', builder: (_, state) => OrderScreen(
        routeStage: state.pathParameters['stage'], apiClient: api,
        enableLiveMap: false, autoLocateOnStart: false,
        mapTileProvider: MemoryTileProvider(),
        vtbPaymentOpener: (_, url) async { opened++; return true; })),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Карта'));
    await tester.tap(find.text('Карта'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    final composer = tester.widget<CityOrderComposer>(find.byType(CityOrderComposer));
    expect(composer.paymentMethod, 'CASH');
    expect(composer.canOrder, isTrue);
    expect(opened, 0);
    await tester.tap(find.text('Карта'));
    await tester.pumpAndSettle();
    expect(find.textContaining('700.00 ₸'), findsOneWidget);
    await tester.tap(find.text('Перейти в ВТБ'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(api.payments.last['purpose'], 'TRIP_TEST');
    expect(api.payments.last['amount'], 100);
    expect(api.realOrders, isEmpty);
    expect(find.textContaining('реальная поездка не оплачена'), findsWidgets);
  });

  testWidgets('cancelling the currency quote does not open the bank', (tester) async {
    await prepare(tester);
    final api = _VtbApi();
    var opened = false;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () async {
        await VtbSandboxCheckout.pay(context, api, amount: 100,
          purpose: 'TOPUP', opener: (_, __) async { opened = true; return true; });
      }, child: const Text('Тест')),
    ))));
    await tester.tap(find.text('Тест'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(opened, isFalse);
  });
}
