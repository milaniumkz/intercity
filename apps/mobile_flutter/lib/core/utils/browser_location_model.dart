class BrowserLocation {
  const BrowserLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime? timestamp;
}
