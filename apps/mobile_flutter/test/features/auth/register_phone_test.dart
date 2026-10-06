import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/utils/phone_input_formatter.dart';
import 'package:intercity_mobile/features/auth/screens/register_screen.dart';

void main() {
  for (final role in ['passenger', 'driver']) {
    testWidgets('$role registration formats and validates the phone number',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: RegisterScreen(role: role)),
      );
      await tester.pumpAndSettle();

      final phoneField = find.ancestor(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.keyboardType == TextInputType.phone,
        ),
        matching: find.byType(TextFormField),
      );
      await tester.ensureVisible(phoneField);
      await tester.enterText(phoneField, '7771234567');
      await tester.pump();

      final field = tester.widget<TextFormField>(phoneField);
      final textField = tester.widget<TextField>(
        find.descendant(of: phoneField, matching: find.byType(TextField)),
      );
      expect(textField.decoration?.prefixText, '+7 ');
      expect(field.controller!.text, '(777) 123-45-67');
      expect(field.validator!(field.controller!.text), isNull);
      expect(normalizeKzLocalPhone(field.controller!.text), '+77771234567');

      await tester.enterText(phoneField, '+7 (778) 123-45-67');
      await tester.pump();
      expect(field.controller!.text, '(778) 123-45-67');
      expect(field.validator!(field.controller!.text), isNull);
      expect(normalizeKzLocalPhone(field.controller!.text), '+77781234567');

      await tester.enterText(phoneField, '777123');
      await tester.pump();
      expect(field.validator!(field.controller!.text), isNotNull);
    });
  }
}
