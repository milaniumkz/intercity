import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/utils/location_display.dart';

void main() {
  group('formatLocationDisplay', () {
    test('prefers manual address over all other fields', () {
      final item = <String, dynamic>{
        'fromManualAddress': 'QA_TEST_Алматы, вокзал 1',
        'fromAddressLabel': 'Улица Абая, 10',
        'fromAddress': '43.2, 76.8',
      };

      expect(
        formatLocationDisplay(item, isFrom: true),
        'QA_TEST_Алматы, вокзал 1',
      );
    });

    test('uses readable label and ignores coordinate-looking text', () {
      final item = <String, dynamic>{
        'toAddressLabel': 'Риддер, ул. Гоголя, 15',
        'toAddress': '49.9901, 82.6145',
        'toLat': 49.9901,
        'toLng': 82.6145,
      };

      expect(
        formatLocationDisplay(item, isFrom: false),
        'Риддер, ул. Гоголя, 15',
      );
    });

    test('falls back to coordinates only as the last resort', () {
      final item = <String, dynamic>{
        'fromAddress': '43.238949, 76.889709',
        'fromLat': 43.238949,
        'fromLng': 76.889709,
      };

      expect(
        formatLocationDisplay(item, isFrom: true),
        'Координаты: 43.23895, 76.88971',
      );
    });
  });

  group('hasUnconfirmedLocation', () {
    test('returns true for explicit request-level flag', () {
      expect(
        hasUnconfirmedLocation({'hasUnconfirmedLocation': true}, isFrom: true),
        isTrue,
      );
    });

    test('returns true for manual source on one side', () {
      expect(
        hasUnconfirmedLocation(
          {'toAddressSource': 'MANUAL'},
          isFrom: false,
        ),
        isTrue,
      );
    });
  });
}
