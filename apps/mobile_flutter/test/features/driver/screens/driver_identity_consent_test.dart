import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/driver/screens/driver_verification_page.dart';

class ConsentApi extends ApiClient {
  final posts = <Map<String, dynamic>>[];
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(
          requestOptions: RequestOptions(path: path),
          data: switch (path) {
            '/auth/identity/status' => {
                'enabled': true,
                'driverConsent': false
              },
            '/tax/me' => {'driverTaxIntegrationPaused': true},
            '/driver/profile' => {'id': 'driver', 'carModel': 'BMW X5'},
            _ => {'name': 'Олег', 'phone': '+77000000000'},
          });
  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data,
      Map<String, dynamic>? queryParameters,
      Options? options}) async {
    posts.add({'path': path, 'data': data});
    return Response(
        requestOptions: RequestOptions(path: path), data: {'success': true});
  }
}

void main() {
  testWidgets(
      'document step exposes explicit consent and sends it only after checkbox and password',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ConsentApi();
    await tester.pumpWidget(MaterialApp(
        home: DriverVerificationPage(routeStage: 'docs', apiClient: api)));
    await tester.pumpAndSettle();
    final consent = find.byType(CheckboxListTile);
    await tester.ensureVisible(consent);
    expect(tester.widget<CheckboxListTile>(consent).value, false);
    final allow =
        find.widgetWithText(FilledButton, 'Разрешить сверку удостоверения');
    expect(tester.widget<FilledButton>(allow).onPressed, isNull);
    await tester.tap(consent);
    await tester.pump();
    final password = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Пароль аккаунта');
    await tester.ensureVisible(password);
    await tester.enterText(password, 'local-current-password');
    await tester.ensureVisible(allow);
    await tester.tap(allow);
    await tester.pumpAndSettle();
    expect(api.posts.single['path'], '/auth/identity/driver-consent');
    expect(api.posts.single['data']['driverConsent'], true);
    expect(find.byType(CheckboxListTile), findsNothing);
  });
}
