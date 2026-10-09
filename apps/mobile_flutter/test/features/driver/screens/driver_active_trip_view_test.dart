import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/features/driver/widgets/driver_active_trip_view.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(360, 640),
    const Size(1280, 800)
  ]) {
    testWidgets(
        'trip controls stay visible and advance without scrolling at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var phase = 0;
      const labels = ['На месте', 'Начать поездку', 'Завершить поездку'];
      await tester.pumpWidget(MaterialApp(
          home: StatefulBuilder(
              builder: (context, setState) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: const TextScaler.linear(1.5),
                      padding: const EdgeInsets.only(bottom: 24)),
                  child: DriverActiveTripView(
                    map: const ColoredBox(
                        color: Colors.blue, key: ValueKey('trip-map')),
                    passenger: 'Олег',
                    from: 'Усть-Каменогорск, проспект Назарбаева 8/1',
                    to: 'Усть-Каменогорск, улица Оралхана Бокея 24',
                    price: '700 ₸',
                    status: 'Водитель едет',
                    payment: 'Наличные',
                    onRefresh: () {},
                    onCall: () {},
                    onChat: () {},
                    onNavigate: () {},
                    actionLabel: labels[phase],
                    actionIcon: Icons.navigation,
                    onAction: () =>
                        setState(() => phase = (phase + 1).clamp(0, 2)),
                  )))));
      for (var i = 0; i < labels.length; i++) {
        await tester.pump();
        final button = find.byKey(const ValueKey('driver-primary-ride-action'));
        expect(button.hitTestable(), findsOneWidget);
        final bounds = tester.getRect(button);
        expect(bounds.bottom, lessThanOrEqualTo(size.height - 24));
        expect(tester.getRect(find.byKey(const ValueKey('trip-map'))).height,
            greaterThan(0));
        expect(find.text(labels[i]), findsOneWidget);
        expect(find.byType(Scrollable), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(button);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
