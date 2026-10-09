Map<String, dynamic> normalizeDriverOffer(
  Map<String, dynamic> order, {
  DateTime? now,
}) {
  final normalized = Map<String, dynamic>.from(order);
  // Keep the server deadline for identity, but count down from its remaining
  // duration so a wrong device clock cannot hide a valid offer.
  if (_parseOfferExpiresAt(normalized['offerCountdownUntil']) != null) {
    return normalized;
  }
  final secondsLeft =
      _parseOfferExpiresInSeconds(normalized['offerExpiresInSec']);
  if (secondsLeft != null) {
    normalized['offerCountdownUntil'] = (now ?? DateTime.now())
        .add(Duration(seconds: secondsLeft.clamp(0, 3600)))
        .toIso8601String();
    normalized['offerExpiresAt'] ??= normalized['offerCountdownUntil'];
  }

  return normalized;
}

int offerSecondsLeft(
  Map<String, dynamic> order, {
  DateTime? now,
  int fallbackSeconds = 30,
}) {
  final expiresAt = _parseOfferExpiresAt(order['offerCountdownUntil']) ??
      _parseOfferExpiresAt(order['offerExpiresAt']);
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

String driverOfferIdentity(Map<String, dynamic> order) =>
    '${order['id'] ?? ''}:${order['offerExpiresAt'] ?? order['dispatchExpiresAt'] ?? ''}';
