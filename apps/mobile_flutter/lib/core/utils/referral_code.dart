/// Supports copied links (including Flutter hash routes), query links and codes.
String? normalizeReferralCode(String? raw) {
  var value = (raw ?? '').trim();
  if (value.isEmpty) return null;
  try {
    value = Uri.decodeComponent(value);
  } on FormatException {/* Validate the original text. */}
  final query = RegExp(r'[?&](?:ref|referral|referralCode)=([A-Za-z0-9]+)',
          caseSensitive: false)
      .firstMatch(value)
      ?.group(1);
  final path = RegExp(r'/ref/([A-Za-z0-9]+)', caseSensitive: false)
      .firstMatch(value)
      ?.group(1);
  final code = (query ?? path ?? value)
      .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
      .toUpperCase();
  return code.isEmpty ? null : code;
}
