import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/features/driver/utils/driver_offer_utils.dart';

void main() {
  group('driver offer utils', () {
    test('re-offering the same order starts a new notification identity', () {
      expect(
          driverOfferIdentity(
              {'id': 'one', 'offerExpiresAt': '2026-10-09T12:00:00Z'}),
          isNot(driverOfferIdentity(
              {'id': 'one', 'offerExpiresAt': '2026-10-09T12:01:00Z'})));
    });
    test('counts down from absolute expiry time instead of static seconds', () {
      final now = DateTime.utc(2026, 5, 4, 10, 0, 0);
      final order = <String, dynamic>{
        'offerExpiresInSec': 30,
        'offerExpiresAt':
            now.add(const Duration(seconds: 12)).toIso8601String(),
      };

      expect(
        offerSecondsLeft(order, now: now.add(const Duration(seconds: 5))),
        7,
      );
    });

    test('backfills absolute expiry time when backend only sends seconds', () {
      final now = DateTime.utc(2026, 5, 4, 10, 0, 0);
      final normalized = normalizeDriverOffer(
        <String, dynamic>{'offerExpiresInSec': 18},
        now: now,
      );

      expect(normalized['offerExpiresAt'], isNotNull);
      expect(
        offerSecondsLeft(normalized, now: now.add(const Duration(seconds: 6))),
        12,
      );
    });

    test('builds russian voice alert for incoming order', () {
      final now = DateTime.utc(2026, 5, 4, 10, 0, 0);
      final speech = buildDriverOfferAlertSpeech(
        <String, dynamic>{
          'fromAddress': 'Абая 10',
          'toAddress': 'Сейфуллина 45',
          'offerExpiresAt':
              now.add(const Duration(seconds: 21)).toIso8601String(),
        },
        now: now,
      );

      expect(speech, contains('Новый заказ'));
      expect(speech, contains('Абая 10'));
      expect(speech, contains('Сейфуллина 45'));
      expect(speech, contains('21 секунд'));
    });
  });
}
