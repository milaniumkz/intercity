import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:intercity_shared/intercity_shared.dart';

import '../constants/app_constants.dart';
import '../services/secure_store.dart';

abstract class ApiTokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureApiTokenStore implements ApiTokenStore {
  SecureApiTokenStore([SecureStore? storage])
      : _storage = storage ??
            createSecureStore(namespace: AppConstants.secureStoreNamespace);

  final SecureStore _storage;

  @override
  Future<String?> read(String key) => _storage.read(key);

  @override
  Future<void> write(String key, String value) => _storage.write(key, value);

  @override
  Future<void> delete(String key) => _storage.delete(key);
}

class ApiClient {
  ApiClient({
    Dio? dio,
    Dio? refreshDio,
    ApiTokenStore? tokenStore,
    String? baseUrl,
  }) : _storage = tokenStore ?? SecureApiTokenStore() {
    final resolvedBaseUrl = _normalizeBaseUrl(baseUrl ?? _resolvedBaseUrl);
    _dio = dio ?? Dio();
    _refreshDio = refreshDio ?? Dio();
    _configureDio(_dio, baseUrl: resolvedBaseUrl);
    _configureDio(_refreshDio, baseUrl: resolvedBaseUrl);
    _dio.interceptors.insert(
      0,
      QueuedInterceptorsWrapper(
        onRequest: _onRequest,
        onError: _onError,
      ),
    );
  }

  static final ApiTokenStore _globalStorage = SecureApiTokenStore();
  static const String _retriedRequestKey = 'intercity.auth.retried';
  static const String _skipRefreshKey = 'intercity.auth.skip_refresh';
  static const String _tokenSnapshotKey = 'intercity.auth.token_snapshot';

  static final String _buildTimeBaseUrl = AppConstants.baseUrl;
  static String _resolvedBaseUrl = _buildTimeBaseUrl;

  late final Dio _dio;
  late final Dio _refreshDio;
  final ApiTokenStore _storage;
  Future<void>? _refreshFuture;

  static Future<void> init() async {
    final storedBaseUrl = await _globalStorage.read(AppConstants.apiBaseUrlKey);
    final resolvedBaseUrl = resolveInitialBaseUrlForTesting(
      storedBaseUrl: storedBaseUrl,
      buildTimeBaseUrl: _buildTimeBaseUrl,
    );
    final normalizedStoredBaseUrl = IntercityApiConfig.normalize(storedBaseUrl);
    final shouldDropStoredOverride = (storedBaseUrl ?? '').trim().isNotEmpty &&
        resolvedBaseUrl == _buildTimeBaseUrl &&
        _buildTimeBaseUrl != IntercityApiConfig.safePlaceholderBaseUrl &&
        normalizedStoredBaseUrl != _buildTimeBaseUrl;

    if (shouldDropStoredOverride) {
      await _globalStorage.delete(AppConstants.apiBaseUrlKey);
    }

    _resolvedBaseUrl = resolvedBaseUrl;
  }

  static String get currentBaseUrl => _resolvedBaseUrl;

