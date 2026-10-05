import 'package:flutter/services.dart';

String normalizeKzPhone(String input) {
  final raw = input.trimLeft();
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';

  var value = digits;
  if (raw.startsWith('+')) {
    if (value.startsWith('777')) {
      value = '7${value.substring(2)}';
    } else if (value.startsWith('8')) {
      value = '7${value.substring(1)}';
    } else if (!value.startsWith('7')) {
      value = '7$value';
    }
  } else {
    if (value.startsWith('8')) {
      value = '7${value.substring(1)}';
    } else if (!value.startsWith('7') || value.length <= 10) {
      value = '7$value';
    }
  }
  if (value.length > 11) {
    value = value.substring(0, 11);
  }
  return '+$value';
}

String formatKzPhone(String input) {
  final hasExplicitPlus = input.trimLeft().startsWith('+');
  final rawDigits = input.replaceAll(RegExp(r'\D'), '');
  if (rawDigits.isEmpty) {
    return hasExplicitPlus ? '+' : '';
  }

  final normalized = normalizeKzPhone(input);
  final digits = normalized.replaceAll(RegExp(r'\D'), ''); // 7XXXXXXXXXX

  final b = StringBuffer('+7');
  final local = digits.length > 1 ? digits.substring(1) : '';

  if (local.isEmpty) return b.toString();
  b.write(' (');
  b.write(local.substring(0, local.length.clamp(0, 3)));
  if (local.length < 3) return b.toString();

  b.write(')');
  if (local.length == 3) return b.toString();

  b.write(' ');
  b.write(local.substring(3, local.length.clamp(3, 6)));
  if (local.length <= 6) return b.toString();

  b.write('-');
  b.write(local.substring(6, local.length.clamp(6, 8)));
  if (local.length <= 8) return b.toString();

  b.write('-');
  b.write(local.substring(8, local.length.clamp(8, 10)));
  return b.toString();
}

bool isValidKzPhone(String input) =>
    RegExp(r'^\+7\d{10}$').hasMatch(normalizeKzPhone(input));

String formatKzLocalPhone(String input) {
  var local = input.replaceAll(RegExp(r'\D'), '');
  if (local.startsWith('77') && local.length > 10) {
    local = local.substring(1);
  } else if (local.startsWith('7') && local.length > 10) {
    local = local.substring(1);
  } else if (local.startsWith('8') && local.length > 10) {
    local = local.substring(1);
  }
  if (local.length > 10) local = local.substring(0, 10);
  if (local.isEmpty) return '';

  final b = StringBuffer();
  b.write('(');
  b.write(local.substring(0, local.length.clamp(0, 3)));
  if (local.length < 3) return b.toString();

  b.write(')');
  if (local.length == 3) return b.toString();

  b.write(' ');
  b.write(local.substring(3, local.length.clamp(3, 6)));
  if (local.length <= 6) return b.toString();

  b.write('-');
  b.write(local.substring(6, local.length.clamp(6, 8)));
  if (local.length <= 8) return b.toString();

  b.write('-');
  b.write(local.substring(8, local.length.clamp(8, 10)));
  return b.toString();
}

String normalizeKzLocalPhone(String input) {
  var digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';

  if (digits.length >= 11 &&
      (digits.startsWith('7') || digits.startsWith('8'))) {
    digits = digits.substring(1);
  }
  if (digits.length > 10) {
    digits = digits.substring(digits.length - 10);
  }
  return '+7$digits';
}

class KzPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newDigits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (newDigits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final isDeleting = newValue.text.length < oldValue.text.length;
    final onlyCountryCodeLeft = newDigits == '7';
    if (isDeleting && onlyCountryCodeLeft) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final formatted = formatKzPhone(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class KzLocalPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatKzLocalPhone(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
