import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/widgets/password_change_dialog.dart';

class _PasswordApi extends ApiClient {
  int calls = 0;
  bool tokensSaved = false;
  final bool fail;
  _PasswordApi({this.fail = false});
  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data, Options? options}) async {
    calls++;
    expect(path, '/auth/change-password');
    expect(data['currentPassword'], 'current-password');
    if (fail) {
      throw DioException(
          type: DioExceptionType.badResponse,
          requestOptions: RequestOptions(path: path),
          response: Response(
              requestOptions: RequestOptions(path: path),
              statusCode: 401,
              data: {'message': 'Неверный текущий пароль'}));
    }
    return Response(
        requestOptions: RequestOptions(path: path),
        data: {'accessToken': 'new-access', 'refreshToken': 'new-refresh'});
  }

  @override
  Future<void> setTokens(String accessToken, String refreshToken) async {
    expect(accessToken, 'new-access');
    expect(refreshToken, 'new-refresh');
    tokensSaved = true;
  }
}

void main() {
  for (final fail in [false, true]) {
    testWidgets('password change validates and handles server failure=$fail',
        (tester) async {
      final api = _PasswordApi(fail: fail);
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => showPasswordChangeDialog(context, api),
                        child: const Text('Открыть')),
                  ))));
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить пароль'));
      await tester.pumpAndSettle();
      expect(api.calls, 0);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'current-password');
      await tester.enterText(fields.at(1), 'New-password-2026!');
      await tester.enterText(fields.at(2), 'New-password-2026!');
      await tester.tap(find.text('Сохранить пароль'));
      await tester.pumpAndSettle();
      expect(api.calls, 1);
      expect(api.tokensSaved, !fail);
      if (fail) {
        expect(find.byType(PasswordChangeDialog), findsOneWidget);
        expect(find.textContaining('Неверный текущий пароль'), findsOneWidget);
      } else {
        expect(find.byType(PasswordChangeDialog), findsNothing);
        expect(find.textContaining('Пароль изменён.'), findsOneWidget);
      }
    });
  }
}
