import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/utils/localization_service.dart';

void main() {
  test('defaults to russian when no stored language exists', () {
    expect(
      LocalizationService.resolveInitialLanguage(storedLanguage: null),
      AppLanguage.russian,
    );
  });

  test('migrates legacy stored kazakh to russian by default', () {
    expect(
      LocalizationService.resolveInitialLanguage(
        storedLanguage: AppLanguage.kazakh.name,
      ),
      AppLanguage.russian,
    );
  });

  test('keeps kazakh only when it is explicitly selected in new storage', () {
    expect(
      LocalizationService.resolveInitialLanguage(
        storedLanguage: AppLanguage.kazakh.name,
        hasExplicitSelection: true,
      ),
      AppLanguage.kazakh,
    );
  });
}
