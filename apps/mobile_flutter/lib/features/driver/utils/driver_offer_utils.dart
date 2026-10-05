Map<String, dynamic> normalizeDriverOffer(
  Map<String, dynamic> order, {
  DateTime? now,
}) {
  final normalized = Map<String, dynamic>.from(order);
  final expiresAt = _parseOfferExpiresAt(normalized['offerExpiresAt']);
  if (expiresAt != null) {
    return normalized;
  }

  final secondsLeft =
      _parseOfferExpiresInSeconds(normalized['offerExpiresInSec']);
  if (secondsLeft == null) {
    return normalized;
  }

  normalized['offerExpiresAt'] = (now ?? DateTime.now())
      .add(Duration(seconds: secondsLeft))
      .toIso8601String();
  return normalized;
}

int offerSecondsLeft(
  Map<String, dynamic> order, {
  DateTime? now,
  int fallbackSeconds = 30,
}) {
  final expiresAt = _parseOfferExpiresAt(order['offerExpiresAt']);
  if (expiresAt != null) {
    final secondsLeft = expiresAt.difference(now ?? DateTime.now()).inSeconds;
    return secondsLeft.clamp(0, 3600).toInt();
  }

  final secondsLeft = _parseOfferExpiresInSeconds(order['offerExpiresInSec']);
  if (secondsLeft != null) {
    return secondsLeft.clamp(0, 3600).toInt();
  }

  return fallbackSeconds.clamp(0, 3600).toInt();
}

String? buildDriverOfferAlertSpeech(
  Map<String, dynamic> order, {
  DateTime? now,
}) {
  final secondsLeft = offerSecondsLeft(order, now: now);
  if (secondsLeft <= 0) return null;

  final fromAddress = _normalizeAddress(
    order['fromAddress'],
    fallback: 'точка подачи',
  );
  final toAddress = _normalizeAddress(
    order['toAddress'],
    fallback: 'точка назначения',
  );

  return 'Новый заказ. Откуда: $fromAddress. Куда: $toAddress. '
      'На принятие осталось $secondsLeft секунд.';
}

DateTime? _parseOfferExpiresAt(dynamic raw) {
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

int? _parseOfferExpiresInSeconds(dynamic raw) {
  if (raw is num) {
    return raw.toInt();
  }
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return int.tryParse(text);
}

String _normalizeAddress(dynamic raw, {required String fallback}) {
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return fallback;
  return text;
}
