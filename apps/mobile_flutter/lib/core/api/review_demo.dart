import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Local review workspace. Every API request is resolved locally while active.
/// Review credentials unlock synthetic data only, including without API access.
class ReviewDemo {
  static final active = ValueNotifier(false);
  static const storageKey = 'intercity.review_demo.v1';
  static const phone = '+77001000002';
  static bool matchesLocalLogin(
    dynamic data, {
    String digest =
        const String.fromEnvironment('INTERCITY_REVIEW_PASSWORD_SHA256'),
  }) =>
      digest.isNotEmpty &&
      data is Map &&
      data['phone'] == phone &&
      data['password'] is String &&
      sha256.convert(utf8.encode(data['password'] as String)).toString() ==
          digest;
  static final user = <String, dynamic>{
    'id': 'demo-user',
    'name': 'InterCity App Review',
    'phone': phone,
    'role': 'DRIVER',
    'cityId': 'demo-ust',
    'identityRequired': false,
    'driverDocumentsRequired': false,
    'mustChangePassword': false,
    'refCode': 'DEMO',
    'refLink': 'https://intercity.89-207-255-27.sslip.io',
  };
  static bool accepts(dynamic value) =>
      value is Map && value['phone'] == phone && value['name'] == user['name'];
  static final cities = <Map<String, dynamic>>[
    {
      'id': 'demo-ust',
      'name': 'Усть-Каменогорск',
      'countryCode': 'KZ',
      'lat': 49.9489,
      'lng': 82.6275
    },
    {
      'id': 'demo-semey',
      'name': 'Семей',
      'countryCode': 'KZ',
      'lat': 50.4111,
      'lng': 80.2275
    },
    {
      'id': 'demo-almaty',
      'name': 'Алматы',
      'countryCode': 'KZ',
      'lat': 43.2389,
      'lng': 76.8897
    },
  ];
  static bool online = false;
  static Map<String, dynamic>? order;
  static final requests = <String, Map<String, dynamic>>{};
  static final messages = <Map<String, dynamic>>[];
  static int sequence = 0;

  static void reset() {
    active.value = false;
    online = false;
    order = null;
    requests.clear();
    messages.clear();
  }

