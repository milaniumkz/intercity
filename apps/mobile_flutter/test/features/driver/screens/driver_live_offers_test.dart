import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/features/driver/screens/driver_home_page.dart';
import 'package:intercity_mobile/features/driver/widgets/driver_daily_bonus_card.dart';

class _OffersApi extends ApiClient {
  final paths = <String>[];
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    paths.add(path);
    dynamic data = <String, dynamic>{};
    if (path == '/driver/profile') {
      data = {
        'id': 'driver',
        'status': 'ACTIVE',
        'acceptIntercity': false,
        'online': {'isOnline': true}
      };
    }
    if (path == '/orders/my' || path == '/driver/intercity/active') data = [];
    if (path == '/driver/orders/nearby') {
      data = [
        {
          'id': 'offer',
          'requestType': 'CITY_FIXED',
          'currency': 'KZT',
          'price': 900,
          'fromAddress': 'Шакарима 10',
          'toAddress': 'Серикбаева 8/1А',
          'offerExpiresAt': DateTime.now()
              .subtract(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
          'offerExpiresInSec': 30,
        }
      ];
    }
    return Response(requestOptions: RequestOptions(path: path), data: data);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
      'direct active route loads real online profile and displays the live offer',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _OffersApi();
    await tester.pumpWidget(MaterialApp(
        home: DriverHomePage(routeStage: 'active', apiClient: api)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.paths, contains('/driver/profile'));
    expect(api.paths, contains('/driver/orders/nearby'));
    expect(find.text('Фиксированный заказ'), findsWidgets);
    expect(find.textContaining('Шакарима 10'), findsWidgets);
    expect(find.textContaining('Серикбаева 8/1А'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets(
      'credited daily bonus disappears while the next daily goal remains visible',
      (tester) async {
    for (final credited in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: DriverDailyBonusCard(bonus: {
        'enabled': true,
        'credited': credited,
        'targetOrders': 10,
        'completed': credited ? 10 : 4,
        'rewardAmount': 1000,
        'currency': 'KZT',
      }))));
      expect(find.byKey(const ValueKey('driver-daily-bonus')),
          credited ? findsNothing : findsOneWidget);
    }
  });
  test(
      'bonus notification is once per account, currency and service day across reloads',
      () async {
    expect(
        await AppPreferences.claimDailyBonusNotice(
            'driver', '2026-10-09', 'KZT'),
        isTrue);
    expect(
        await AppPreferences.claimDailyBonusNotice(
            'driver', '2026-10-09', 'KZT'),
        isFalse);
    expect(
        await AppPreferences.claimDailyBonusNotice(
            'driver', '2026-10-10', 'KZT'),
        isTrue);
    expect(
        await AppPreferences.claimDailyBonusNotice(
            'driver', '2026-10-09', 'RUB'),
        isTrue);
    expect(
        await AppPreferences.claimDailyBonusNotice(
            'other', '2026-10-09', 'KZT'),
        isTrue);
  });
}
