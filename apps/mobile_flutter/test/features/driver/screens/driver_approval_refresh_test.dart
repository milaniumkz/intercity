import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/driver/screens/driver_verification_page.dart';

class ApprovalApi extends ApiClient {
  bool approved = false;
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(
          requestOptions: RequestOptions(path: path),
          data: switch (path) {
            '/driver/profile' => {
                'id': 'driver',
                'status': approved ? 'ACTIVE' : 'PENDING',
                'carModel': 'ГАЗ Газель',
                'carNumber': 'A123BC77'
              },
            '/auth/me' => {'driverDocumentsRequired': false},
            '/auth/identity/status' => {'enabled': true, 'driverConsent': true},
            '/tax/me' => {'driverTaxIntegrationPaused': true},
            _ => {'name': 'Олег', 'phone': '+77000000000'}
          });
}

void main() {
  testWidgets(
      'approval received while the page is open replaces registration with driver entry without reloading',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ApprovalApi();
    await tester
        .pumpWidget(MaterialApp(home: DriverVerificationPage(apiClient: api)));
    await tester.pumpAndSettle();
    expect(find.text('Перейти в режим водителя'), findsNothing);
    api.approved = true;
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text('Перейти в режим водителя'), findsOneWidget);
    expect(
        find.textContaining('Повторная регистрация не нужна'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
