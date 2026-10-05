import 'dart:convert';

Map<String, dynamic> buildDriverOfferPayload({
  required String orderId,
}) {
  return <String, dynamic>{
    'type': 'driver_offer',
    'orderId': orderId,
    'route': '/driver/home',
  };
}

String buildDriverOfferNotificationBody({
  required String fromAddress,
  required String toAddress,
  int? secondsLeft,
}) {
  final sec = (secondsLeft ?? 30).clamp(1, 3600);
  return '$fromAddress -> $toAddress • $sec сек на принятие';
}

String encodePushPayload(Map<String, dynamic> payload) {
  return jsonEncode(payload);
}

Map<String, dynamic>? decodePushPayload(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  try {
    final parsed = jsonDecode(text);
    if (parsed is Map<String, dynamic>) {
      return parsed;
    }
    if (parsed is Map) {
      return Map<String, dynamic>.from(parsed);
    }
  } catch (_) {
    return null;
  }
  return null;
}
