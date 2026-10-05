import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/services/push_notification_payloads.dart';

void main() {
  test('buildDriverOfferPayload encodes driver offer route and id', () {
    final payload = buildDriverOfferPayload(orderId: 'order-1');

    expect(payload['type'], 'driver_offer');
    expect(payload['orderId'], 'order-1');
    expect(payload['route'], '/driver/home');
  });

  test('encode/decode push payload round-trips map payloads', () {
    final raw = encodePushPayload(<String, dynamic>{
      'type': 'driver_offer',
      'orderId': 'abc',
      'route': '/driver/home',
    });

    expect(
      decodePushPayload(raw),
      <String, dynamic>{
        'type': 'driver_offer',
        'orderId': 'abc',
        'route': '/driver/home',
      },
    );
  });

  test('buildDriverOfferNotificationBody keeps seconds in message', () {
    final body = buildDriverOfferNotificationBody(
      fromAddress: 'Алматы',
      toAddress: 'Астана',
      secondsLeft: 17,
    );

    expect(body, 'Алматы -> Астана • 17 сек на принятие');
  });
}
