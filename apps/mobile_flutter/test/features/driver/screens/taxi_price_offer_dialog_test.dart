import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/features/driver/widgets/taxi_price_offer_dialog.dart';

void main() {
  for (final extra in [0, 200, 500, 700]) {
    testWidgets('driver immediately sends price with increment $extra',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      double? submitted;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TaxiPriceOfferDialog(
        order: const {
          'price': 725,
          'currency': 'KZT',
          'fromAddress': 'Шакарима 10',
          'toAddress': 'Серикбаева 8/1А'
        },
        secondsLeft: 30,
        onSubmit: (price) => submitted = price,
        onReject: () {},
      ))));
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find
          .text(extra == 0 ? 'Принять цену пассажира' : '${725 + extra} ₸'));
      expect(submitted, 725 + extra);
      expect(tester.takeException(), isNull);
    });
  }
}
