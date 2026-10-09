import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/services/navigation_voice_catalog.dart';
import 'package:intercity_mobile/features/driver/widgets/navigation_instruction.dart';

void main() {
  test(
      'each navigation instruction has a bundled female recording in both languages',
      () {
    for (final kazakh in [false, true]) {
      for (final modifier in ['left', 'right', 'uturn', 'straight']) {
        final step = {
          'maneuver': {'type': 'turn', 'modifier': modifier}
        };
        for (final distance in [300, 100, 50]) {
          expect(
              navigationVoiceRecordings
                  .containsKey(navigationSpeech(step, distance, kazakh)),
              isTrue);
        }
      }
      for (final distance in [300, 100, 50]) {
        expect(
            navigationVoiceRecordings.containsKey(navigationSpeech({
              'maneuver': {'type': 'roundabout'}
            }, distance, kazakh)),
            isTrue);
      }
      expect(
          navigationVoiceRecordings.containsKey(navigationSpeech({
            'maneuver': {'type': 'arrive'}
          }, 0, kazakh)),
          isTrue);
    }
    final manifest = jsonDecode(
        File('web/navigation-voice/manifest.json').readAsStringSync()) as List;
    expect(manifest.length, 34);
    for (final text in [
      'Не удалось списать оплату с карты. Способ оплаты переведён на наличные.',
      'Картадан төлем алынбады. Төлем әдісі қолма-қол ақшаға ауыстырылды.'
    ]) {
      expect(navigationVoiceRecordings.containsKey(text), isTrue);
    }
    for (final row in manifest) {
      expect(
          row['voice'],
          row['language'] == 'ru'
              ? 'ru-RU-SvetlanaNeural'
              : 'kk-KZ-AigulNeural');
      expect(File('web/navigation-voice/${row['file']}').lengthSync(),
          greaterThan(1000));
    }
  });
}
