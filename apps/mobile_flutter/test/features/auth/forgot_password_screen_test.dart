import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intercity_mobile/features/auth/screens/forgot_password_screen.dart';

void main() {
  Future<GoRouter> open(WidgetTester tester, {bool dark = false}) async {
    final router = GoRouter(initialLocation: '/forgot-password', routes: [
      GoRoute(
          path: '/forgot-password',
          builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('Экран входа'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      theme: dark ? ThemeData.dark() : ThemeData.light(),
    ));
    await tester.pumpAndSettle();
    addTearDown(router.dispose);
    return router;
  }

  for (final dark in [false, true]) {
    testWidgets(
        'unavailable recovery is explained before requesting a password (dark=$dark)',
        (tester) async {
      await open(tester, dark: dark);
      expect(
          find.textContaining('Автоматическое восстановление пока недоступно'),
          findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText,
          isFalse);
      expect(find.text('Обновить пароль'), findsNothing);
      expect(find.text('Пароль обновлён'), findsNothing);
      await tester
          .tap(find.byKey(const ValueKey('forgot_password_back_button')));
      await tester.pumpAndSettle();
      expect(find.text('Экран входа'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'request copies only the validated account phone and does not claim to reset it',
      (tester) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await open(tester);
    final button = find.text('Скопировать обращение');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(copied, isNull);
    expect(find.text('Введите телефон аккаунта полностью'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '7000000123');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(copied, contains('Телефон аккаунта: +77000000123'));
    expect(copied, contains('Готов подтвердить'));
    expect(find.textContaining('Текст скопирован.'), findsOneWidget);
  });

  testWidgets('small phone and open keyboard leave the return action reachable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    addTearDown(tester.view.reset);
    await open(tester);
    await tester.tap(find.byType(TextFormField));
    final back = find.text('Вернуться ко входу');
    await tester.ensureVisible(back);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('Экран входа'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
