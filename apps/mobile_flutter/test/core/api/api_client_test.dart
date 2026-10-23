import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/constants/app_constants.dart';
import 'package:intercity_shared/intercity_shared.dart';

void main() {
  group('Sign-in transport recovery', () {
    test('retries a native timeout once with the same login and HTTPS URL',
        () async {
      var attempts = 0;
      final fallback = _buildMockDio((options) async {
        attempts++;
        expect(
            options.uri.toString(), 'https://api.example.com/api/auth/login');
        expect(options.data, {'phone': '+77001000002', 'password': 'test'});
        return _jsonBody({'accessToken': 'access', 'refreshToken': 'refresh'});
      });
      final primary = _buildMockDio((options) async {
        expect(options.connectTimeout, const Duration(seconds: 8));
        throw DioException.receiveTimeout(
            timeout: const Duration(seconds: 8), requestOptions: options);
      });
      final client = ApiClient(
          dio: primary,
          loginFallbackDio: fallback,
          tokenStore: _MemoryTokenStore(),
          baseUrl: 'https://api.example.com/api');
      final response = await client.post('/auth/login',
          data: {'phone': '+77001000002', 'password': 'test'});
      expect(response.data['accessToken'], 'access');
      expect(attempts, 1);
    });

    for (final scenario in ['password', 'certificate', 'cancel', 'payment']) {
      test('does not retry $scenario', () async {
        var attempts = 0;
        final fallback = _buildMockDio((_) async {
          attempts++;
          return _jsonBody({});
        });
        final primary = _buildMockDio((options) async {
          if (scenario == 'password') return _jsonBody({}, statusCode: 401);
          throw DioException(
              requestOptions: options,
              type: scenario == 'certificate'
                  ? DioExceptionType.badCertificate
                  : scenario == 'cancel'
                      ? DioExceptionType.cancel
                      : DioExceptionType.receiveTimeout);
        });
        final client = ApiClient(
            dio: primary,
            loginFallbackDio: fallback,
            tokenStore: _MemoryTokenStore(),
            baseUrl: 'https://api.example.com/api');
        await expectLater(
            client.post(
                scenario == 'payment' ? '/payments/create' : '/auth/login',
                data: {}),
            throwsA(isA<DioException>()));
        expect(attempts, 0);
      });
    }
  });

  group('ApiClient refresh flow', () {
    test('wrong current password preserves the authenticated session',
        () async {
      final store = _MemoryTokenStore()
        ..values[AppConstants.accessTokenKey] = 'valid-access'
        ..values[AppConstants.refreshTokenKey] = 'valid-refresh';
      var refreshCalls = 0;
      final apiDio = _buildMockDio((options) async {
        expect(options.headers['Authorization'], 'Bearer valid-access');
        if (options.path == '/auth/change-password') {
          return _jsonBody({'message': 'Неверный текущий пароль'},
              statusCode: 401);
        }
        return _jsonBody({'id': 'user'});
      });
      final refresh = _buildMockDio((_) async {
        refreshCalls++;
        return _jsonBody({}, statusCode: 401);
      });
      final client = ApiClient(
          dio: apiDio,
          refreshDio: refresh,
          tokenStore: store,
          baseUrl: 'https://api.example.com/api');
      await expectLater(client.post('/auth/change-password', data: {}),
          throwsA(isA<DioException>()));
      expect(refreshCalls, 0);
      expect(store.values[AppConstants.accessTokenKey], 'valid-access');
      expect((await client.get('/me')).data['id'], 'user');
    });

    test('reuses one refresh request for concurrent unauthorized calls',
        () async {
      final store = _MemoryTokenStore()
        ..values[AppConstants.accessTokenKey] = 'stale-access'
        ..values[AppConstants.refreshTokenKey] = 'valid-refresh';
      var refreshCalls = 0;

      final apiDio = _buildMockDio((options) async {
        if (options.path == '/me') {
          final authHeader = options.headers['Authorization']?.toString();
          if (authHeader == 'Bearer fresh-access') {
            return _jsonBody(<String, dynamic>{'id': 'user-1'});
          }
          return _jsonBody(
            const <String, dynamic>{'message': 'Unauthorized'},
            statusCode: 401,
          );
        }
        return _jsonBody(
          const <String, dynamic>{'message': 'Not found'},
          statusCode: 404,
        );
      });

      final refreshDio = _buildMockDio((options) async {
        if (options.path == '/auth/refresh') {
          refreshCalls++;
          return _jsonBody(<String, dynamic>{
            'accessToken': 'fresh-access',
            'refreshToken': 'fresh-refresh',
          });
        }
        return _jsonBody(
          const <String, dynamic>{'message': 'Not found'},
          statusCode: 404,
        );
      });

      final client = ApiClient(
        dio: apiDio,
        refreshDio: refreshDio,
        tokenStore: store,
        baseUrl: 'https://api.intercity.invalid/api',
      );

      final responses = await Future.wait<dynamic>([
        client.get('/me'),
        client.get('/me'),
      ]);

      expect(refreshCalls, 1);
      expect(responses, hasLength(2));
      expect(responses.first.data, <String, dynamic>{'id': 'user-1'});
      expect(store.values[AppConstants.accessTokenKey], 'fresh-access');
      expect(store.values[AppConstants.refreshTokenKey], 'fresh-refresh');
    });

    test('clears tokens and throws managed auth error when refresh fails',
        () async {
      final store = _MemoryTokenStore()
        ..values[AppConstants.accessTokenKey] = 'stale-access'
        ..values[AppConstants.refreshTokenKey] = 'expired-refresh';

      final apiDio = _buildMockDio((options) async {
        if (options.path == '/me') {
          return _jsonBody(
            const <String, dynamic>{'message': 'Unauthorized'},
            statusCode: 401,
          );
        }
        return _jsonBody(
          const <String, dynamic>{'message': 'Not found'},
          statusCode: 404,
        );
      });

      final refreshDio = _buildMockDio((options) async {
        if (options.path == '/auth/refresh') {
          return _jsonBody(
            const <String, dynamic>{'message': 'refresh expired'},
            statusCode: 401,
          );
        }
        return _jsonBody(
          const <String, dynamic>{'message': 'Not found'},
          statusCode: 404,
        );
      });

      final client = ApiClient(
        dio: apiDio,
        refreshDio: refreshDio,
        tokenStore: store,
        baseUrl: 'https://api.intercity.invalid/api',
      );

      await expectLater(
        client.get('/me'),
        throwsA(
          isA<DioException>().having(
            (error) => error.error,
            'error',
            isA<AuthSessionExpiredException>(),
          ),
        ),
      );
      expect(store.values[AppConstants.accessTokenKey], isNull);
      expect(store.values[AppConstants.refreshTokenKey], isNull);
    });

    test('does not try to refresh the refresh endpoint itself', () async {
      final store = _MemoryTokenStore()
        ..values[AppConstants.accessTokenKey] = 'stale-access'
        ..values[AppConstants.refreshTokenKey] = 'valid-refresh';
      var refreshCalls = 0;
      var refreshEndpointCalls = 0;

      final apiDio = _buildMockDio((options) async {
        if (options.path == '/auth/refresh') {
          refreshEndpointCalls++;
          return _jsonBody(
            const <String, dynamic>{'message': 'Unauthorized'},
            statusCode: 401,
          );
        }
        return _jsonBody(
          const <String, dynamic>{'message': 'Not found'},
          statusCode: 404,
        );
      });

      final refreshDio = _buildMockDio((options) async {
        refreshCalls++;
        return _jsonBody(
          const <String, dynamic>{'message': 'Not found'},
          statusCode: 404,
        );
      });

      final client = ApiClient(
        dio: apiDio,
        refreshDio: refreshDio,
        tokenStore: store,
        baseUrl: 'https://api.intercity.invalid/api',
      );

      await expectLater(
        client.post(
          '/auth/refresh',
          data: <String, dynamic>{'refreshToken': 'valid-refresh'},
        ),
        throwsA(isA<DioException>()),
      );
      expect(refreshEndpointCalls, 1);
      expect(refreshCalls, 0);
    });
  });

  group('ApiClient base URL resolution', () {
    test('prefers compile-time production URL over stored override', () {
      final resolved = ApiClient.resolveInitialBaseUrlForTesting(
        storedBaseUrl: 'https://stale-dev.example.com/api',
        buildTimeBaseUrl:
            'https://intercity-backend-4pfoxrpnkq-uc.a.run.app/api',
      );

      expect(
        resolved,
        'https://intercity-backend-4pfoxrpnkq-uc.a.run.app/api',
      );
    });

    test('uses stored override only when compile-time URL is placeholder', () {
      final resolved = ApiClient.resolveInitialBaseUrlForTesting(
        storedBaseUrl: 'https://staging.example.com/api',
        buildTimeBaseUrl: IntercityApiConfig.safePlaceholderBaseUrl,
      );

      expect(resolved, 'https://staging.example.com/api');
    });
  });
}

class _MemoryTokenStore implements ApiTokenStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

Dio _buildMockDio(
  Future<ResponseBody> Function(RequestOptions options) handler,
) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.intercity.invalid/api'));
  dio.httpClientAdapter = _MockAdapter(handler);
  return dio;
}

ResponseBody _jsonBody(
  dynamic data, {
  int statusCode = 200,
}) {
  return ResponseBody.fromString(
    jsonEncode(data),
    statusCode,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );
}

class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }
}
