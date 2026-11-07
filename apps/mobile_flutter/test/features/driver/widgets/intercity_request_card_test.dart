import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/features/driver/widgets/intercity_request_card.dart';
import 'package:intercity_mobile/features/driver/widgets/intercity_price_proposal_dialog.dart';

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
  testWidgets(
      'delivery action is visible first and published address and village note reach driver',
      (tester) async {
    tester.view.physicalSize = const Size(390, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var offered = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: IntercityRequestCard(request: const {
      'requestType': 'DELIVERY_CITY',
      'fromCity': 'Усть-Каменогорск',
      'toCity': 'Zhilandy',
      'fromAddressLabel': 'Шакарима 143',
      'toAddressLabel': 'проспект Каныша Сатпаева, 1',
      'comment': 'Село Черногорка, встреча у магазина',
      'price': 0,
    }, onOffer: () => offered = true)))));
    expect(find.text('Zhilandy, проспект Каныша Сатпаева, 1'), findsNothing);
    expect(find.text('проспект Каныша Сатпаева, 1'), findsOneWidget);
    await tester.tap(find.text('Предложить цену'));
    expect(offered, isTrue);
    await tester.ensureVisible(find.textContaining('Примечание:'));
    expect(find.text('Примечание: Село Черногорка, встреча у магазина'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('delivery price dialog keeps the exact passenger addresses',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: IntercityPriceProposalDialog(request: const {
      'requestType': 'DELIVERY_CITY',
      'fromCity': 'Усть-Каменогорск',
      'toCity': 'Zhilandy',
      'fromAddressLabel': 'Шакарима 143',
      'toAddressLabel': 'Каныша Сатпаева, 1',
      'price': 0
    }, onSubmit: (_) async {}))));
    expect(find.text('Шакарима 143 → Каныша Сатпаева, 1'), findsOneWidget);
    expect(find.textContaining('Zhilandy'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
