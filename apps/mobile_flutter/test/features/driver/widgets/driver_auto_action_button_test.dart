import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/features/driver/widgets/driver_auto_action_button.dart';

void main() {
  testWidgets('counts down 15 seconds and invokes the action exactly once',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DriverAutoActionButton(
                label: 'На месте',
                icon: Icons.check,
                onPressed: () => calls++,
                eligible: true,
                clock: tester.binding.clock.now))));
    expect(find.text('На месте · 15 с'), findsOneWidget);
    await tester.pump(const Duration(seconds: 14));
    expect(calls, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 20));
    expect(calls, 1);
  });
  testWidgets(
      'ineligible actions never auto fire; leaving eligibility cancels countdown',
      (tester) async {
    var calls = 0;
    Widget button(bool eligible) => MaterialApp(
        home: Scaffold(
            body: DriverAutoActionButton(
                label: 'Начать поездку',
                icon: Icons.play_arrow,
                onPressed: () => calls++,
                eligible: eligible,
                clock: tester.binding.clock.now)));
    await tester.pumpWidget(button(true));
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(button(false));
    await tester.pump(const Duration(seconds: 20));
    expect(calls, 0);
    await tester.pumpWidget(button(true));
    await tester.pump(const Duration(seconds: 15));
    expect(calls, 1);
  });
  testWidgets('manual tap cancels automatic action and completion stays manual',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DriverAutoActionButton(
                label: 'На месте',
                icon: Icons.check,
                onPressed: () => calls++,
                eligible: true,
                clock: tester.binding.clock.now))));
    await tester.tap(find.byType(FilledButton));
    await tester.pump(const Duration(seconds: 20));
    expect(calls, 1);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DriverAutoActionButton(
                key: const ValueKey('finish'),
                label: 'Завершить',
                icon: Icons.check,
                onPressed: () => calls++,
                clock: tester.binding.clock.now))));
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 1);
  });
}
