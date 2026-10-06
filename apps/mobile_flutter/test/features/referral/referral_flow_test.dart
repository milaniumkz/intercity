import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/utils/route_guard.dart';
import 'package:intercity_mobile/features/referral/widgets/referral_profile_card.dart';
import 'package:intercity_mobile/features/referral/screens/referral_landing_page.dart';

class _ReferralApi extends ApiClient {
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: path == '/auth/referral'
              ? {
                  'refCode': 'INVITE123',
                  'refLink':
                      'https://intercity.89-207-255-27.sslip.io/#/ref/INVITE123',
                  'invitedCount': 3,
                  'earned': {'KZT': 25, 'RUB': 75},
                }
              : {
                  'appStoreUrl': 'https://apps.apple.com/app/id123',
                  'googlePlayUrl':
                      'https://play.google.com/store/apps/details?id=test'
                });
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
      'profile shows personal link, referral totals and copies the current link',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = call.arguments['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ReferralProfileCard(user: const {
      'refCode': 'INVITE123',
      'refLink': 'https://old.invalid'
    }, apiClient: _ReferralApi()))));
    await tester.pumpAndSettle();
    expect(find.text('Приглашено: 3'), findsOneWidget);
    expect(find.text('Начислено: 25.00 ₸ · 75.00 ₽'), findsOneWidget);
    await tester.tap(find.text('Скопировать ссылку'));
    await tester.pumpAndSettle();
    expect(copied, 'https://intercity.89-207-255-27.sslip.io/#/ref/INVITE123');
  });
  testWidgets(
      'store downloads follow registration so invitation survives installation',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: ReferralLandingPage(
            referralCode: 'INVITE123', apiClient: _ReferralApi())));
    await tester.pumpAndSettle();
    expect(find.text('Зарегистрироваться'), findsOneWidget);
    expect(find.text('Скачать в App Store'), findsNothing);
    await tester.pumpWidget(MaterialApp(
        home: ReferralLandingPage(
            key: UniqueKey(),
            referralCode: 'INVITE123',
            downloadOnly: true,
            apiClient: _ReferralApi())));
    await tester.pumpAndSettle();
    expect(find.text('Приглашение закреплено'), findsOneWidget);
    expect(find.text('Скачать в App Store'), findsOneWidget);
    expect(find.text('Скачать в Google Play'), findsOneWidget);
    expect(find.text('Зарегистрироваться'), findsNothing);
    expect(
        resolveAuthRedirect(path: '/ref/INVITE123/download', hasToken: false),
        '/ref/INVITE123');
    expect(resolveAuthRedirect(path: '/ref/INVITE123/download', hasToken: true),
        isNull);
  });
}
