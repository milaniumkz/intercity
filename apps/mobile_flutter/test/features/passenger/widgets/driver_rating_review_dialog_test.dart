import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/features/passenger/widgets/driver_rating_dialog.dart';

void main() {
  testWidgets('low rating requires explanation and submits it for review',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    int? rating;
    String? reason;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (ctx) => Scaffold(
                body: TextButton(
                    onPressed: () => showDriverRatingDialog(
                        context: ctx,
                        onSubmit: (_) async {},
                        onSubmitWithReason: (r, text) async {
                          rating = r;
                          reason = text;
                        }),
                    child: const Text('Оценить'))))));
    await tester.tap(find.text('Оценить'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.star_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Что произошло?'), findsOneWidget);
    await tester.ensureVisible(find.text('Отправить'));
    await tester.tap(find.text('Отправить'));
    await tester.pumpAndSettle();
    expect(rating, isNull);
    expect(find.textContaining('не менее 10'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField), 'Водитель ехал опасно, нарушал правила');
    await tester.ensureVisible(find.text('Отправить'));
    await tester.tap(find.text('Отправить'));
    await tester.pumpAndSettle();
    expect(rating, 1);
    expect(reason, 'Водитель ехал опасно, нарушал правила');
  });
}
