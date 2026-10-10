import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Local pixels isolate map interactions from tile servers in widget tests.
class MemoryTileProvider extends TileProvider {
  final image = MemoryImage(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII='));
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      image;
}
