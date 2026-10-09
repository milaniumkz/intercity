import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Remaining distance along the road geometry; negative after passing a turn.
double? navigationRoadDistance(List<LatLng> route, LatLng driver, LatLng turn) {
  if (route.length < 2) return null;
  final cumulative = <double>[0];
  for (var i = 1; i < route.length; i++) {
    cumulative.add(cumulative.last +
        const Distance().as(LengthUnit.Meter, route[i - 1], route[i]));
  }
  double project(LatLng point) {
    var closest = double.infinity, along = 0.0;
    final scale = math.cos(point.latitude * math.pi / 180);
    for (var i = 1; i < route.length; i++) {
      final a = route[i - 1], b = route[i];
      final ax = (a.longitude - point.longitude) * scale,
          ay = a.latitude - point.latitude;
      final dx = (b.longitude - a.longitude) * scale,
          dy = b.latitude - a.latitude;
      final length = dx * dx + dy * dy;
      final t =
          length == 0 ? 0.0 : (-(ax * dx + ay * dy) / length).clamp(0.0, 1.0);
      final distance = math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2);
      if (distance < closest) {
        closest = distance.toDouble();
        along = cumulative[i - 1] + t * (cumulative[i] - cumulative[i - 1]);
      }
    }
    return along;
  }

  return (project(turn) - project(driver)) / 1000;
}
