import 'browser_location_model.dart';

bool isReliableCurrentLocation(BrowserLocation location, {DateTime? now}) {
  if (!location.latitude.isFinite ||
      !location.longitude.isFinite ||
      location.latitude.abs() > 90 ||
      location.longitude.abs() > 180 ||
      !location.accuracy.isFinite ||
      location.accuracy <= 0 ||
      location.accuracy > 50) {
    return false;
  }
  final timestamp = location.timestamp;
  if (timestamp == null) return true;
  final age = (now ?? DateTime.now()).difference(timestamp);
  return age >= const Duration(seconds: -30) &&
      age <= const Duration(minutes: 2);
}
