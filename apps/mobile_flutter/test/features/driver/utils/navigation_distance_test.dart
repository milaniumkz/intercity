import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:intercity_mobile/features/driver/utils/navigation_distance.dart';
import 'package:intercity_mobile/features/driver/widgets/navigation_instruction.dart';

void main() {
  test('turn distance follows curved road rather than air distance', () {
    final route = [
      const LatLng(0, 0),
      const LatLng(.01, 0),
      const LatLng(.01, .01)
    ];
    final road = navigationRoadDistance(route, route.first, route.last)!;
    expect(road, closeTo(2.22, .02));
    expect(
        road,
        greaterThan(const Distance()
            .as(LengthUnit.Kilometer, route.first, route.last)));
    expect(navigationRoadDistance(route, route.last, route.first), lessThan(0));
  });
  test('Russian and Kazakh instructions use requested thresholds and arrival',
      () {
    final left = {
      'maneuver': {'type': 'turn', 'modifier': 'left'}
    };
    expect(navigationSpeech(left, 300, false),
        'Через 300 метров поверните налево');
    expect(navigationSpeech(left, 100, false),
        'Через 100 метров поверните налево');
    expect(navigationSpeech(left, 50, false), 'Поверните налево');
    expect(
        navigationSpeech(left, 100, true), '100 метрден кейін солға бұрылыңыз');
    expect(
        navigationSpeech({
          'maneuver': {'type': 'arrive'}
        }, 0, true),
        'Сіз келдіңіз');
  });
}
