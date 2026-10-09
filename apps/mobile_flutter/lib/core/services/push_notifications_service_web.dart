import 'dart:async';
import 'dart:js_interop';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:web/web.dart' as web;

import '../api/api_client.dart';
import 'push_notification_payloads.dart';
import 'push_notifications_startup_policy.dart';

class PushNotificationsService {
  PushNotificationsService._();

  static final PushNotificationsService instance = PushNotificationsService._();

  static const String _webVapidKey = String.fromEnvironment(
    'INTERCITY_FIREBASE_WEB_VAPID_KEY',
    defaultValue: '',
  );

  final StreamController<Map<String, dynamic>> _payloadStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final Map<String, web.Notification> _activeNotifications =
      <String, web.Notification>{};

  bool _initialized = false;
  bool _firebaseReady = false;

  Stream<Map<String, dynamic>> get onNotificationPayload =>
      _payloadStreamController.stream;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _registerMessagingServiceWorker();

    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyBx5o8anmvNDDubNHjEEVKWLRxddM-BERE',
          appId: '1:176647550231:web:6e778252e634289c6d7352',
          messagingSenderId: '176647550231',
          projectId: 'inter-city-pkzpps',
          authDomain: 'inter-city-pkzpps.firebaseapp.com',
          storageBucket: 'inter-city-pkzpps.firebasestorage.app',
        ),
      );
      _firebaseReady = true;
    } catch (_) {
      _firebaseReady = false;
    }

    _bindServiceWorkerClicks();

    if (_firebaseReady) {
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      if (shouldSyncPushTokenOnStartup(
        firebaseReady: _firebaseReady,
        notificationPermission: web.Notification.permission,
      )) {
        await syncTokenIfAuthorized();
      }
    }
  }

  Future<void> enableDriverNotifications() async {
    await _requestPermissionIfNeeded();
    await syncTokenIfAuthorized();
  }

  Future<void> syncTokenIfAuthorized() async {
    if (!_firebaseReady || !_isPermissionGranted) return;
    try {
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: _webVapidKey.isEmpty ? null : _webVapidKey,
      );
      if (token != null && token.isNotEmpty) {
        await _sendTokenToBackend(token);
      }
    } catch (_) {
      // Browser notifications should keep working even if FCM token sync fails.
    }
  }

  Future<void> showDriverOfferNotification({
    required String orderId,
    required String fromAddress,
    required String toAddress,
    int? secondsLeft,
    int? notificationId,
  }) async {
    if (!_isPermissionGranted) {
      await _requestPermissionIfNeeded();
    }
    if (!_isPermissionGranted) return;

    final payload = buildDriverOfferPayload(orderId: orderId);
    final tag = 'driver-offer-${notificationId ?? orderId.hashCode}';
    _activeNotifications.remove(tag)?.close();

    // Android Chrome requires service-worker notifications (the constructor
    // is unavailable there). This also keeps taps working after closing a tab.
    try {
      final registration = await web.window.navigator.serviceWorker.ready.toDart
          .timeout(const Duration(seconds: 2));
      await registration
          .showNotification(
              'Новый заказ',
              web.NotificationOptions(
                body: buildDriverOfferNotificationBody(
                    fromAddress: fromAddress,
                    toAddress: toAddress,
                    secondsLeft: secondsLeft),
                icon: '/icons/Icon-192.png',
                tag: tag,
                renotify: true,
                requireInteraction: true,
                data: payload.jsify(),
              ))
          .toDart;
      return;
    } catch (_) {}

    final notification = web.Notification(
      'Новый заказ',
      web.NotificationOptions(
        body: buildDriverOfferNotificationBody(
          fromAddress: fromAddress,
          toAddress: toAddress,
          secondsLeft: secondsLeft,
        ),
        icon: 'icons/Icon-192.png',
        badge: 'icons/Icon-maskable-192.png',
        tag: tag,
        renotify: true,
        requireInteraction: true,
      ),
    );
    _activeNotifications[tag] = notification;
    notification.onclick = ((web.Event _) {
      notification.close();
      _activeNotifications.remove(tag);
      _focusCurrentWindow();
      _payloadStreamController.add(payload);
    }).toJS;
    notification.onclose = ((web.Event _) {
      _activeNotifications.remove(tag);
    }).toJS;
  }

  Future<void> showOrderStatusNotification({
    required String orderId,
    required String title,
    required String body,
    int? notificationId,
  }) async {
    if (!_isPermissionGranted) {
      await _requestPermissionIfNeeded();
    }
    if (!_isPermissionGranted) return;

    final tag = 'order-status-${notificationId ?? Object.hash(orderId, title)}';
    _activeNotifications.remove(tag)?.close();
    final notification = web.Notification(
      title,
      web.NotificationOptions(
        body: body,
        icon: 'icons/Icon-192.png',
        badge: 'icons/Icon-maskable-192.png',
        tag: tag,
        renotify: true,
        requireInteraction: false,
      ),
    );
    _activeNotifications[tag] = notification;
    notification.onclick = ((web.Event _) {
      notification.close();
      _activeNotifications.remove(tag);
      _focusCurrentWindow();
      _payloadStreamController.add({
        'type': 'order_status',
        'orderId': orderId,
      });
    }).toJS;
    notification.onclose = ((web.Event _) {
      _activeNotifications.remove(tag);
    }).toJS;
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    _payloadStreamController.add(Map<String, dynamic>.from(message.data));
    final notification = message.notification;
    if (notification == null) return;
    if (!_isPermissionGranted) return;

    final payload = <String, dynamic>{
      ...message.data,
      'route': message.data['route']?.toString() ?? '/profile',
    };
    final tag = 'remote-${message.messageId ?? notification.hashCode}';
    _activeNotifications.remove(tag)?.close();

    final browserNotification = web.Notification(
      notification.title ?? 'INTERCITY',
      web.NotificationOptions(
        body: notification.body ?? '',
        icon: notification.apple?.imageUrl ??
            notification.android?.imageUrl ??
            notification.web?.image ??
            'icons/Icon-192.png',
        badge: 'icons/Icon-maskable-192.png',
        tag: tag,
      ),
    );

    _activeNotifications[tag] = browserNotification;
    browserNotification.onclick = ((web.Event _) {
      browserNotification.close();
      _activeNotifications.remove(tag);
      _focusCurrentWindow();
      _payloadStreamController.add(payload);
    }).toJS;
    browserNotification.onclose = ((web.Event _) {
      _activeNotifications.remove(tag);
    }).toJS;
  }

  void _bindServiceWorkerClicks() {
    final serviceWorker = web.window.navigator.serviceWorker;

    serviceWorker.addEventListener(
      'message',
      ((web.Event event) {
        final messageEvent = event as web.MessageEvent;
        final data = messageEvent.data.dartify();
        if (data is! Map) return;
        final type = data['type']?.toString() ?? '';
        if (type != 'notification-click') return;
        final payload = data['payload'];
        if (payload is Map<String, dynamic>) {
          _payloadStreamController.add(payload);
          return;
        }
        if (payload is Map) {
          _payloadStreamController.add(Map<String, dynamic>.from(payload));
        }
      }).toJS,
    );
  }

  Future<void> _registerMessagingServiceWorker() async {
    final serviceWorker = web.window.navigator.serviceWorker;
    try {
      await serviceWorker
          .register('firebase-messaging-sw.js'.toJS)
          .toDart
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Ignore: app can still use foreground notifications without SW.
    }
  }

  Future<void> _requestPermissionIfNeeded() async {
    if (_isPermissionGranted || web.Notification.permission == 'denied') return;
    try {
      await web.Notification.requestPermission()
          .toDart
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Ignore blocked/unsupported permission requests.
    }
  }

  bool get _isPermissionGranted => web.Notification.permission == 'granted';

  void _focusCurrentWindow() {
    try {
      web.window.focus();
    } catch (_) {
      // Ignore browsers that block focus() without direct user gesture.
    }
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      final accessToken = await ApiClient().getAccessToken();
      if (accessToken == null || accessToken.isEmpty) return;
      await ApiClient().post(
        '/auth/push-token',
        data: <String, dynamic>{
          'token': token,
          'platform': 'WEB',
        },
      );
    } catch (_) {
      // Keep notifications functional even if backend token sync fails.
    }
  }
}
