import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/features/auth/screens/login_screen.dart';
import 'package:intercity_mobile/core/widgets/ic_premium.dart';

void main() {
  testWidgets('login stays scrollable above the keyboard on a small phone',
      (tester) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final submit = find.byType(ICGradientButton);
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    expect(tester.getRect(submit).bottom, lessThanOrEqualTo(340));
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Введите телефон'), findsOneWidget);
    expect(find.text('Введите пароль'), findsOneWidget);
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    expect(tester.getRect(submit).bottom, lessThanOrEqualTo(340));
    expect(tester.takeException(), isNull);
  });
}
