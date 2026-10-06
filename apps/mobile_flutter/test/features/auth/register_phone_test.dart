import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/utils/phone_input_formatter.dart';
import 'package:intercity_mobile/features/auth/screens/register_screen.dart';

class _RegistrationApi extends ApiClient {
  final requests = <Map<String, dynamic>>[];
  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data,
      Map<String, dynamic>? queryParameters,
      Options? options}) async {
    requests.add({'path': path, 'data': data});
    return Response(
        requestOptions: RequestOptions(path: path),
        statusCode: path == '/auth/register' ? 201 : 200,
        data: {'accessToken': 'test-access', 'refreshToken': 'test-refresh'});
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('registration completes without requesting device location',
      (tester) async {
    final locationCalls = <String>[];
    const channel = MethodChannel('flutter.baseflow.com/geolocator');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      locationCalls.add(call.method);
      throw PlatformException(code: 'PERMISSION_DENIED');
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final api = _RegistrationApi();
    final router = GoRouter(initialLocation: '/register', routes: [
      GoRoute(
          path: '/register',
          builder: (_, __) => RegisterScreen(apiClient: api)),
      GoRoute(
          path: '/order',
          builder: (_, __) =>
              const Scaffold(body: Text('Регистрация завершена'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    Future<void> fill(String label, String value) async {
      final field = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == label);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
    }

    await fill('Имя', 'Тест');
    await fill('Телефон', '7771234567');
    await fill('Пароль', 'testPassword123');
    final submit = find.text('Создать аккаунт');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Регистрация завершена'), findsOneWidget);
    expect(locationCalls, isEmpty);
    expect(
        api.requests.map((r) => r['path']), ['/auth/register', '/auth/login']);
    expect(api.requests.first['data'], isNot(contains('lat')));
    expect(api.requests.first['data'], isNot(contains('lng')));
  });

  for (final role in ['passenger', 'driver']) {
    testWidgets('$role registration formats and validates the phone number',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: RegisterScreen(role: role)),
      );
      await tester.pumpAndSettle();

      final phoneField = find.ancestor(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.keyboardType == TextInputType.phone,
        ),
        matching: find.byType(TextFormField),
      );
      await tester.ensureVisible(phoneField);
      await tester.enterText(phoneField, '7771234567');
      await tester.pump();

      final field = tester.widget<TextFormField>(phoneField);
      final textField = tester.widget<TextField>(
        find.descendant(of: phoneField, matching: find.byType(TextField)),
      );
      expect(textField.decoration?.prefixText, '+7 ');
      expect(field.controller!.text, '(777) 123-45-67');
      expect(field.validator!(field.controller!.text), isNull);
      expect(normalizeKzLocalPhone(field.controller!.text), '+77771234567');

      await tester.enterText(phoneField, '+7 (778) 123-45-67');
      await tester.pump();
      expect(field.controller!.text, '(778) 123-45-67');
      expect(field.validator!(field.controller!.text), isNull);
      expect(normalizeKzLocalPhone(field.controller!.text), '+77781234567');

      await tester.enterText(phoneField, '777123');
      await tester.pump();
      expect(field.validator!(field.controller!.text), isNotNull);
    });
  }
}
