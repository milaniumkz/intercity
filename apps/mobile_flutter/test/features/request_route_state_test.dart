import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/passenger/screens/intercity_request_page.dart';
import 'package:intercity_mobile/main.dart';

class _Api extends ApiClient {
  final List<String> requests = [];
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    requests.add(path);
    throw DioException(requestOptions: RequestOptions(path: path));
  }
}

void main() {
  testWidgets('opening the next request disposes the previous request state',
      (tester) async {
    final api = _Api();
    final router = createRouter(initialLocation: '/market/request/first',
        disableAuthRedirect: true, orderApiClient: api);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    final first = tester.state(find.byType(IntercityRequestPage));
    router.go('/market/request/second');
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(IntercityRequestPage)), isNot(same(first)));
    expect(first.mounted, isFalse);
    expect(tester.widget<IntercityRequestPage>(find.byType(IntercityRequestPage)).requestId, 'second');
    expect(api.requests, containsAll(['/intercity/requests/first', '/intercity/requests/second']));
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });
}
