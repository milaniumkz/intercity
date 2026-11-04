import 'dart:async';
import 'package:flutter/widgets.dart';
import 'push_notifications_service.dart';
import 'trip_status_sound.dart';

/// FCM, realtime and chat polling share message IDs, so each message rings once.
class ChatMessageNotices {
  ChatMessageNotices(
      {Future<void> Function(String, String)? sound,
      Future<void> Function(Map<String, dynamic>)? notification})
      : _sound = sound ?? TripStatusSound.playOnce,
        _notification = notification ?? _showNotification;
  static final shared = ChatMessageNotices();
  final Future<void> Function(String, String) _sound;
  final Future<void> Function(Map<String, dynamic>) _notification;
  final _seen = <String>{};
  final openThreads = <String>{};
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;
  static String threadKey(String kind, String id) => '$kind:$id';

  Future<void> notify(Map<String, dynamic> payload) async {
    final id = '${payload['messageId'] ?? ''}',
        tripId = '${payload['orderId'] ?? ''}';
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    final kind = '${payload['kind'] ?? ''}';
    if (id.isEmpty ||
        tripId.isEmpty ||
        !['CITY', 'INTERCITY'].contains(kind) ||
        !_seen.add('$kind:$tripId:$id')) {
      return;
    }
    if (_seen.length > 500) _seen.remove(_seen.first);
    final driver = payload['recipientRole'] == 'DRIVER';
    final fallback = driver
        ? Uri(path: '/driver/home', queryParameters: {
            kind == 'INTERCITY' ? 'intercityRequestId' : 'orderId': tripId,
            'chat': '1',
            'chatMessageId': id
          }).toString()
        : Uri(
            path:
                '${kind == 'INTERCITY' ? '/intercity/request/' : '/order/searching/'}$tripId',
            queryParameters: {'chat': '1', 'chatMessageId': id}).toString();
    final notice = <String, dynamic>{
      ...payload,
      'type': 'chat_message',
      'route': payload['route'] ?? fallback
    };
    _events.add(notice);
    await Future.wait([
      Future<void>.sync(() => _sound(tripId, 'CHAT:$id')).catchError((_) {}),
      Future<void>.sync(() => _notification(notice)).catchError((_) {})
    ]);
  }

  static Future<void> _showNotification(Map<String, dynamic> data) =>
      PushNotificationsService.instance.showOrderStatusNotification(
          orderId: '${data['orderId']}',
          title: '${data['title'] ?? 'Новое сообщение'}',
          body: '${data['body'] ?? 'Вам написали в чате'}',
          notificationId: '${data['messageId']}'.hashCode,
          data: data);
  Future<void> dispose() => _events.close();
}

List<Map<String, dynamic>> newIncomingChatMessages(
    {required Set<String> known,
    required bool initialized,
    required List<dynamic> messages,
    required String role}) {
  final incoming = <Map<String, dynamic>>[];
  for (final raw in messages.whereType<Map>()) {
    final message = Map<String, dynamic>.from(raw), id = '${raw['id'] ?? ''}';
    final mine = raw['isMine'] is bool
        ? raw['isMine'] == true
        : '${raw['participantRole'] ?? ''}' == role;
    if (id.isNotEmpty && known.add(id) && initialized && !mine) {
      incoming.add(message);
    }
  }
  return incoming;
}
