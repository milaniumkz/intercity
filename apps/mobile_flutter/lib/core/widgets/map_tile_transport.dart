import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';

/// Public map imagery uses one application-session connection pool. A screen
/// leaving must not abort an image another screen is taking from ImageCache.
class MapTileHttpClient extends http.BaseClient {
  static final http.Client _transport = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _transport.send(request);
  @override
  void close() {} // The map layer owns a lease, not the session transport.
}

/// Same key/provider as the interactive map, so home and booking reuse decoded
/// pixels as well as the browser/server HTTP cache. No URL cache busting.
final _staticProvider = NetworkTileProvider(httpClient: MapTileHttpClient());
final _staticOptions = TileLayer(
  tileProvider: _staticProvider,
  urlTemplate: AppConstants.serverMapTileUrl,
  userAgentPackageName: 'com.milanium.intercity',
);
ImageProvider mapTileImage(int z, int x, int y) =>
    _staticProvider.getImage(TileCoordinates(x, y, z), _staticOptions);