  static Future<void> setCustomBaseUrl(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await clearCustomBaseUrl();
      return;
    }
    final normalized = _normalizeBaseUrl(trimmed);
    await _globalStorage.write(AppConstants.apiBaseUrlKey, normalized);
    _resolvedBaseUrl = normalized;
  }

  static Future<void> clearCustomBaseUrl() async {
    await _globalStorage.delete(AppConstants.apiBaseUrlKey);
    _resolvedBaseUrl = _buildTimeBaseUrl;
  }

  @visibleForTesting
  static String resolveInitialBaseUrlForTesting({
    String? storedBaseUrl,
    String? buildTimeBaseUrl,
  }) {
    final normalizedBuildTimeBaseUrl =
        IntercityApiConfig.normalize(buildTimeBaseUrl);
    final normalizedStoredBaseUrl = IntercityApiConfig.normalize(storedBaseUrl);
    final hasExplicitBuildTimeBaseUrl =
        normalizedBuildTimeBaseUrl != IntercityApiConfig.safePlaceholderBaseUrl;

    if (hasExplicitBuildTimeBaseUrl) {
      return normalizedBuildTimeBaseUrl;
    }

    final hasStoredOverride = (storedBaseUrl ?? '').trim().isNotEmpty &&
        normalizedStoredBaseUrl != IntercityApiConfig.safePlaceholderBaseUrl;
    if (hasStoredOverride) {
      return normalizedStoredBaseUrl;
    }

    return normalizedBuildTimeBaseUrl;
  }

  static String _normalizeBaseUrl(String? raw) {
    final normalized = IntercityApiConfig.normalize(raw);
    if ((raw ?? '').trim().isEmpty) {
      return _buildTimeBaseUrl;
    }
    return normalized;
  }

  void _configureDio(Dio dio, {required String baseUrl}) {
    dio.options.baseUrl = baseUrl;
    dio.options.connectTimeout ??= const Duration(seconds: 30);
    dio.options.receiveTimeout ??= const Duration(seconds: 30);
    final headers = Map<String, dynamic>.from(dio.options.headers);
    headers.putIfAbsent('Content-Type', () => 'application/json');
    dio.options.headers = headers;
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_shouldAttachAuthorization(options)) {
      final token = await _storage.read(AppConstants.accessTokenKey);
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
        options.extra[_tokenSnapshotKey] = token;
      }
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_shouldAttemptRefresh(error)) {
      handler.next(error);
      return;
    }

    try {
      final token = await _resolveRetryToken(error.requestOptions);
      if (token == null || token.isEmpty) {
        throw const AuthSessionExpiredException();
      }
      final response =
          await _retryRequestWithToken(error.requestOptions, token);
      handler.resolve(response);
    } on AuthSessionExpiredException catch (sessionError) {
      handler.reject(
        _buildManagedAuthError(error.requestOptions, sessionError),
      );
    } catch (_) {
      handler.reject(
        _buildManagedAuthError(
          error.requestOptions,
          const AuthSessionExpiredException(),
        ),
      );
    }
  }

  bool _shouldAttachAuthorization(RequestOptions options) {
    return options.extra[_skipRefreshKey] != true &&
        !_isNonRefreshableRequest(options.path);
  }

  bool _shouldAttemptRefresh(DioException error) {
    if (error.response?.statusCode != 401) return false;
    if (error.requestOptions.extra[_retriedRequestKey] == true) return false;
    if (error.requestOptions.extra[_skipRefreshKey] == true) return false;
    return !_isNonRefreshableRequest(error.requestOptions.path);
  }

  bool _isNonRefreshableRequest(String path) {
    final normalized = path.toLowerCase();
    return normalized.endsWith('/auth/refresh') ||
        normalized.endsWith('/auth/login') ||
        normalized.endsWith('/auth/register') ||
        normalized.endsWith('/auth/reset-password');
  }

  Future<String?> _resolveRetryToken(RequestOptions requestOptions) async {
    final currentToken = await getAccessToken();
    final requestToken = requestOptions.extra[_tokenSnapshotKey]?.toString();
    if (currentToken != null &&
        currentToken.isNotEmpty &&
        requestToken != null &&
        requestToken.isNotEmpty &&
        currentToken != requestToken) {
      return currentToken;
    }
    await _refreshAccessToken();
    return getAccessToken();
  }

  Future<Response<dynamic>> _retryRequestWithToken(
    RequestOptions requestOptions,
    String token,
  ) {
    requestOptions
      ..headers['Authorization'] = 'Bearer $token'
      ..extra[_retriedRequestKey] = true
      ..extra[_tokenSnapshotKey] = token;
    return _dio.fetch<dynamic>(requestOptions);
  }

  Future<void> _refreshAccessToken() {
    final inFlight = _refreshFuture;
    if (inFlight != null) return inFlight;

    final completer = Completer<void>();
    _refreshFuture = completer.future;

    () async {
      try {
        final refreshToken = await _storage.read(AppConstants.refreshTokenKey);
        if (refreshToken == null || refreshToken.isEmpty) {
          throw const AuthSessionExpiredException('Refresh token is missing.');
        }

        final response = await _refreshDio.post<dynamic>(
          '/auth/refresh',
          data: <String, dynamic>{'refreshToken': refreshToken},
          options: Options(extra: <String, dynamic>{_skipRefreshKey: true}),
        );
        final tokens = _extractTokens(response.data);
        await setTokens(tokens.$1, tokens.$2);
        completer.complete();
      } catch (error, stackTrace) {
        await clearTokens();
        completer.completeError(_toSessionExpired(error), stackTrace);
      } finally {
        _refreshFuture = null;
      }
    }();

    return completer.future;
  }

  (String, String) _extractTokens(dynamic data) {
    if (data is! Map) {
      throw const AuthSessionExpiredException(
        'Refresh response does not contain token payload.',
      );
    }
    final map = Map<String, dynamic>.from(data);
    final accessToken = map['accessToken']?.toString().trim() ?? '';
    final refreshToken = map['refreshToken']?.toString().trim() ?? '';
    if (accessToken.isEmpty || refreshToken.isEmpty) {
      throw const AuthSessionExpiredException(
        'Refresh response does not contain valid tokens.',
      );
    }
    return (accessToken, refreshToken);
  }

  AuthSessionExpiredException _toSessionExpired(Object error) {
    if (error is AuthSessionExpiredException) {
      return error;
    }
    if (error is DioException) {
      final serverMessage = _extractServerMessage(error.response?.data);
      if (serverMessage != null && serverMessage.isNotEmpty) {
        return AuthSessionExpiredException(serverMessage);
      }
    }
    return const AuthSessionExpiredException();
  }

  DioException _buildManagedAuthError(
    RequestOptions requestOptions,
    AuthSessionExpiredException error,
  ) {
    return DioException(
      requestOptions: requestOptions,
      response: Response<dynamic>(
        requestOptions: requestOptions,
        statusCode: 401,
        data: <String, dynamic>{'message': error.message},
      ),
      type: DioExceptionType.badResponse,
      error: error,
      message: error.message,
    );
  }

  String? _extractServerMessage(dynamic data) {
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final message = map['message']?.toString().trim();
      if (message != null && message.isNotEmpty) {
        return message;
      }
    }
    if (data is String && data.trim().isNotEmpty) {
      return data.trim();
    }
    return null;
  }

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: options,
    );
  }

  Future<Response<dynamic>> post(
    String path, {
    dynamic data,
    Options? options,
  }) {
    return _dio.post<dynamic>(path, data: data, options: options);
  }

  Future<Response<dynamic>> patch(
    String path, {
    dynamic data,
    Options? options,
  }) {
    return _dio.patch<dynamic>(path, data: data, options: options);
  }

  Future<Response<dynamic>> delete(
    String path, {
    Options? options,
  }) {
    return _dio.delete<dynamic>(path, options: options);
  }

  Future<void> setTokens(String accessToken, String refreshToken) async {
    await _storage.write(AppConstants.accessTokenKey, accessToken);
    await _storage.write(AppConstants.refreshTokenKey, refreshToken);
  }

  Future<void> clearTokens() async {
    await _storage.delete(AppConstants.accessTokenKey);
    await _storage.delete(AppConstants.refreshTokenKey);
  }

  Future<String?> getAccessToken() {
    return _storage.read(AppConstants.accessTokenKey);
  }
}