  static Map<String, dynamic> sampleOrder([String id = 'demo-trip']) => {
        'id': id,
        'status': 'SEARCHING',
        'mode': 'CITY',
        'requestType': 'CITY_FIXED',
        'fromLat': 49.9489,
        'fromLng': 82.6275,
        'toLat': 49.961,
        'toLng': 82.612,
        'fromAddress': 'Демо — проспект Шакарима, 143',
        'toAddress': 'Демо — улица Казахстан, 55',
        'fromCity': 'Усть-Каменогорск',
        'toCity': 'Семей',
        'price': 1200,
        'finalPrice': 1200,
        'currency': 'KZT',
        'distance': 4.2,
        'duration': 600,
        'paymentMethod': 'CASH',
        'vehicleClass': 'ECONOMY',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 30))
            .toUtc()
            .toIso8601String(),
        'passenger': {'id': 'demo-passenger', 'name': 'Демо пассажир'},
        'driver': {
          'id': 'demo-driver',
          'carModel': 'Toyota Camry',
          'carNumber': 'DEMO',
          'user': {'name': 'Демо водитель'},
          'rating': {'average': 4.9, 'count': 10}
        },
      };

  static dynamic respond(RequestOptions options) {
    final uri = options.uri;
    final path = uri.path.replaceFirst(RegExp(r'^/api(?=/)'), '');
    final q = {...uri.queryParameters, ...options.queryParameters};
    final data = options.data is Map
        ? Map<String, dynamic>.from(options.data)
        : <String, dynamic>{};
    final write = options.method != 'GET';
    if (path == '/me' || path == '/auth/me') return {...user};
    if (path == '/auth/delete-account') {
      reset();
      return {'success': true};
    }
    if (path == '/auth/push-token') return {'success': true};
    if (path == '/app/runtime-settings' || path == '/driver/runtime-settings') {
      return {
        'passengerMapHomeEnabled': true,
        'identityVerificationEnabled': false
      };
    }
    if (path == '/driver/profile') {
      return {
        'id': 'demo-driver',
        'userId': user['id'],
        'status': 'ACTIVE',
        'user': {...user},
        'carModel': 'Toyota Camry',
        'carNumber': 'DEMO',
        'vehicles': [],
        'acceptCityFixed': true,
        'acceptCityAuction': true,
        'acceptIntercity': true,
        'acceptDelivery': true,
        'acceptCargo': true,
        'online': {
          'isOnline': online,
          'lat': 49.9489,
          'lng': 82.6275,
          'cityId': 'demo-ust'
        },
        'rating': {'average': 4.9, 'count': 10},
      };
    }
    if (path == '/driver/online') online = data['isOnline'] == true;
    if (path == '/driver/online' || path == '/driver/location') {
      return {'success': true, 'cityId': 'demo-ust', 'isOnline': online};
    }
    if (path == '/driver/orders/active' || path == '/orders/active') {
      return order;
    }
    if (path == '/driver/orders/nearby') {
      return online && order == null ? [sampleOrder()] : [];
    }
    if (path == '/driver/intercity/active') return null;
    if (path == '/driver/earnings') {
      return {
        'currency': q['currency'] ?? 'KZT',
        'trips': {'total': 3, 'completed': 3},
        'income': {'cash': 3600, 'card': 1200, 'total': 4800},
        'cashIncome': 3600,
        'cardIncome': 1200,
        'totalIncome': 4800,
        'serviceCommission': 480,
        'pendingCardPayments': 0,
        'refunds': 0,
        'tax': {'showSocialPayments': false},
      };
    }
    if (path == '/wallet') {
      return {
        'money': 5000,
        'bonus': 500,
        'bonuses': 500,
        'currency': q['currency'] ?? 'KZT',
        'balances': {
          'KZT': {'money': 5000, 'bonus': 500},
          'RUB': {'money': 500, 'bonus': 50}
        },
        'transactions': [
          {
            'id': 'demo-transaction',
            'type': 'TOPUP',
            'direction': 'IN',
            'balanceSource': 'MONEY',
            'amount': 5000,
            'currency': 'KZT',
            'note': 'Демонстрационное пополнение',
            'createdAt': DateTime.now().toUtc().toIso8601String()
          }
        ],
        'topups': [],
        'payouts': [],
      };
    }
    if (path.startsWith('/wallet/') && write ||
        path.startsWith('/payments/') && write) {
      throw DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: options, statusCode: 400, data: {
            'message': 'Демонстрация: реальные платежи и переводы недоступны.'
          }));
    }
    if (path == '/payments/cards') return {'configured': false, 'cards': []};
    if (path == '/geo/cities') return cities;
    if (path == '/geo/reverse') {
      return {
        'cityId': 'demo-ust',
        'city': 'Усть-Каменогорск',
        'countryCode': 'KZ',
        'currency': 'KZT',
        'address': 'Демо — проспект Шакарима, 143',
        'cityResolved': true,
        'addressResolved': true,
      };
    }
    if (path == '/geo/search') {
      return [
        for (final row in [
          sampleOrder(),
          {
            ...sampleOrder(),
            'fromLat': 49.961,
            'fromLng': 82.612,
            'fromAddress': 'Демо — улица Казахстан, 55'
          }
        ])
          {
            'lat': row['fromLat'],
            'lng': row['fromLng'],
            'address': row['fromAddress'],
            'displayName': row['fromAddress'],
            'cityId': 'demo-ust',
            'city': 'Усть-Каменогорск',
            'countryCode': 'KZ'
          },
      ];
    }
    if (path == '/route' || path == '/orders/preview') {
      return {
        'price': 1200,
        'currency': 'KZT',
        'distance': 4.2,
        'duration': 600,
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [
              q['fromLng'] ?? data['fromLng'] ?? 82.6275,
              q['fromLat'] ?? data['fromLat'] ?? 49.9489
            ],
            [
              q['toLng'] ?? data['toLng'] ?? 82.612,
              q['toLat'] ?? data['toLat'] ?? 49.961
            ],
          ]
        },
      };
    }
    if (path == '/orders' && write) {
      order = {...sampleOrder('demo-order-${++sequence}'), ...data};
      return order;
    }
    if (path.startsWith('/driver/orders/') && write) {
      order = {
        ...sampleOrder(),
        'status': path.endsWith('/accept') ? 'ACCEPTED' : 'CANCELLED'
      };
      return order;
    }
    if (path.startsWith('/orders/') && !path.contains('history')) {
      if (path.endsWith('/cancel')) {
        final result = {...?order, 'status': 'CANCELLED'};
        order = null;
        return result;
      }
      if (path.endsWith('/status')) {
        order = {...?order, ...data};
        return order;
      }
      if (path.contains('messages') || path.endsWith('/chat')) {
        if (write) {
          messages.add({
            'id': 'demo-message-${++sequence}',
            'text': data['text'] ?? data['message'],
            'senderId': user['id'],
            'createdAt': DateTime.now().toUtc().toIso8601String()
          });
        }
        return write ? messages.last : messages;
      }
      return order ?? sampleOrder(path.split('/').last);
    }
    if (path == '/intercity/requests' && write) {
      final id = 'demo-request-${++sequence}';
      final request = {
        ...sampleOrder(id),
        ...data,
        'status': 'OPEN',
        'offers': [
          {
            'id': 'demo-offer',
            'price': data['desiredPrice'] ?? 5000,
            'status': 'PENDING',
            'driver': sampleOrder()['driver'],
            'createdAt': DateTime.now().toUtc().toIso8601String()
          },
        ]
      };
      requests[id] = request;
      return request;
    }
    if (path.startsWith('/intercity/requests/')) {
      final id = path.split('/')[3];
      final request =
          requests[id] ?? {...sampleOrder(id), 'status': 'OPEN', 'offers': []};
      if (path.endsWith('/cancel')) request['status'] = 'CANCELLED';
      requests[id] = request;
      return request;
    }
    if (path.contains('history') ||
        path == '/orders' ||
        path == '/intercity/requests/mine') {
      return [
        {...sampleOrder('demo-history'), 'status': 'COMPLETED'}
      ];
    }
    if (path.contains('referral')) {
      return {
        'refCode': 'DEMO',
        'refLink': user['refLink'],
        'balance': 0,
        'referrals': [],
        'transactions': []
      };
    }
    if (path.contains('trips') ||
        path.contains('routes') ||
        path.contains('requests') ||
        path.contains('notifications') ||
        path.contains('messages')) {
      return [];
    }
    if (write) return {'success': true, 'id': 'demo-${++sequence}', ...data};
    return <String, dynamic>{};
  }
}
