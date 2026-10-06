import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'browser_location_model.dart';

Future<BrowserLocation?> getBrowserLocation() {
  final geolocation = web.window.navigator.geolocation;
  final completer = Completer<BrowserLocation?>();
  geolocation.getCurrentPosition(
    ((web.GeolocationPosition position) {
      final coords = position.coords;
      if (completer.isCompleted) return;
      completer.complete(
        BrowserLocation(
          latitude: coords.latitude,
          longitude: coords.longitude,
          accuracy: coords.accuracy,
          timestamp:
              DateTime.fromMillisecondsSinceEpoch(position.timestamp.toInt()),
        ),
      );
    }).toJS,
    ((web.GeolocationPositionError error) {
      if (!completer.isCompleted) completer.complete(null);
    }).toJS,
    web.PositionOptions(
      enableHighAccuracy: true,
      timeout: 12000,
      maximumAge: 0,
    ),
  );
  return completer.future.timeout(
    const Duration(seconds: 13),
    onTimeout: () => null,
  );
}
