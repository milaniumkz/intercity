/// Currency belongs to the departure city; monetary amounts are not converted.
String rideCurrencyCode(Map? data) {
  final code = data?['currency']?.toString().toUpperCase();
  if (code == 'RUB' || code == 'KZT') return code!;
  final city = data?['city'];
  final country =
      data?['countryCode'] ?? (city is Map ? city['countryCode'] : null);
  return country?.toString().toUpperCase() == 'RU' ? 'RUB' : 'KZT';
}

String rideCurrencySymbol(Map? data) =>
    rideCurrencyCode(data) == 'RUB' ? '₽' : '₸';

/// Wallet balances retain cents; ride price rounding must not alter balances.
String formatWalletAmount(Object? value) {
  final amount = value is num ? value : num.tryParse('$value') ?? 0;
  if (!amount.isFinite) return '0';
  final fixed = amount.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  final parts = fixed.split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]} ',
  );
  return parts.length == 1 ? whole : '$whole,${parts[1]}';
}
