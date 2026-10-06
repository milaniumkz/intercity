import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/utils/phone_input_formatter.dart';

void main() {
  group('formatKzPhone', () {
    test('keeps a single explicit plus while the user starts typing', () {
      expect(formatKzPhone('+'), '+');
    });

    test('does not duplicate country code for explicit +7 input', () {
      expect(formatKzPhone('+77015151501'), '+7 (701) 515-15-01');
      expect(formatKzPhone('+7 +77015151501'), '+7 (701) 515-15-01');
      expect(normalizeKzPhone('+77015151501'), '+77015151501');
      expect(normalizeKzPhone('+7 +77015151501'), '+77015151501');
    });

    test('formats local input into Kazakhstan phone format', () {
      expect(formatKzPhone('7015151501'), '+7 (701) 515-15-01');
      expect(normalizeKzPhone('7015151501'), '+77015151501');
    });

    test('does not create trailing mask separators', () {
      expect(formatKzPhone('+7701'), '+7 (701)');
      expect(formatKzPhone('+7701515'), '+7 (701) 515');
      expect(formatKzPhone('+770151515'), '+7 (701) 515-15');
    });
  });

  group('isValidKzPhone', () {
    test('accepts fully formatted Kazakhstan number', () {
      expect(isValidKzPhone('+7 (701) 515-15-01'), isTrue);
    });

    test('preserves valid numbers starting with plus seven seven seven', () {
      for (final phone in ['+77771234567', '+77781234567', '+77761234567']) {
        expect(normalizeKzPhone(phone), phone);
        expect(isValidKzPhone(phone), isTrue);
        expect(isValidKzPhone(formatKzPhone(phone)), isTrue);
      }
    });

    test('rejects incomplete and overlong numbers without truncating them', () {
      for (final phone in ['', '+7', '+7777123456', '+777712345678']) {
        expect(isValidKzPhone(phone), isFalse);
        expect(isValidKzPhone(normalizeKzLocalPhone(phone)), isFalse);
      }
    });
  });

  group('KzPhoneInputFormatter', () {
    test('supports incremental typing from explicit plus prefix', () {
      final formatter = KzPhoneInputFormatter();
      var value = const TextEditingValue();

      for (final nextText in ['+', '+7', '+77', '+770', '+7701', '+77015']) {
        value = formatter.formatEditUpdate(
          value,
          TextEditingValue(text: nextText),
        );
      }

      expect(value.text, '+7 (701) 5');
    });

    test('allows clearing a formatted phone completely', () {
      final formatter = KzPhoneInputFormatter();
      var value = const TextEditingValue(text: '+7 (701) 515-15-01');

      for (final nextText in [
        '+7 (701) 515-15-0',
        '+7 (701) 515-15-',
        '+7 (701) 515-15',
        '+7 (701) 515-1',
        '+7 (701) 515-',
        '+7 (701) 515',
        '+7 (701) 51',
        '+7 (701) 5',
        '+7 (701)',
        '+7 (70',
        '+7 (7',
        '+7',
        '+',
        '',
      ]) {
        value = formatter.formatEditUpdate(
          value,
          TextEditingValue(text: nextText),
        );
      }

      expect(value.text, isEmpty);
      expect(value.selection.baseOffset, 0);
    });

    test('collapses duplicated plus seven pasted into existing prefix', () {
      final formatter = KzPhoneInputFormatter();
      final value = formatter.formatEditUpdate(
        const TextEditingValue(text: '+7'),
        const TextEditingValue(text: '+7+77015151501'),
      );

      expect(value.text, '+7 (701) 515-15-01');
      expect(value.text.contains('+7+7'), isFalse);
    });
  });

  group('KzLocalPhoneInputFormatter', () {
    test('formats a local number incrementally and preserves all digits', () {
      final formatter = KzLocalPhoneInputFormatter();
      var value = const TextEditingValue();
      for (final digit in '7771234567'.split('')) {
        value = formatter.formatEditUpdate(
          value,
          TextEditingValue(text: '${value.text}$digit'),
        );
      }
      expect(value.text, '(777) 123-45-67');
      expect(normalizeKzLocalPhone(value.text), '+77771234567');
      expect(isValidKzPhone(normalizeKzLocalPhone(value.text)), isTrue);
    });

    test('accepts pasted local, international and trunk-prefix numbers', () {
      final formatter = KzLocalPhoneInputFormatter();
      for (final phone in [
        '7771234567',
        '+77771234567',
        '+7 (777) 123-45-67',
        '87771234567',
      ]) {
        final value = formatter.formatEditUpdate(
          const TextEditingValue(),
          TextEditingValue(text: phone),
        );
        expect(value.text, '(777) 123-45-67');
        expect(normalizeKzLocalPhone(value.text), '+77771234567');
        expect(isValidKzPhone(normalizeKzLocalPhone(value.text)), isTrue);
      }
    });
    test('keeps country code outside editable value', () {
      final formatter = KzLocalPhoneInputFormatter();
      final value = formatter.formatEditUpdate(
        const TextEditingValue(),
        const TextEditingValue(text: '+77015151501'),
      );

      expect(value.text, '(701) 515-15-01');
      expect(normalizeKzLocalPhone(value.text), '+77015151501');
      expect(value.text.contains('+7'), isFalse);
    });
  });
}
