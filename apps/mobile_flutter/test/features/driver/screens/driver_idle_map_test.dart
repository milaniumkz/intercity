import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:intercity_mobile/features/driver/widgets/driver_idle_map.dart';
import '../../../support/memory_tile_provider.dart';

void main() {
  testWidgets(
      'GPS jitter preserves camera and user gestures; real movement follows without recreating map',
      (tester) async {
    const start = LatLng(49.95, 82.60),
        jitter = LatLng(49.95001, 82.60001),
        next = LatLng(49.951, 82.601),
        last = LatLng(49.952, 82.602);
    final key = GlobalKey<DriverIdleMapState>();
    Widget page(LatLng p) => MaterialApp(
        home: Scaffold(
            body: DriverIdleMap(
                key: key,
                point: p,
                tileProvider: MemoryTileProvider(),
                marker: const Icon(Icons.navigation))));
    await tester.pumpWidget(page(start));
    await tester.pump(const Duration(seconds: 1));
    final state = tester.state(find.byType(FlutterMap));
    final map =
        tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
    await tester.pumpWidget(page(jitter));
    await tester.pump(const Duration(seconds: 1));
    expect(map.camera.center, start);
    await tester.pumpWidget(page(next));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.state(find.byType(FlutterMap)), same(state));
    expect(map.camera.center.latitude, closeTo(next.latitude, .000001));
    await tester.drag(find.byType(FlutterMap), const Offset(100, 20));
    await tester.pump(const Duration(seconds: 1));
    final selected = map.camera.center;
    await tester.pumpWidget(page(last));
    await tester.pump(const Duration(seconds: 1));
    expect(map.camera.center, selected);
    key.currentState!.recenter();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(map.camera.center.latitude, closeTo(last.latitude, .000001));
    await tester.pumpWidget(const SizedBox());
  });
}
