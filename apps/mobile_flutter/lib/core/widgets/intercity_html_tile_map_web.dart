import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:web/web.dart' as web;

import '../constants/app_constants.dart';

class IntercityHtmlTileMap extends StatelessWidget {
  IntercityHtmlTileMap({
    super.key,
    required this.center,
    required this.zoom,
    required this.dark,
  }) : viewType =
            'intercity-map-${center.latitude.toStringAsFixed(5)}-${center.longitude.toStringAsFixed(5)}-${zoom.toStringAsFixed(1)}-$dark';

  final LatLng center;
  final double zoom;
  final bool dark;
  final String viewType;

  @override
  Widget build(BuildContext context) {
    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (_) => _buildElement(),
    );
    return HtmlElementView(viewType: viewType);
  }

  web.HTMLDivElement _buildElement() {
    final root = web.HTMLDivElement();
    root.setAttribute('data-intercity-osm-map', 'true');
    root.style
      ..setProperty('position', 'relative')
      ..setProperty('overflow', 'hidden')
      ..setProperty('width', '100%')
      ..setProperty('height', '100%')
      ..setProperty('background', dark ? '#090713' : '#f4f1fb');

    final z = zoom.round().clamp(1, 18);
    final scale = math.pow(2, z).toDouble();
    final centerTile = _latLngToTile(center, scale);
    const width = 420.0;
    const height = 520.0;
    final centerPx = _Point(centerTile.x * 256, centerTile.y * 256);
    final topLeftPx = _Point(centerPx.x - width / 2, centerPx.y - height / 2);
    final startX = (topLeftPx.x / 256).floor() - 1;
    final startY = (topLeftPx.y / 256).floor() - 1;
    final endX = ((topLeftPx.x + width) / 256).ceil() + 1;
    final endY = ((topLeftPx.y + height) / 256).ceil() + 1;
    final maxTile = 1 << z;

    for (var x = startX; x <= endX; x++) {
      for (var y = startY; y <= endY; y++) {
        if (y < 0 || y >= maxTile) continue;
        final wrappedX = ((x % maxTile) + maxTile) % maxTile;
        final left = x * 256 - topLeftPx.x;
        final top = y * 256 - topLeftPx.y;
        final img = web.HTMLImageElement()
          ..src = _tileUrl(wrappedX, y, z)
          ..decoding = 'async';
        img.style
          ..setProperty('position', 'absolute')
          ..setProperty('left', '${left}px')
          ..setProperty('top', '${top}px')
          ..setProperty('width', '256px')
          ..setProperty('height', '256px')
          ..setProperty('user-select', 'none')
          ..setProperty('pointer-events', 'none');
        root.appendChild(img);
      }
    }

    if (dark) {
      final veil = web.HTMLDivElement();
      veil.style
        ..setProperty('position', 'absolute')
        ..setProperty('inset', '0')
        ..setProperty('background', 'rgba(9, 7, 19, 0.08)')
        ..setProperty('pointer-events', 'none');
      root.appendChild(veil);
    }

    return root;
  }

  _Point _latLngToTile(LatLng point, double scale) {
    final latRad = point.latitude * math.pi / 180;
    final x = (point.longitude + 180) / 360 * scale;
    final y =
        (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
            2 *
            scale;
    return _Point(x, y);
  }

  String _tileUrl(int x, int y, int z) {
    final subdomain = AppConstants
        .mapTileSubdomains[(x + y) % AppConstants.mapTileSubdomains.length];
    return AppConstants.osmTileUrl
        .replaceAll('{s}', subdomain)
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y');
  }
}

class _Point {
  const _Point(this.x, this.y);

  final double x;
  final double y;
}
