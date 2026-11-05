import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:intercity_mobile/core/constants/app_constants.dart';
import 'package:intercity_mobile/core/widgets/intercity_static_tile_map.dart';
import '../../support/memory_tile_provider.dart';

void main() {
  testWidgets(
      'home requests only visible pixels and reuses interactive map cache',
      (tester) async {
    const z = 12, x = 2987, y = 1389;
    final center = LatLng(
      math.atan((math.exp(math.pi * (1 - 2 * (y + .5) / (1 << z))) -
                  math.exp(-math.pi * (1 - 2 * (y + .5) / (1 << z)))) /
              2) *
          180 /
          math.pi,
      (x + .5) / (1 << z) * 360 - 180,
    );
    final provider = NetworkTileProvider(
        httpClient: MockClient((_) async =>
            http.Response.bytes(MemoryTileProvider().image.bytes, 200)));
    final image = provider.getImage(const TileCoordinates(x, y, z),
        TileLayer(urlTemplate: AppConstants.serverMapTileUrl));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox).first);
    await tester.runAsync(() => precacheImage(image, context));
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: SizedBox(
                width: 128,
                height: 128,
                child: IntercityStaticTileMap(
                    center: center, zoom: z.toDouble())))));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget,
        reason: 'offscreen tiles must not compete with the next screen');
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull,
        reason: 'a mode switch must reuse already decoded map pixels');
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
}
