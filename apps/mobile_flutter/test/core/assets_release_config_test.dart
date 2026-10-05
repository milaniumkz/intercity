import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release assets do not include design-board screenshots', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec.contains('assets/design-boards/'), isFalse);
    expect(pubspec.contains('assets/branding/'), isTrue);
  });

  test('production routes do not expose legacy preview entry points', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      expect(source.contains('preview=1'), isFalse, reason: file.path);
      expect(source.contains('legacy_'), isFalse, reason: file.path);
      expect(source.contains('previewStep'), isFalse, reason: file.path);
    }
  });

}
