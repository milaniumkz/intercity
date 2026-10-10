import 'package:latlong2/latlong.dart';
import 'browser_location_model.dart';
import 'current_location.dart';
import 'browser_location_error.dart';

// Confirmed trip context survives screen changes, without treating it as GPS.
class LocationSession {
  BrowserLocation? _fix;
  Future<BrowserLocation?>? _pendingFix;
  bool _automaticAttempted = false;
  BrowserLocationException? _permissionError;

  // Keep the request alive across home -> booking navigation, including denial.
  Future<BrowserLocation?> locate(
    Future<BrowserLocation?> Function() provider, {
    bool retry = false,
  }) async {
    final cached = freshFix;
    if (!retry && cached != null) return cached;
    if (_pendingFix != null) return _pendingFix;
    if (!retry && _permissionError != null) throw _permissionError!;
    if (!retry && _automaticAttempted) return null;
    if (retry) _permissionError = null;
    _automaticAttempted = true;
    final request = provider();
    _pendingFix = request;
    try {
      final fix = await request;
      if (fix != null) rememberFix(fix);
      return fix;
    } on BrowserLocationException catch (error) {
      if (error.reason == BrowserLocationFailure.permissionDenied) {
        _permissionError = error;
      } else {
        _automaticAttempted = false;
      }
      rethrow;
    } finally {
      if (identical(_pendingFix, request)) _pendingFix = null;
    }
  }

  Map<String, dynamic>? city;
  final _reverse = <String, ({DateTime at, Map<String, dynamic> data})>{};
  BrowserLocation? get freshFix =>
      _fix != null && isReliableCurrentLocation(_fix!) ? _fix : null;
  void rememberFix(BrowserLocation fix) {
    if (!isReliableCurrentLocation(fix)) return;
    _automaticAttempted = false;
    _permissionError = null;
    _fix = BrowserLocation(
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracy: fix.accuracy,
        timestamp: fix.timestamp ?? DateTime.now());
  }

  final _reversePending = <String, Future<Map<String, dynamic>>>{};
  Future<Map<String, dynamic>> resolveReverse(
      LatLng point, Future<Map<String, dynamic>> Function() provider) async {
    final cached = reverse(point);
    if (cached != null) return cached;
    final key = _key(point);
    if (_reversePending[key] != null) return _reversePending[key]!;
    final request = provider();
    _reversePending[key] = request;
    try {
      final data = await request;
      rememberReverse(point, data);
      return data;
    } finally {
      if (identical(_reversePending[key], request)) _reversePending.remove(key);
    }
  }

  String _key(LatLng p) => '${p.latitude}:${p.longitude}';
  Map<String, dynamic>? reverse(LatLng p) {
    final entry = _reverse[_key(p)];
    return entry != null &&
            DateTime.now().difference(entry.at) < const Duration(minutes: 2)
        ? entry.data
        : null;
  }

  void rememberReverse(LatLng p, Map<String, dynamic> data) {
    if (data['cityResolved'] == false ||
        data['addressResolved'] == false ||
        (data['address'] ?? '').toString().trim().isEmpty) {
      return;
    }
    if (_reverse.length >= 50) _reverse.remove(_reverse.keys.first);
    _reverse[_key(p)] =
        (at: DateTime.now(), data: Map<String, dynamic>.from(data));
  }

  void clear() {
    _fix = null;
    _automaticAttempted = false;
    _permissionError = null;
    city = null;
    _reverse.clear();
  }
}

final sharedLocationSession = LocationSession();
