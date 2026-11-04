import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/auth/screens/login_screen.dart';
import 'package:intercity_mobile/core/widgets/ic_premium.dart';

class RecoveryApi extends ApiClient {
  final changes = <Map<String, dynamic>>[];
  @override
  Future<void> setTokens(String accessToken, String refreshToken) async {}
  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data, Options? options}) async {
    if (path == '/auth/login') {
      return Response(requestOptions: RequestOptions(path: path), data: {
        'accessToken': 'local-only',
        'refreshToken': 'local-only',
        'user': {'id': 'qa', 'role': 'PASSENGER', 'mustChangePassword': true}
      });
    }
    if (path == '/auth/change-password') {
      changes.add(Map<String, dynamic>.from(data as Map));
      throw DioException(
          type: DioExceptionType.badResponse,
          requestOptions: RequestOptions(path: path),
          response: Response(
              requestOptions: RequestOptions(path: path),
              statusCode: 401,
              data: {'message': 'Неверный текущий пароль'}));
    }
    throw StateError('Unexpected request $path');
  }
}

void main() {
  testWidgets(
      'temporary login requires explicit current password and keeps failed change in dialog',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = RecoveryApi();
    await tester.pumpWidget(MaterialApp(home: LoginScreen(apiClient: api)));
    await tester.enterText(find.byType(TextFormField).at(0), '7771234567');
    await tester.enterText(find.byType(TextFormField).at(1), '123456');
    await tester.tap(find.byType(ICGradientButton));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Замените временный пароль'), findsOneWidget);
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(1), 'New-long-password-9');
    await tester.enterText(fields.at(2), 'New-long-password-9');
    await tester.tap(find.text('Сохранить'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Введите текущий временный пароль'), findsOneWidget);
    expect(api.changes, isEmpty);
    await tester.enterText(fields.at(0), '123456');
    await tester.tap(find.text('Сохранить'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.changes.single,
        {'currentPassword': '123456', 'newPassword': 'New-long-password-9'});
    expect(find.text('Замените временный пароль'), findsOneWidget);
    expect(find.textContaining('Неверный текущий пароль'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
