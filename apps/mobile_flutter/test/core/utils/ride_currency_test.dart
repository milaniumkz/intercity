import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_shared/intercity_shared.dart';

void main() {
  test('wallet amount keeps cents and does not round to ride price steps', () {
    expect(formatWalletAmount(120), '120');
    expect(formatWalletAmount(112.5), '112,5');
    expect(formatWalletAmount(7000), '7 000');
    expect(formatWalletAmount(-12.25), '-12,25');
  });
  test('currency follows departure city metadata', () {
    expect(rideCurrencyCode({'countryCode': 'RU'}), 'RUB');
    expect(rideCurrencySymbol({'countryCode': 'RU'}), '₽');
    expect(rideCurrencySymbol({'countryCode': 'KZ'}), '₸');
    expect(
        rideCurrencySymbol({
          'city': {'countryCode': 'RU'}
        }),
        '₽');
  });

  test('saved order currency survives country changes and defaults legacy data',
      () {
    expect(
        rideCurrencySymbol({
          'currency': 'RUB',
          'city': {'countryCode': 'KZ'}
        }),
        '₽');
    expect(
        rideCurrencySymbol({
          'currency': 'KZT',
          'city': {'countryCode': 'RU'}
        }),
        '₸');
    expect(rideCurrencySymbol({}), '₸');
  });
}
