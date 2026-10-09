import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/features/driver/widgets/driver_offer_expiry_watcher.dart';

void main() {
  testWidgets('deadline expiration closes an offer once without rejecting it',
      (tester) async {
    var remaining = 2, expired = 0, ticks = 0;
    await tester.pumpWidget(DriverOfferExpiryWatcher(
        secondsLeft: () => remaining,
        onTick: (_) => ticks++,
        onExpired: () => expired++,
        child: const SizedBox()));
    await tester.pump(const Duration(seconds: 1));
    expect(ticks, 1);
    expect(expired, 0);
    remaining = 0;
    await tester.pump(const Duration(seconds: 1));
    expect(expired, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(expired, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'withdrawn offer closes, and removing the dialog cancels its timer',
      (tester) async {
    var available = true, expired = 0;
    Widget watcher() => DriverOfferExpiryWatcher(
        secondsLeft: () => available ? 20 : 0,
        onTick: (_) {},
        onExpired: () => expired++,
        child: const SizedBox());
    await tester.pumpWidget(watcher());
    available = false;
    await tester.pump(const Duration(seconds: 1));
    expect(expired, 1);
    await tester.pumpWidget(const SizedBox());
    available = true;
    await tester.pumpWidget(watcher());
    await tester.pumpWidget(const SizedBox());
    available = false;
    await tester.pump(const Duration(seconds: 2));
    expect(expired, 1);
  });
}
