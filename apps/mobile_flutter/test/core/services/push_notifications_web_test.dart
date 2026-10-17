@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/services/push_notifications_service_web.dart';

void main() {
  test(
      'iPhone browser without Notification API can safely continue optional push setup',
      () async {
    final original = globalContext.getProperty<JSAny?>('Notification'.toJS);
    globalContext.setProperty('Notification'.toJS, null);
    try {
      await PushNotificationsService.instance.enableDriverNotifications();
      await PushNotificationsService.instance.syncTokenIfAuthorized();
    } finally {
      globalContext.setProperty('Notification'.toJS, original);
    }
  });
}
