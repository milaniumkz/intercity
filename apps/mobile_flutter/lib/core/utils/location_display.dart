String formatLocationDisplay(
  Map<String, dynamic> item, {
  required bool isFrom,
}) {
  final prefix = isFrom ? 'from' : 'to';
  final manualAddress = _asNonCoordinateText(item['${prefix}ManualAddress']);
  if (manualAddress != null) return manualAddress;

  final addressLabel = _asNonCoordinateText(item['${prefix}AddressLabel']);
  if (addressLabel != null) return addressLabel;

  final genericAddress = _asNonCoordinateText(item['${prefix}Address']);
  if (genericAddress != null) return genericAddress;

  final cityFallback = _asNonCoordinateText(item['${prefix}City']);
  if (cityFallback != null) return cityFallback;

  final lat = _asDouble(item['${prefix}Lat']);
  final lng = _asDouble(item['${prefix}Lng']);
  if (lat != null && lng != null) {
    return 'Координаты: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  return isFrom ? 'Адрес подачи уточняется' : 'Адрес назначения уточняется';
}

bool hasUnconfirmedLocation(
  Map<String, dynamic> item, {
  required bool isFrom,
}) {
  if (item['hasUnconfirmedLocation'] == true) return true;
  final prefix = isFrom ? 'from' : 'to';
  final source =
      (item['${prefix}AddressSource'] ?? '').toString().trim().toUpperCase();
  if (source == 'MANUAL') return true;
  final lat = _asDouble(item['${prefix}Lat']);
  final lng = _asDouble(item['${prefix}Lng']);
  return lat == null || lng == null;
}

String? _asNonCoordinateText(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  if (_looksLikeCoordinates(text)) return null;
  return text;
}

bool _looksLikeCoordinates(String value) {
  return RegExp(r'^-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?$')
      .hasMatch(value.trim());
}

double? _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value == null) return null;
  return double.tryParse(value.toString());
}
