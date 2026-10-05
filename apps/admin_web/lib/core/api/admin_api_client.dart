import 'dart:async';

import 'package:dio/dio.dart';
import 'package:intercity_shared/intercity_shared.dart';

import 'admin_token_store.dart';

export 'admin_token_store.dart';

abstract class AdminApi {
  Future<Map<String, dynamic>> login(String phone, String password);
  Future<void> logout();
  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? query});
  Future<Response<dynamic>> post(String path, {dynamic data});
  Future<Response<dynamic>> patch(String path, {dynamic data});
  Future<Response<dynamic>> delete(String path);
}

class AdminApiClient implements AdminApi {
  AdminApiClient({
    Dio? dio,
    Dio? refreshDio,
    AdminTokenStore? tokenStore,
    String? baseUrl,
  }) : _storage = tokenStore ?? createDefaultAdminTokenStore() {
    final resolvedBaseUrl = IntercityApiConfig.normalize(
      baseUrl ??
          const String.fromEnvironment(
            IntercityApiConfig.envKey,
            defaultValue: IntercityApiConfig.safePlaceholderBaseUrl,
          ),
    );
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

  static final AdminApiClient _defaultInstance = AdminApiClient();
  static AdminApi? _overrideInstance;

  static const String _accessTokenKey = 'admin_access_token';
  static const String _refreshTokenKey = 'admin_refresh_token';
  static const String _retriedRequestKey = 'intercity.admin.retried';
  static const String _skipRefreshKey = 'intercity.admin.skip_refresh';
  static const String _tokenSnapshotKey = 'intercity.admin.token_snapshot';

  static AdminApi get instance => _overrideInstance ?? _defaultInstance;

  static void debugOverride(AdminApi? client) {
    _overrideInstance = client;
  }

  late final Dio _dio;
  late final Dio _refreshDio;
  final AdminTokenStore _storage;
  Future<void>? _refreshFuture;

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
      final token = await _storage.read(_accessTokenKey);
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
      final retried = await _retryRequestWithToken(error.requestOptions, token);
      handler.resolve(retried);
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
        normalized.endsWith('/auth/login');
  }

  Future<String?> _resolveRetryToken(RequestOptions requestOptions) async {
    final currentToken = await _storage.read(_accessTokenKey);
    final requestToken = requestOptions.extra[_tokenSnapshotKey]?.toString();
    if (currentToken != null &&
        currentToken.isNotEmpty &&
        requestToken != null &&
        requestToken.isNotEmpty &&
        currentToken != requestToken) {
      return currentToken;
    }
    await _refreshTokens();
    return _storage.read(_accessTokenKey);
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

  Future<void> _refreshTokens() {
    final inFlight = _refreshFuture;
    if (inFlight != null) return inFlight;

    final completer = Completer<void>();
    _refreshFuture = completer.future;

    () async {
      try {
        final refreshToken = await _storage.read(_refreshTokenKey);
        if (refreshToken == null || refreshToken.isEmpty) {
          throw const AuthSessionExpiredException('Refresh token is missing.');
        }

        final response = await _refreshDio.post<dynamic>(
          '/auth/refresh',
          data: <String, dynamic>{'refreshToken': refreshToken},
          options: Options(extra: <String, dynamic>{_skipRefreshKey: true}),
        );
        final tokens = _extractTokens(response.data);
        await _persistTokens(tokens.$1, tokens.$2);
        completer.complete();
      } catch (error, stackTrace) {
        await logout();
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

  Future<void> _persistTokens(String accessToken, String refreshToken) async {
    await _storage.write(_accessTokenKey, accessToken);
    await _storage.write(_refreshTokenKey, refreshToken);
  }

  @override
  Future<Map<String, dynamic>> login(String phone, String password) async {
    final res = await _dio.post<dynamic>(
      '/auth/login',
      data: <String, dynamic>{'phone': phone, 'password': password},
    );
    final data = Map<String, dynamic>.from(res.data as Map);
    final tokens = _extractTokens(data);
    await _persistTokens(tokens.$1, tokens.$2);
    return Map<String, dynamic>.from(data['user'] as Map);
  }

  @override
  Future<void> logout() async {
    await _storage.delete(_accessTokenKey);
    await _storage.delete(_refreshTokenKey);
  }

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) {
    return _dio.get<dynamic>(path, queryParameters: query);
  }

  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) {
    return _dio.post<dynamic>(path, data: data);
  }

  @override
  Future<Response<dynamic>> patch(String path, {dynamic data}) {
    return _dio.patch<dynamic>(path, data: data);
  }

  @override
  Future<Response<dynamic>> delete(String path) {
    return _dio.delete<dynamic>(path);
  }
}
