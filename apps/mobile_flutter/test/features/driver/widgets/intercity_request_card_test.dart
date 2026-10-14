import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/features/driver/widgets/intercity_request_card.dart';

void main() {
  testWidgets(
      'raw intercity fields show complete endpoints, actual departure and price, without fabricated distance',
      (tester) async {
    var offered = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: IntercityRequestCard(request: const {
      'fromCity': 'Усть-Каменогорск',
      'toCity': 'Семей',
      'fromManualAddress': 'Назарбаева 8/1',
      'toAddressLabel': 'Абая 10',
      'date': '2026-10-15T05:00:00Z',
      'price': 7000,
      'currency': 'KZT',
      'seats': 2,
    }, onOffer: () => offered = true))));
    expect(find.text('Усть-Каменогорск, Назарбаева 8/1'), findsOneWidget);
    expect(find.text('Семей, Абая 10'), findsOneWidget);
    expect(find.textContaining('15.10.2026'), findsOneWidget);
    expect(find.textContaining('7000'), findsOneWidget);
    expect(find.textContaining('0 км'), findsNothing);
    expect(find.textContaining('Сегодня'), findsNothing);
    await tester.tap(find.text('Предложить цену'));
    expect(offered, isTrue);
  });
}
