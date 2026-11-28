import 'package:flutter/material.dart';
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
        'WhatsApp delivery is explained before requesting a password (dark=$dark)',
        (tester) async {
      await open(tester, dark: dark);
      expect(find.textContaining('Одноразовый код придёт сообщением в WhatsApp'),
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

  for (final action in ['Отправить код на WhatsApp', 'Написать в техподдержку']) {
    testWidgets('A valid account phone is required for $action', (tester) async {
      await open(tester);
      final button = find.text(action);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Введите телефон аккаунта полностью'), findsOneWidget);
      expect(find.text('Сохранить пароль и войти'), findsNothing);
    });
  }

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
