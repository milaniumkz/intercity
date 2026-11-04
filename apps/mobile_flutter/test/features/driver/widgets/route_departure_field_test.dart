import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/features/driver/widgets/route_departure_field.dart';

void main() {
  test('saved local calendar day is retained across UTC midnight', () {
    expect(
        formatRouteDeparture(DateTime.parse('2026-10-28T20:30:00Z'),
            offsetMinutes: 300),
        '29.10.2026 01:30');
    expect(formatRouteDeparture(null), 'Дата и время не указаны');
  });

  testWidgets(
      'cancel time picker does not submit a partially selected departure',
      (tester) async {
    DateTime? selected;
    final future = DateTime.now().add(const Duration(days: 1));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RouteDepartureField(
                value: future, onChanged: (v) => selected = v))));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });

  testWidgets('date and time confirmation emits one complete local departure',
      (tester) async {
    DateTime? selected;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final future =
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 16, 30);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RouteDepartureField(
                value: future, onChanged: (v) => selected = v))));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();
    expect(selected, future);
    expect(tester.takeException(), isNull);
  });
}
