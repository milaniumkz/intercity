import 'driver_offer_sound.dart';

/// The same transition may arrive through FCM, SSE and polling.
class TripStatusSound {
  static final Set<String> _played = {};
  static Future<void> prepare() => DriverOfferSound.prepare();
  static Future<void> playOnce(String tripId, String status) async {
    final canonical = status == 'DRIVER_EN_ROUTE' ? 'DRIVER_ASSIGNED' : status;
    if (!_played.add('$tripId:$canonical')) return;
    if (_played.length > 200) _played.remove(_played.first);
    await DriverOfferSound.play();
  }
}
