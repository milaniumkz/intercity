import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:intercity_mobile/features/driver/utils/pickup_departure_tracker.dart';

void main() {
  final time = DateTime.utc(2026, 10, 9);
  const pickup = LatLng(49.95, 82.6);
  void fix(PickupDepartureTracker tracker, double lat,
          {String id = 'ride',
          bool arrived = true,
          double accuracy = 5,
          double speed = 0,
          int seconds = 0,
          int age = 0}) =>
      tracker.update(
          id: id,
          arrived: arrived,
          pickup: pickup,
          point: LatLng(lat, 82.6),
          accuracy: accuracy,
          speed: speed,
          timestamp: time.add(Duration(seconds: seconds)),
          now: time.add(Duration(seconds: seconds + age)));

  test('standing and small GPS jitter do not start the trip', () {
    final tracker = PickupDepartureTracker();
    fix(tracker, 49.95);
    fix(tracker, 49.95005, seconds: 5);
    fix(tracker, 49.95, seconds: 15);
    expect(tracker.departed, isFalse);
  });
  test('driving away after arrival confirms departure, new order resets it',
      () {
    final tracker = PickupDepartureTracker();
    fix(tracker, 49.95);
    fix(tracker, 49.9503, seconds: 5, speed: 3);
    expect(tracker.departed, isTrue);
    fix(tracker, 49.95, id: 'other', seconds: 10);
    expect(tracker.departed, isFalse);
    fix(tracker, 49.9503, id: 'other', arrived: false, seconds: 15, speed: 3);
    expect(tracker.departed, isFalse);
  });
  test('two outward fixes confirm browser movement when speed is unavailable',
      () {
    final tracker = PickupDepartureTracker();
    fix(tracker, 49.95);
    fix(tracker, 49.9503, seconds: 5);
    expect(tracker.departed, isFalse);
    fix(tracker, 49.9504, seconds: 8);
    expect(tracker.departed, isTrue);
  });
  test('inaccurate or stale GPS and arrival away from pickup do not start', () {
    final tracker = PickupDepartureTracker();
    fix(tracker, 49.95);
    fix(tracker, 49.9503, seconds: 5, speed: 3, accuracy: 100);
    fix(tracker, 49.9503, seconds: 5, speed: 3, age: 60);
    expect(tracker.departed, isFalse);
    final remote = PickupDepartureTracker();
    fix(remote, 49.96, speed: 3);
    fix(remote, 49.961, seconds: 5, speed: 3);
    expect(remote.departed, isFalse);
  });
}
