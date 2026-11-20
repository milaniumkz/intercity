import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/api/review_demo.dart';

class MemoryStore implements ApiTokenStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class LoginAdapter implements HttpClientAdapter {
  int calls = 0;
  final bool demo;
  LoginAdapter({this.demo = true});
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
      Future<void>? cancel) async {
    calls++;
    if (options.path != '/auth/login') {
      throw StateError('Unexpected production request');
    }
    return ResponseBody.fromString(
        jsonEncode({
          'accessToken': 'test-access',
          'refreshToken': 'test-refresh',
          'user': {
            'id': 'server-id',
            'name': demo ? 'InterCity App Review' : 'Passenger',
            'phone': ReviewDemo.phone,
            'role': 'DRIVER',
            'identityRequired': true
          }
        }),
        201,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(ReviewDemo.reset);
  tearDown(ReviewDemo.reset);
  test('local demo login requires both the dedicated phone and matching digest',
      () {
    final digest = sha256.convert(utf8.encode('test-only-password')).toString();
    expect(
        ReviewDemo.matchesLocalLogin(
            {'phone': ReviewDemo.phone, 'password': 'test-only-password'},
            digest: digest),
        true);
    expect(
        ReviewDemo.matchesLocalLogin(
            {'phone': ReviewDemo.phone, 'password': 'wrong'},
            digest: digest),
        false);
    expect(
        ReviewDemo.matchesLocalLogin(
            {'phone': '+77000000000', 'password': 'test-only-password'},
            digest: digest),
        false);
    expect(
        ReviewDemo.matchesLocalLogin(
            {'phone': ReviewDemo.phone, 'password': 'test-only-password'},
            digest: ''),
        false);
  });
  test('authenticated review login opens isolated driver and passenger data',
      () async {
    final adapter = LoginAdapter();
    final api = ApiClient(
        dio: Dio()..httpClientAdapter = adapter,
        tokenStore: MemoryStore(),
        baseUrl: 'https://example.com/api');
    final login = await api.post('/auth/login',
        data: {'phone': ReviewDemo.phone, 'password': 'test'});
    expect(login.data['user']['identityRequired'], false);
    await api.setTokens('test-access', 'test-refresh');
    expect((await api.get('/driver/profile')).data['status'], 'ACTIVE');
    await api.post('/driver/online', data: {'isOnline': true});
    expect((await api.get('/driver/orders/nearby')).data, isNotEmpty);
    final order =
        await api.post('/orders', data: {'fromAddress': 'Demo pickup'});
    final id = order.data['id'];
    expect((await api.get('/orders/$id')).data['fromAddress'], 'Demo pickup');
    await api.post('/orders/$id/cancel');
    expect((await api.get('/driver/orders/active')).data, isNull);
    expect((await api.get('/wallet')).data['money'], 5000);
    await expectLater(api.post('/wallet/topup-request', data: {'amount': 100}),
        throwsA(isA<DioException>()));
    expect(adapter.calls, 1);
    await api.clearTokens();
    expect(ReviewDemo.active.value, false);
  });
  test('ordinary account keeps identity requirements', () async {
    final api = ApiClient(
        dio: Dio()..httpClientAdapter = LoginAdapter(demo: false),
        tokenStore: MemoryStore(),
        baseUrl: 'https://example.com/api');
    final login = await api.post('/auth/login', data: {});
    expect(login.data['user']['identityRequired'], true);
    expect(ReviewDemo.active.value, false);
  });
}
