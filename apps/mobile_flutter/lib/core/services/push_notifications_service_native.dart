import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/api_client.dart';
import 'push_notification_payloads.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await _initializeFirebaseForSupportedNativePlatform();
  } catch (_) {
    // Firebase may already be initialized or config may be absent.
  }
}

@pragma('vm:entry-point')
void onDidReceiveBackgroundNotificationResponse(NotificationResponse response) {
  // Intentionally empty: this callback just enables notification actions/taps
  // for terminated/background states on Android.
}

class PushNotificationsService {
  PushNotificationsService._();

  static final PushNotificationsService instance = PushNotificationsService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, dynamic>> _payloadStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _initialized = false;
  bool _firebaseReady = false;

  Stream<Map<String, dynamic>> get onNotificationPayload =>
      _payloadStreamController.stream;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _initLocalNotifications();

    try {
      await _initializeFirebaseForSupportedNativePlatform();
      _firebaseReady = true;
    } catch (_) {
      // Missing google-services.json / plist or Firebase setup not finished.
      _firebaseReady = false;
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    await messaging.setAutoInitEnabled(true);

    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await _sendTokenToBackend(token);
    }

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _payloadStreamController.add(Map<String, dynamic>.from(message.data));
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      await _sendTokenToBackend(token);
    });
  }

  Future<void> enableDriverNotifications() async {
    if (!_firebaseReady) return;
    await FirebaseMessaging.instance
        .requestPermission(alert: true, badge: true, sound: true);
    await syncTokenIfAuthorized();
  }

  Future<void> syncTokenIfAuthorized() async {
    if (!_firebaseReady) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _sendTokenToBackend(token);
      }
    } catch (_) {
      // Optional: app should work even if FCM token sync fails
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(
        android: androidSettings, iOS: DarwinInitializationSettings());
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          onDidReceiveBackgroundNotificationResponse,
    );

    const androidChannel = AndroidNotificationChannel(
      'intercity_default_channel',
      'INTERCITY уведомления',
      description: 'Заказы, статусы, сообщения сервиса',
      importance: Importance.max,
    );

    const driverChannel = AndroidNotificationChannel(
      'intercity_driver_offers_v2',
      'Новые заказы водителя',
      description: 'Звуковой сигнал новых предложений заказа',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('intercity_order'),
      enableVibration: true,
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(driverChannel);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    _payloadStreamController.add(Map<String, dynamic>.from(message.data));
    final notification = message.notification;
    if (notification == null) return;
    await _localNotifications.show(
      notification.hashCode,
      notification.title ?? 'INTERCITY',
      notification.body ?? '',
      const NotificationDetails(
        iOS: DarwinNotificationDetails(presentSound: true),
        android: AndroidNotificationDetails(
          'intercity_default_channel',
          'INTERCITY уведомления',
          channelDescription: 'Заказы, статусы, сообщения сервиса',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      payload: encodePushPayload(Map<String, dynamic>.from(message.data)),
    );
  }

  Future<void> cancelDriverOfferNotification(String orderId) async {
    try {
      await _localNotifications.cancel(orderId.hashCode);
    } catch (_) {}
  }

  Future<void> showDriverOfferNotification({
    required String orderId,
    required String fromAddress,
    required String toAddress,
    int? secondsLeft,
    int? notificationId,
  }) async {
    final sec = (secondsLeft ?? 30).clamp(1, 3600);
    final payload =
        encodePushPayload(buildDriverOfferPayload(orderId: orderId));
    await _localNotifications.show(
      notificationId ?? orderId.hashCode,
      'Новый заказ',
      buildDriverOfferNotificationBody(
        fromAddress: fromAddress,
        toAddress: toAddress,
        secondsLeft: sec,
      ),
      NotificationDetails(
        iOS: const DarwinNotificationDetails(
            presentSound: true,
            sound: 'intercity_order.wav',
            interruptionLevel: InterruptionLevel.timeSensitive),
        android: AndroidNotificationDetails(
          'intercity_driver_offers_v2',
          'Новые заказы водителя',
          channelDescription: 'Заказы, статусы, сообщения сервиса',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          timeoutAfter: sec * 1000,
          onlyAlertOnce: false,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('intercity_order'),
          enableVibration: true,
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          ticker: 'Новый заказ для водителя',
        ),
      ),
      payload: payload,
    );
  }

  Future<void> showOrderStatusNotification({
    required String orderId,
    required String title,
    required String body,
    int? notificationId,
  }) async {
    await _localNotifications.show(
      notificationId ?? Object.hash(orderId, title),
      title,
      body,
      const NotificationDetails(
        iOS: DarwinNotificationDetails(presentSound: true),
        android: AndroidNotificationDetails(
          'intercity_default_channel',
          'INTERCITY уведомления',
          channelDescription: 'Заказы, статусы, сообщения сервиса',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
      ),
      payload: encodePushPayload({
        'type': 'order_status',
        'orderId': orderId,
      }),
    );
  }

  void _onDidReceiveNotificationResponse(NotificationResponse response) {
    final parsed = decodePushPayload(response.payload);
    if (parsed != null) {
      _payloadStreamController.add(parsed);
    }
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      final accessToken = await ApiClient().getAccessToken();
      if (accessToken == null || accessToken.isEmpty) return;
      await ApiClient().post('/auth/push-token', data: <String, dynamic>{
        'token': token,
        'platform': _platformName(),
      });
    } catch (_) {
      // Ignore until backend endpoint/config is available.
    }
  }

  String _platformName() {
    if (kIsWeb) return 'WEB';
    if (Platform.isAndroid) return 'ANDROID';
    if (Platform.isIOS) return 'IOS';
    return 'UNKNOWN';
  }
}

Future<void> _initializeFirebaseForSupportedNativePlatform() {
  if (Platform.isAndroid) {
    return Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyC1DhcnvHMItFX_pxJfBXG-geQTmhd3QHw',
        appId: '1:176647550231:android:fcc297a0ecdb070c6d7352',
        messagingSenderId: '176647550231',
        projectId: 'inter-city-pkzpps',
        storageBucket: 'inter-city-pkzpps.firebasestorage.app',
      ),
    );
  }
  return Firebase.initializeApp();
}
