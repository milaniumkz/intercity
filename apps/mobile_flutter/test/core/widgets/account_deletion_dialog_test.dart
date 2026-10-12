import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intercity_mobile/core/utils/location_session.dart';
import 'package:intercity_mobile/core/utils/browser_location_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/widgets/account_deletion_dialog.dart';

class _DeleteApi extends ApiClient {
  int calls = 0;
  bool cleared = false;
  @override
  Future<void> clearTokens() async {
    cleared = true;
  }

  bool fail = false;
  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data, Options? options}) async {
    calls++;
    expect(path, '/auth/delete-account');
    expect(data, {'password': 'test-password'});
    if (fail) {
      throw DioException(
          type: DioExceptionType.badResponse,
          requestOptions: RequestOptions(path: path),
          response: Response(
              requestOptions: RequestOptions(path: path),
              statusCode: 400,
              data: {'message': 'Неверный пароль'}));
    }
    return Response(
        requestOptions: RequestOptions(path: path), data: {'deleted': true});
  }
}

void main() {
  testWidgets(
      'full deletion flow clears the local session and confirms before returning to login',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = _DeleteApi();
    sharedLocationSession.rememberFix(
        const BrowserLocation(latitude: 49.9, longitude: 82.6, accuracy: 10));
    final router = GoRouter(initialLocation: '/profile', routes: [
      GoRoute(
          path: '/profile',
          builder: (context, state) => Scaffold(
              body: TextButton(
                  onPressed: () => showAccountDeletion(context, api),
                  child: const Text('Удалить аккаунт')))),
      GoRoute(
          path: '/login',
          builder: (context, state) => const Scaffold(body: Text('Вход'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Удалить аккаунт'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('account-delete-password')), 'test-password');
    await tester.pump();
    await tester.tap(find.text('Удалить навсегда'));
    await tester.pumpAndSettle();
    expect(find.text('Аккаунт удалён'), findsOneWidget);
    expect(api.cleared, true);
    expect(sharedLocationSession.freshFix, isNull);
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    expect(find.text('Вход'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });

  for (final failed in [false, true]) {
    testWidgets(
        'deletion requires confirmation and handles response: failed=$failed',
        (tester) async {
      final api = _DeleteApi()..fail = failed;
      bool? deleted;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        deleted = await showDialog<bool>(
                            context: context,
                            builder: (_) => AccountDeletionDialog(api: api));
                      },
                      child: const Text('Открыть'))))));
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      expect(api.calls, 0);
      await tester.enterText(
          find.byKey(const ValueKey('account-delete-password')),
          'test-password');
      await tester.pump();
      await tester.tap(find.text('Удалить навсегда'));
      await tester.pumpAndSettle();
      expect(api.calls, 1);
      if (failed) {
        expect(find.text('Неверный пароль'), findsOneWidget);
        expect(deleted, isNull);
      } else {
        expect(deleted, true);
        expect(find.byType(AccountDeletionDialog), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
