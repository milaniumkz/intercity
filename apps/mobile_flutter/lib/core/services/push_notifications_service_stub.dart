import 'dart:async';

class PushNotificationsService {
  PushNotificationsService._();

  static final PushNotificationsService instance = PushNotificationsService._();

  Stream<Map<String, dynamic>> get onNotificationPayload =>
      const Stream<Map<String, dynamic>>.empty();

  Future<void> init() async {}

  Future<void> enableDriverNotifications() async {}

  Future<void> syncTokenIfAuthorized() async {}

  Future<void> showDriverOfferNotification({
    required String orderId,
    required String fromAddress,
    required String toAddress,
    int? secondsLeft,
    int? notificationId,
  }) async {}

  Future<void> showOrderStatusNotification({
    required String orderId,
    required String title,
    required String body,
    int? notificationId,
  }) async {}
}
