import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:intercity_mobile/core/widgets/passenger_map_tiles.dart';

void main() {
  testWidgets('map timeout offers a tappable retry that reloads tiles',
      (tester) async {
    final provider = PendingTiles();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: FlutterMap(
      options: const MapOptions(
          initialCenter: LatLng(49.97, 82.61), initialZoom: 14),
      children: [PassengerMapTiles(tileProvider: provider)],
    ))));
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();
    final retry = find.text('Повторить загрузку карты');
    expect(retry, findsOneWidget);
    final before = PendingImage.loads;
    await tester.tap(retry);
    await tester.pump();
    await tester.pump();
    expect(PendingImage.loads, greaterThan(before));
    expect(retry, findsNothing);
    await tester.pumpWidget(const SizedBox());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
}

class PendingTiles extends TileProvider {
  int requests = 0;
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    requests++;
    return const PendingImage(1);
  }
}

class PendingImage extends ImageProvider<PendingImage> {
  const PendingImage(this.id);
  final int id;
  static int loads = 0;
  @override
  bool operator ==(Object other) => other is PendingImage && other.id == id;
  @override
  int get hashCode => id;
  @override
  Future<PendingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
      PendingImage key, ImageDecoderCallback decode) {
    loads++;
    return OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
  }
}
