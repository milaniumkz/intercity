import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/driver/screens/driver_wallet_page.dart';
import 'package:intercity_mobile/features/passenger/screens/wallet_page.dart';

class _WalletApi extends ApiClient {
  final calls = <String>[];
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    calls.add(path);
    final rub = path.contains('RUB');
    return Response(
      requestOptions: RequestOptions(path: path),
      data: {
        'currency': rub ? 'RUB' : 'KZT',
        'money': rub ? 120 : 7000,
        'bonus': rub ? 50.25 : 8000,
        'transactions': [
          {
            'type': 'TOPUP_APPROVED',
            'direction': 'CREDIT',
            'amount': 120,
            'note': 'Пополнение ${rub ? 'RUB' : 'KZT'}',
            'createdAt': '2026-10-06'
          },
          {
            'type': 'ORDER_COMMISSION_DEBIT',
            'direction': 'DEBIT',
            'amount': 10,
            'note': 'Комиссия ${rub ? 'RUB' : 'KZT'}',
            'createdAt': '2026-10-06'
          },
        ]
      },
      statusCode: 200,
    );
  }
}

void main() {
  for (final driver in [false, true]) {
    testWidgets(
        '${driver ? 'driver' : 'passenger'} switches independent wallets',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _WalletApi();
      await tester.pumpWidget(MaterialApp(
          home: driver
              ? DriverWalletPage(apiClient: api)
              : WalletPage(apiClient: api)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(api.calls.last, '/wallet?currency=KZT');
      expect(find.text('1 бонус = 1 ₸'), findsOneWidget);
      await tester.tap(find.text('Рубли ₽'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(api.calls.last, '/wallet?currency=RUB');
      expect(find.text('1 бонус = 1 ₽'), findsOneWidget);
      expect(find.text('50,25'), findsOneWidget);
      expect(find.text('1 бонус = 1 ₸'), findsNothing);
      if (driver) {
        expect(find.text('120 ₽'), findsOneWidget);
        await tester.ensureVisible(find.text('Списания'));
        await tester.tap(find.text('Списания'));
        await tester.pump();
        expect(find.text('Комиссия RUB'), findsOneWidget);
        expect(find.text('Пополнение RUB'), findsNothing);
        await tester.tap(find.text('Пополнения'));
        await tester.pump();
        expect(find.text('Пополнение RUB'), findsOneWidget);
        expect(find.text('Комиссия RUB'), findsNothing);
        await tester.ensureVisible(find.text('Тенге ₸'));
      }
      await tester.tap(find.text('Тенге ₸'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(api.calls.last, '/wallet?currency=KZT');
      expect(find.text('1 бонус = 1 ₸'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
