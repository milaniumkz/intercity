import 'chat_message_notices.dart';
import 'dart:async';
import 'dart:js_interop';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:web/web.dart' as web;

import '../api/api_client.dart';
import 'push_notification_payloads.dart';
import 'trip_status_sound.dart';
import 'push_notifications_startup_policy.dart';

@JS('window.intercityRequestWebPush')
external set _requestWebPush(JSFunction callback);
@JS('window.intercityWebPushStatus')
external set _webPushStatus(JSFunction callback);

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

  final Set<String> _shownTripNotices = {};
  bool _initialized = false;
  bool _firebaseReady = false;
  bool _registered = false;
  bool _foregroundBound = false;

  Stream<Map<String, dynamic>> get onNotificationPayload =>
      _payloadStreamController.stream;

  Future<void> init() async {
    _requestWebPush =
        (() => enableWebNotifications().then((v) => v.toJS).toJS).toJS;
    _webPushStatus = (() => webPushStatus().then((v) => v.jsify()!).toJS).toJS;
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
      if (!_foregroundBound) {
        _foregroundBound = true;
        FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      }
      if (shouldSyncPushTokenOnStartup(
        firebaseReady: _firebaseReady,
        notificationPermission: _notificationPermission,
      )) {
        await syncTokenIfAuthorized();
      }
    }
    web.window.dispatchEvent(web.Event('intercity-push-ready'));
  }

  Future<void> enableDriverNotifications() async {
    await _requestPermissionIfNeeded();
    await syncTokenIfAuthorized();
  }

  Future<Map<String, Object>> webPushStatus() async {
    bool signedIn = false;
    try {
      signedIn = (await ApiClient().getAccessToken())?.isNotEmpty == true;
    } catch (_) {}
    return {
      'signedIn': signedIn,
      'permission': _notificationPermission,
      'registered': signedIn && _registered && _isPermissionGranted
    };
  }

  Future<bool> enableWebNotifications() async {
    // This call must start synchronously from a click. No network/storage await
    // may precede the iOS permission request.
    final permission = _notificationPermission;
    if (permission == 'unsupported' || permission == 'denied') return false;
    try {
      if (permission != 'granted') {
        final result = await web.Notification.requestPermission().toDart;
        if (result.toDart != 'granted') return false;
      }
      if (!_firebaseReady) {
        await Firebase.initializeApp(
            options: const FirebaseOptions(
          apiKey: 'AIzaSyBx5o8anmvNDDubNHjEEVKWLRxddM-BERE',
          appId: '1:176647550231:web:6e778252e634289c6d7352',
          messagingSenderId: '176647550231',
          projectId: 'inter-city-pkzpps',
          authDomain: 'inter-city-pkzpps.firebaseapp.com',
          storageBucket: 'inter-city-pkzpps.firebasestorage.app',
        ));
        _firebaseReady = true;
        if (!_foregroundBound) {
          _foregroundBound = true;
          FirebaseMessaging.onMessage.listen(_onForegroundMessage);
        }
      }
      final token = await FirebaseMessaging.instance
          .getToken(vapidKey: _webVapidKey.isEmpty ? null : _webVapidKey);
      if (token == null || token.isEmpty) return false;
      return await _sendTokenToBackend(token);
    } catch (_) {
      return false;
    }
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

  Future<void> cancelDriverOfferNotification(String orderId) async {
    _activeNotifications.remove('driver-offer-${orderId.hashCode}')?.close();
    try {
      final registration = await web.window.navigator.serviceWorker.ready.toDart
          .timeout(const Duration(seconds: 2));
      final notifications =
          (await registration.getNotifications().toDart).toDart;
      for (final notification in notifications) {
        if (notification.tag == 'driver-offer-${orderId.hashCode}' ||
            notification.tag == 'driver-offer-$orderId') {
          notification.close();
        }
      }
    } catch (_) {}
  }

  Future<void> showDriverOfferNotification({
    required String orderId,
    required String fromAddress,
    required String toAddress,
    int? secondsLeft,
    int? notificationId,
  }) async {
    // Incoming events cannot request browser permission without a user click.
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
    Map<String, dynamic>? data,
  }) async {
    // Incoming events cannot request browser permission without a user click.
    if (!_isPermissionGranted) return;

    final payload = <String, dynamic>{
      'type': 'order_status',
      'orderId': orderId,
      ...?data
    };
    await _showBrowserNotification(
        title,
        body,
        'order-status-${notificationId ?? Object.hash(orderId, title)}',
        payload);
  }

  Future<void> _showBrowserNotification(String title, String body, String tag,
      Map<String, dynamic> payload) async {
    if (!_isPermissionGranted) return;
    if (payload['type'] == 'order_status' ||
        payload['type'] == 'passenger_leaving') {
      final key = '${payload['orderId']}:$title';
      if (!_shownTripNotices.add(key)) return;
      if (_shownTripNotices.length > 200) {
        _shownTripNotices.remove(_shownTripNotices.first);
      }
    }
    _activeNotifications.remove(tag)?.close();
    try {
      final registration = await web.window.navigator.serviceWorker.ready.toDart
          .timeout(const Duration(seconds: 2));
      await registration
          .showNotification(
              title,
              web.NotificationOptions(
                body: body,
                silent: payload['type'] == 'chat_message',
                icon: '/icons/Icon-192.png',
                tag: tag,
                renotify: true,
                data: payload.jsify(),
              ))
          .toDart;
      return;
    } catch (_) {}
    try {
      final notification = web.Notification(
          title,
          web.NotificationOptions(
              body: body,
              silent: payload['type'] == 'chat_message',
              icon: '/icons/Icon-192.png',
              tag: tag,
              data: payload.jsify()));
      _activeNotifications[tag] = notification;
      notification.onclick = ((web.Event _) {
        notification.close();
        _activeNotifications.remove(tag);
        _focusCurrentWindow();
        _payloadStreamController.add(payload);
      }).toJS;
      notification.onclose =
          ((web.Event _) => _activeNotifications.remove(tag)).toJS;
    } catch (_) {
      // Unsupported notifications must not interrupt the trip screen.
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    if (message.data['type'] == 'chat_message') {
      await ChatMessageNotices.shared
          .notify(Map<String, dynamic>.from(message.data));
      return;
    }
    _payloadStreamController.add(Map<String, dynamic>.from(message.data));
    final tripId = message.data['orderId']?.toString();
    final status = message.data['type'] == 'passenger_leaving'
        ? 'passenger_leaving'
        : message.data['status']?.toString();
    if (tripId != null && status != null) {
      unawaited(TripStatusSound.playOnce(tripId, status));
    }
    final notification = message.notification;
    if (notification == null) return;
    final payload = <String, dynamic>{
      ...message.data,
      'route': message.data['route']?.toString() ?? '/profile'
    };
    await _showBrowserNotification(
        notification.title ?? 'INTERCITY',
        notification.body ?? '',
        'remote-${message.messageId ?? notification.hashCode}',
        payload);
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
    try {
      if (!web.window.navigator.userActivation.isActive) return;
    } catch (_) {
      return;
    }
    final permission = _notificationPermission;
    if (permission == 'granted' ||
        permission == 'denied' ||
        permission == 'unsupported') {
      return;
    }
    try {
      await web.Notification.requestPermission()
          .toDart
          .then((_) => syncTokenIfAuthorized())
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Ignore blocked/unsupported permission requests.
    }
  }

  // iPhone browser tabs may not expose Notification at all. Optional push
  // support must never break login after valid tokens have been saved.
  String get _notificationPermission {
    try {
      return web.Notification.permission;
    } catch (_) {
      return 'unsupported';
    }
  }

  bool get _isPermissionGranted => _notificationPermission == 'granted';

  void _focusCurrentWindow() {
    try {
      web.window.focus();
    } catch (_) {
      // Ignore browsers that block focus() without direct user gesture.
    }
  }

  Future<bool> _sendTokenToBackend(String token) async {
    try {
      final accessToken = await ApiClient().getAccessToken();
      if (accessToken == null || accessToken.isEmpty) return false;
      await ApiClient().post(
        '/auth/push-token',
        data: <String, dynamic>{
          'token': token,
          'platform': 'WEB',
        },
      );
      _registered = true;
      return true;
    } catch (_) {
      _registered = false;
      return false;
    } finally {
      web.window.dispatchEvent(web.Event('intercity-push-ready'));
    }
  }
}
