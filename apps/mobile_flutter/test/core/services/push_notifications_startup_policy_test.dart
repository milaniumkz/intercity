import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/services/push_notifications_startup_policy.dart';

void main() {
  group('push notification startup policy', () {
    test('does not prompt for browser permission during app startup', () {
      expect(shouldPromptForPushPermissionAtStartup(), isFalse);
    });

    test('syncs push token only when firebase is ready and permission granted',
        () {
      expect(
        shouldSyncPushTokenOnStartup(
          firebaseReady: true,
          notificationPermission: 'granted',
        ),
        isTrue,
      );
      expect(
        shouldSyncPushTokenOnStartup(
          firebaseReady: true,
          notificationPermission: 'default',
        ),
        isFalse,
      );
      expect(
        shouldSyncPushTokenOnStartup(
          firebaseReady: true,
          notificationPermission: 'denied',
        ),
        isFalse,
      );
      expect(
        shouldSyncPushTokenOnStartup(
          firebaseReady: false,
          notificationPermission: 'granted',
        ),
        isFalse,
      );
    });
  });
}
