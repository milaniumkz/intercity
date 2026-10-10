import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'browser_location_model.dart';
import 'browser_location_error.dart';
import 'current_location.dart';

Future<BrowserLocation?> getBrowserLocation() async {
  final geolocation = web.window.navigator.geolocation;
  final completer = Completer<BrowserLocation?>();
  BrowserLocation? best;
  var failure = BrowserLocationFailure.timeout;
  int? watch;
  final deadline = Timer(const Duration(seconds: 30), () {
    if (completer.isCompleted) return;
    if (best != null) {
      completer.complete(best);
    } else {
      completer.completeError(BrowserLocationException(failure));
    }
  });
  try {
    // Ask for an already available accurate position while GPS warms up.
    // Both paths use the same age/accuracy checks and never accept a coarse fix.
    geolocation.getCurrentPosition(
      ((web.GeolocationPosition position) {
        if (completer.isCompleted) return;
        final fix = BrowserLocation(
            latitude: position.coords.latitude,
            longitude: position.coords.longitude,
            accuracy: position.coords.accuracy,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
                position.timestamp.toInt()));
        if (isReliableCurrentLocation(fix)) completer.complete(fix);
      }).toJS,
      ((web.GeolocationPositionError error) {
        if (!completer.isCompleted && error.code == 1) {
          completer.completeError(const BrowserLocationException(
              BrowserLocationFailure.permissionDenied));
        }
      }).toJS,
      web.PositionOptions(
          enableHighAccuracy: false, maximumAge: 15000, timeout: 1500),
    );
    // Keep listening if the first fix is coarse: mobile browsers often refine
    // Wi-Fi coordinates only after the GPS receiver acquires a position.
    watch = geolocation.watchPosition(
      ((web.GeolocationPosition position) {
        if (completer.isCompleted) return;
        final coords = position.coords;
        final fix = BrowserLocation(
          latitude: coords.latitude,
          longitude: coords.longitude,
          accuracy: coords.accuracy,
          timestamp:
              DateTime.fromMillisecondsSinceEpoch(position.timestamp.toInt()),
        );
        if (best == null || fix.accuracy < best!.accuracy) best = fix;
        if (isReliableCurrentLocation(fix)) completer.complete(fix);
      }).toJS,
      ((web.GeolocationPositionError error) {
        if (completer.isCompleted) return;
        if (error.code == 1) {
          completer.completeError(const BrowserLocationException(
              BrowserLocationFailure.permissionDenied));
        } else {
          failure = error.code == 2
              ? BrowserLocationFailure.unavailable
              : BrowserLocationFailure.timeout;
        }
      }).toJS,
      web.PositionOptions(
          enableHighAccuracy: true, timeout: 25000, maximumAge: 30000),
    );
    return await completer.future;
  } finally {
    deadline.cancel();
    if (watch != null) geolocation.clearWatch(watch);
  }
}
