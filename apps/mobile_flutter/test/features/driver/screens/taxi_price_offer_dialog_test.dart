import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/features/driver/widgets/taxi_price_offer_dialog.dart';

void main() {
  for (final custom in [false, true]) {
    testWidgets(
        custom
            ? 'driver sends a counter offer'
            : 'driver agrees to the exact passenger price', (tester) async {
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
      if (custom) {
        await tester.tap(find.text('Своя цена'));
        await tester.pump();
        await tester.enterText(
            find.byKey(const ValueKey('driver-taxi-counter-price')), '900');
        await tester.pump();
      }
      await tester.tap(find.text(custom ? 'Предложить' : 'Отправить'));
      expect(submitted, custom ? 900 : 725);
      expect(tester.takeException(), isNull);
    });
  }
}
