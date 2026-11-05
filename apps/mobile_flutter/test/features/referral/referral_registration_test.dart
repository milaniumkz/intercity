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
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(
          requestOptions: RequestOptions(path: path),
          data: {'valid': storedValid});
  Map? registration;
  bool failLogin = false;
  bool storedValid = true;
  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data,
      Map<String, dynamic>? queryParameters,
      Options? options}) async {
    if (path == '/auth/register') registration = data as Map;
    if (path == '/auth/login' && failLogin) {
      throw DioException(
          requestOptions: RequestOptions(path: path),
          response: Response(
              requestOptions: RequestOptions(path: path), statusCode: 503));
    }
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
    expect(find.textContaining('Оно применится автоматически'), findsOneWidget);
    expect(
        find.widgetWithText(
            TextFormField, 'Реферальная ссылка или код (опционально)'),
        findsNothing);
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
  Future<void> fill(WidgetTester tester) async {
    for (final entry in {
      'Имя': 'Приглашённый пользователь',
      'Телефон': '7000000999',
      'Пароль': 'Secret123!'
    }.entries) {
      final field = find.widgetWithText(TextFormField, entry.key);
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
    }
  }

  testWidgets(
      'a new referral link in the same open registration overrides the old hidden code and is cleared after account creation',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _Api();
    final router = GoRouter(initialLocation: '/register?ref=OLD111', routes: [
      GoRoute(
          path: '/register',
          builder: (_, state) => RegisterScreen(
              referralCode: state.uri.queryParameters['ref'], apiClient: api)),
      GoRoute(
          path: '/order',
          builder: (_, __) => const Scaffold(body: Text('Registered')))
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    router.go('/register?ref=NEW222');
    await tester.pumpAndSettle();
    expect(await AppPreferences.getPendingReferralCode(), 'NEW222');
    await fill(tester);
    await tester.ensureVisible(find.text('Создать аккаунт'));
    await tester.tap(find.text('Создать аккаунт'));
    await tester.pumpAndSettle();
    expect(api.registration!['referralCode'], 'NEW222');
    expect(await AppPreferences.getPendingReferralCode(), isNull);
    expect(find.text('NEW222'), findsNothing);
    expect(find.text('OLD111'), findsNothing);
  });
  testWidgets(
      'successful registration clears pending invitation even if the subsequent login fails',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _Api()..failLogin = true;
    await tester.pumpWidget(MaterialApp(
        home: RegisterScreen(referralCode: 'INVITE42', apiClient: api)));
    await tester.pumpAndSettle();
    await fill(tester);
    await tester.ensureVisible(find.text('Создать аккаунт'));
    await tester.tap(find.text('Создать аккаунт'));
    await tester.pumpAndSettle();
    expect(api.registration!['referralCode'], 'INVITE42');
    expect(await AppPreferences.getPendingReferralCode(), isNull);
  });
  testWidgets(
      'an invalid old browser invitation is removed only after server confirmation',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await AppPreferences.setPendingReferralCode('DELETED1');
    final api = _Api()..storedValid = false;
    await tester.pumpWidget(MaterialApp(home: RegisterScreen(apiClient: api)));
    await tester.pumpAndSettle();
    expect(await AppPreferences.getPendingReferralCode(), isNull);
    expect(find.textContaining('Приглашение сохранено'), findsNothing);
  });
}
