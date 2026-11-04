import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/core/utils/referral_code.dart';
import 'package:intercity_mobile/features/auth/screens/register_screen.dart';

class _Api extends ApiClient {
  Map? registration;
  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data,
      Map<String, dynamic>? queryParameters,
      Options? options}) async {
    if (path == '/auth/register') registration = data as Map;
    return Response(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'accessToken': 'test-only-access',
          'refreshToken': 'test-only-refresh'
        });
  }
}

void main() {
  test(
      'codes, copied hash links, query links and escaped links normalize consistently',
      () {
    for (final input in [
      'invite42',
      'https://example.test/#/ref/invite42',
      'https://example.test/?ref=invite42',
      'https://example.test/?referralCode=invite42',
      'https://example.test/%23/ref/invite42'
    ]) {
      expect(normalizeReferralCode(input), 'INVITE42');
    }
    expect(normalizeReferralCode(' '), isNull);
  });
  testWidgets(
      'current referral link overrides saved code and is sent during registration',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await AppPreferences.setPendingReferralCode('OLD123');
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _Api();
    final router = GoRouter(initialLocation: '/register', routes: [
      GoRoute(
          path: '/register',
          builder: (_, __) => RegisterScreen(
              referralCode: 'https://example.test/#/ref/invite42',
              apiClient: api)),
      GoRoute(
          path: '/order',
          builder: (_, __) => const Scaffold(body: Text('Registered')))
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    final ref = find.widgetWithText(
        TextFormField, 'Реферальная ссылка или код (опционально)');
    expect(tester.widget<TextFormField>(ref).controller!.text, 'INVITE42');
    for (final entry in {
      'Имя': 'Invited QA',
      'Телефон': '7000000999',
      'Пароль': 'LocalFixture2026!'
    }.entries) {
      final field = find.widgetWithText(TextFormField, entry.key);
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
    }
    final submit = find.text('Создать аккаунт');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(api.registration!['referralCode'], 'INVITE42');
    expect(find.text('Registered'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
