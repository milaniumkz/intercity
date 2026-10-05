import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

class IntercityHtmlTileMap extends StatelessWidget {
  const IntercityHtmlTileMap({
    super.key,
    required this.center,
    required this.zoom,
    required this.dark,
  });

  final LatLng center;
  final double zoom;
  final bool dark;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
