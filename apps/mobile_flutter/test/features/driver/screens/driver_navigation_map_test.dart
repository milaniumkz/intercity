import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:intercity_mobile/features/driver/widgets/driver_navigation_map.dart';

void main() {
  testWidgets(
      'GPS moves and rotates the existing map, gestures pause follow and button restores it',
      (tester) async {
    const start = LatLng(49.95, 82.60),
        next = LatLng(49.951, 82.601),
        last = LatLng(49.952, 82.602);
    Widget page(LatLng point, double heading) => MaterialApp(
        home: Scaffold(
            body: DriverNavigationMap(
                driver: point,
                target: last,
                routeStart: start,
                heading: heading,
                route: const [start, next, last])));
    await tester.pumpWidget(page(start, 0));
    await tester.pump(const Duration(seconds: 1));
    final controller =
        tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
    await tester.pumpWidget(page(next, 120));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController,
        same(controller));
    expect(controller.camera.center.latitude, closeTo(next.latitude, 0.00001));
    expect((controller.camera.rotation + 360) % 360, closeTo(240, 0.01));
    await tester.drag(find.byType(FlutterMap), const Offset(100, 20));
    await tester.pump(const Duration(seconds: 1));
    final manuallySelected = controller.camera.center;
    await tester.pumpWidget(page(last, 180));
    await tester.pump(const Duration(seconds: 1));
    expect(controller.camera.center, manuallySelected);
    await tester.tap(find.byTooltip('Следовать за машиной'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.camera.center.latitude, closeTo(last.latitude, 0.00001));
    expect((controller.camera.rotation + 360) % 360, closeTo(180, 0.01));
    await tester.pumpWidget(const SizedBox());
  });
}
