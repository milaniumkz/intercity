import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Confirms departure from a GPS fix recorded near pickup after arrival.
class PickupDepartureTracker {
  String? orderId;
  LatLng? _anchor;
  double _anchorAccuracy = 0;
  double _anchorPickupDistance = 0;
  double? _outwardDistance;
  DateTime? _outwardAt;
  bool departed = false;

  void update({
    required String? id,
    required bool arrived,
    required LatLng? pickup,
    required LatLng point,
    required double accuracy,
    required double speed,
    required DateTime timestamp,
    required DateTime now,
  }) {
    if (id != orderId || !arrived) {
      orderId = arrived ? id : null;
      _anchor = null;
      _outwardAt = null;
      _outwardDistance = null;
      departed = false;
    }
    if (!arrived ||
        id == null ||
        pickup == null ||
        !accuracy.isFinite ||
        accuracy > 40 ||
        accuracy < 0 ||
        now.difference(timestamp).inSeconds > 30 ||
        timestamp.isAfter(now)) {
      return;
    }
    final distance = const Distance().as(LengthUnit.Meter, pickup, point);
    if (_anchor == null) {
      if (distance <= 50) {
        _anchor = point;
        _anchorAccuracy = accuracy;
        _anchorPickupDistance = distance;
      }
      return;
    }
    if (departed) return;
    final displacement = const Distance().as(LengthUnit.Meter, _anchor!, point);
    if (displacement < math.max(20, accuracy + _anchorAccuracy) ||
        distance < _anchorPickupDistance + 15) {
      _outwardAt = null;
      _outwardDistance = null;
      return;
    }
    final elapsed = _outwardAt == null
        ? 0
        : timestamp.difference(_outwardAt!).inMilliseconds / 1000;
    final confirmedByPositions = elapsed >= 1 &&
        elapsed <= 30 &&
        distance - (_outwardDistance ?? distance) >= 3;
    if (speed.isFinite && speed >= 1 || confirmedByPositions) {
      departed = true;
    } else {
      _outwardAt = timestamp;
      _outwardDistance = distance;
    }
  }
}
