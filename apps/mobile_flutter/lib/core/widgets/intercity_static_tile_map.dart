import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../constants/app_constants.dart';

class IntercityStaticTileMap extends StatelessWidget {
  const IntercityStaticTileMap({
    super.key,
    required this.center,
    this.zoom = 12,
    this.dark,
  });

  final LatLng center;
  final double zoom;
  final bool? dark;

  @override
  Widget build(BuildContext context) {
    final isDark = dark ?? Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (width <= 0 || height <= 0) {
          return const SizedBox.shrink();
        }

        final z = zoom.round().clamp(1, 18);
        final scale = math.pow(2, z).toDouble();
        final centerTile = _latLngToTile(center, scale);
        final centerPx = Offset(centerTile.dx * 256, centerTile.dy * 256);
        final topLeftPx = centerPx - Offset(width / 2, height / 2);
        final startX = (topLeftPx.dx / 256).floor() - 1;
        final startY = (topLeftPx.dy / 256).floor() - 1;
        final endX = ((topLeftPx.dx + width) / 256).ceil() + 1;
        final endY = ((topLeftPx.dy + height) / 256).ceil() + 1;
        final maxTile = 1 << z;

        final children = <Widget>[
          Positioned.fill(
              child: ColoredBox(
                  color: isDark
                      ? const Color(0xFF151024)
                      : const Color(0xFFF1ECFF),
                  child: const Center(child: Text('Загрузка карты…')))),
        ];

        for (var x = startX; x <= endX; x++) {
          for (var y = startY; y <= endY; y++) {
            if (y < 0 || y >= maxTile) continue;
            final wrappedX = ((x % maxTile) + maxTile) % maxTile;
            final left = x * 256 - topLeftPx.dx;
            final top = y * 256 - topLeftPx.dy;
            children.add(
              Positioned(
                left: left,
                top: top,
                width: 256,
                height: 256,
                child: Image.network(
                  _tileUrl(wrappedX, y, z, isDark),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  webHtmlElementStrategy: WebHtmlElementStrategy.never,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            );
          }
        }

        if (isDark) {
          children.add(
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF090713).withValues(alpha: 0.10),
                ),
              ),
            ),
          );
        }

        return ClipRect(child: Stack(children: children));
      },
    );
  }

  Offset _latLngToTile(LatLng point, double scale) {
    final latRad = point.latitude * math.pi / 180;
    final x = (point.longitude + 180) / 360 * scale;
    final y =
        (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
            2 *
            scale;
    return Offset(x, y);
  }

  String _tileUrl(int x, int y, int z, bool isDark) {
    final subdomain = AppConstants
        .mapTileSubdomains[(x + y) % AppConstants.mapTileSubdomains.length];
    return AppConstants.osmTileUrl
        .replaceAll('{s}', subdomain)
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y');
  }
}
