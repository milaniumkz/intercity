import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/services/identity_face_guide_model.dart';
import 'package:intercity_mobile/core/services/identity_error_voice.dart';
import 'package:intercity_mobile/features/auth/screens/identity_camera_frame.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('only one centered face turns green; unknown state never does', () {
    expect(facePosition(IdentityFaceSample.unavailable),
        IdentityFacePosition.unavailable);
    expect(facePosition(const IdentityFaceSample([])),
        IdentityFacePosition.missing);
    const face = Rect.fromLTWH(.35, .30, .30, .48);
    expect(facePosition(const IdentityFaceSample([face])),
        IdentityFacePosition.centered);
    expect(facePosition(const IdentityFaceSample([face, face])),
        IdentityFacePosition.multiple);
    expect(
        facePosition(
            const IdentityFaceSample([Rect.fromLTWH(.05, .3, .3, .48)])),
        IdentityFacePosition.outside);
    expect(
        facePosition(
            const IdentityFaceSample([Rect.fromLTWH(.46, .45, .08, .12)])),
        IdentityFacePosition.small);
  });
  test('guide stays a tall oval on narrow and wide screens', () {
    for (final width in [240.0, 320.0, 430.0, 800.0]) {
      final oval = identityFaceOval(Size(width, 320));
      expect(oval.height, greaterThan(oval.width * 1.4));
      expect(oval.center.dx, closeTo(width / 2, 1e-9));
      expect(oval.left, greaterThanOrEqualTo(0));
    }
  });
  test('failure reason selects a matching bundled voice clip', () async {
    final errors = {
      'В кадре должно быть только одно лицо': 'error_multiple',
      'Лицо часто пропадает из кадра или слишком далеко': 'error_position',
      'Недостаточно кадров с лицом прямо в камеру': 'error_front',
      'Не распознаны задания: моргание': 'error_blink',
      'Не распознаны задания: поднять подбородок': 'error_chin',
      'Не удалось открыть камеру': 'error_camera',
      'Восстановление не разрешено.': 'error_match',
    };
    for (final entry in errors.entries) {
      final cue = identityErrorCue(entry.key);
      expect(cue, entry.value);
      expect(
          (await rootBundle.load('assets/sounds/identity/$cue.wav'))
              .lengthInBytes,
          greaterThan(1000));
    }
  });
}
