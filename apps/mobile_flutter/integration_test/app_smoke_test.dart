import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';
import 'package:intercity_mobile/features/passenger/screens/profile_page.dart';
import 'package:intercity_mobile/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _FakeBackendServer backend;
  final secureStorage = <String, String>{};
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final args =
          (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      final key = args['key']?.toString();
      switch (call.method) {
        case 'read':
          return key == null ? null : secureStorage[key];
        case 'write':
          if (key != null) {
            secureStorage[key] = (args['value'] ?? '').toString();
          }
          return null;
        case 'delete':
          if (key != null) {
            secureStorage.remove(key);
          }
          return null;
        case 'deleteAll':
          secureStorage.clear();
          return null;
        case 'containsKey':
          return key != null && secureStorage.containsKey(key);
        case 'readAll':
          return Map<String, String>.from(secureStorage);
      }
      return null;
    });
    backend = await _FakeBackendServer.start();
    await ApiClient.setCustomBaseUrl(backend.baseUrl);
  });

  tearDownAll(() async {
    await ApiClient.clearCustomBaseUrl();
    await backend.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  setUp(() async {
    await ApiClient().clearTokens();
    backend.reset();
  });

  testWidgets('unauthorized user is routed to login', (tester) async {
    await _launchApp(tester);
    expect(find.text('Войти'), findsOneWidget);
  });

  testWidgets('authorized passenger can open profile with driver onboarding',
      (tester) async {
    backend.userRole = 'PASSENGER';
    backend.driverProfile = null;

    await _launchScreen(tester, const ProfilePage());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Профиль'), findsWidgets);
    expect(find.textContaining('водител'), findsWidgets);
  });

  testWidgets('intercity order mode copy is visible and understandable',
      (tester) async {
    backend.userRole = 'PASSENGER';

    await _launchScreen(
      tester,
      const OrderScreen(
        routeStage: 'mode',
        enableLiveMap: false,
        autoLocateOnStart: false,
      ),
    );

    final intercityCard = find.text('Межгород').last;
    await tester.ensureVisible(intercityCard);

    expect(find.text('Что нужно заказать?'), findsOneWidget);
    expect(find.text('Межгород'), findsWidgets);
    expect(find.text('Аукцион'), findsWidgets);
  });
}

Future<void> _launchApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 2200);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(const ProviderScope(child: IntercityApp()));
  await _pumpBriefly(tester, seconds: 5);
}

Future<void> _launchScreen(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1440, 2200);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: child,
      ),
    ),
  );
  await _pumpBriefly(tester, seconds: 4);
}

Future<void> _pumpBriefly(
  WidgetTester tester, {
  required int seconds,
}) async {
  for (var i = 0; i < seconds; i += 1) {
    await tester.pump(const Duration(seconds: 1));
  }
}

class _FakeBackendServer {
  _FakeBackendServer._(this._server);

  final HttpServer _server;

  String userRole = 'PASSENGER';
  Map<String, dynamic>? driverProfile;

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  static Future<_FakeBackendServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final backend = _FakeBackendServer._(server);
    server.listen(backend._handle);
    return backend;
  }

  void reset() {
    userRole = 'PASSENGER';
    driverProfile = null;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (request.method == 'POST' && path == '/api/auth/login') {
      return _json(request, {
        'accessToken': 'access-token',
        'refreshToken': 'refresh-token',
        'user': {
          'id': 'user-1',
          'name': 'Тестовый пользователь',
          'phone': '+77771112233',
          'role': userRole,
          'refCode': 'REF123',
        }
      });
    }

    if (request.method == 'POST' && path == '/api/auth/refresh') {
      return _json(request, {
        'accessToken': 'access-token-new',
        'refreshToken': 'refresh-token-new',
      });
    }

    if (request.method == 'GET' && path == '/api/me') {
      return _json(request, {
        'id': 'user-1',
        'name': 'Тестовый пользователь',
        'phone': '+77771112233',
        'role': userRole,
        'refCode': 'REF123',
      });
    }

    if (request.method == 'GET' && path == '/api/driver/profile') {
      if (driverProfile == null) {
        return _json(request, {'message': 'Driver profile not found'},
            statusCode: 404);
      }
      return _json(request, driverProfile!);
    }

    if (request.method == 'GET' && path == '/api/driver/runtime-settings') {
      return _json(request, {
        'autoAcceptEnabled': true,
        'autoAcceptRadiusKm': 5,
      });
    }

    if (request.method == 'GET' && path == '/api/driver/orders/nearby') {
      return _json(request, []);
    }

    if (request.method == 'GET' && path.startsWith('/api/orders/')) {
      return _json(request, {
        'id': 'order-1',
        'status': 'SEARCHING_DRIVER',
        'price': 1200,
        'fromAddress': 'Шәкәрім даңғылы 143, Өскемен',
        'toAddress': 'Гоголь көшесі 1, Өскемен',
      });
    }

    if (request.method == 'POST' && path == '/api/orders') {
      final body = await utf8.decoder.bind(request).join();
      final data = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
      return _json(request, {
        'id': 'order-created-1',
        'echo': data,
      });
    }

    if (request.method == 'POST' && path == '/api/orders/preview') {
      return _json(request, {
        'distance': 4.2,
        'duration': 12,
        'price': 980,
      });
    }

    if (request.method == 'POST' && path == '/api/intercity/requests') {
      final body = await utf8.decoder.bind(request).join();
      final data = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
      return _json(request, {
        'id': 'intercity-request-1',
        'echo': data,
      });
    }

    return _json(request, {'message': 'Not found: $path'}, statusCode: 404);
  }

  Future<void> _json(HttpRequest request, Object data,
      {int statusCode = 200}) async {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(data));
    await request.response.close();
  }
}
