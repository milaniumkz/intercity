import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/passenger/screens/orders_history_page.dart';
import 'package:intercity_mobile/features/passenger/screens/wallet_page.dart';

class _HistoryApi extends ApiClient {
  _HistoryApi({this.failWallet = false});
  final bool failWallet;
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    if (failWallet && path.startsWith('/wallet')) {
      throw DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.connectionError);
    }
    return Response(
        requestOptions: RequestOptions(path: path),
        data: path.startsWith('/wallet')
            ? {
                'bonus': 37,
                'transactions': [
                  {
                    'balanceSource': 'BONUS',
                    'direction': 'CREDIT',
                    'amount': 37,
                    'note': 'Реальное начисление',
                    'createdAt': '2026-10-23T12:00:00Z'
                  },
                  {
                    'balanceSource': 'MONEY',
                    'direction': 'CREDIT',
                    'amount': 500,
                    'note': 'Денежная операция',
                    'createdAt': '2026-10-23T12:00:00Z'
                  },
                ],
              }
            : []);
  }
}

void main() {
  testWidgets('empty server history never invents passenger trips',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: OrdersHistoryPage(apiClient: _HistoryApi())));
    await tester.pumpAndSettle();
    expect(find.text('Активных поездок пока нет'), findsOneWidget);
    expect(find.textContaining('Алматы'), findsNothing);
    await tester.tap(find.text('Завершенные'));
    await tester.pumpAndSettle();
    expect(find.text('Завершённых поездок пока нет'), findsOneWidget);
    await tester.tap(find.text('Отмененные'));
    await tester.pumpAndSettle();
    expect(find.text('Отменённых поездок пока нет'), findsOneWidget);
  });
  testWidgets('bonus history shows server bonus entries only', (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester
        .pumpWidget(MaterialApp(home: WalletPage(apiClient: _HistoryApi())));
    await tester.pumpAndSettle();
    expect(find.textContaining('Реальное начисление'), findsOneWidget);
    expect(find.textContaining('23.10.2026'), findsOneWidget);
    expect(find.textContaining('Денежная операция'), findsNothing);
    expect(find.textContaining('2024'), findsNothing);
  });
  testWidgets('failed wallet load offers retry instead of fake history',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: WalletPage(apiClient: _HistoryApi(failWallet: true))));
    await tester.pumpAndSettle();
    expect(find.text('Повторить загрузку'), findsOneWidget);
    expect(find.textContaining('2024'), findsNothing);
  });
}
