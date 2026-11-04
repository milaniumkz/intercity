import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/driver/screens/driver_trip_create_page.dart';

void main() {
  testWidgets(
      'accepted passenger remains visible when matching fails and opens the correct trip',
      (tester) async {
    tester.view.physicalSize = const Size(392, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = AcceptedApi();
    final router = GoRouter(initialLocation: '/driver/trips', routes: [
      GoRoute(
          path: '/driver/trips',
          builder: (_, __) => DriverTripCreatePage(apiClient: api)),
      GoRoute(
          path: '/driver/home',
          builder: (_, state) => Scaffold(
              body: Text(
                  'Opened ${state.uri.queryParameters['intercityRequestId']}'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    final trip = find.byKey(const ValueKey('active-intercity-accepted-trip'));
    expect(trip, findsOneWidget);
    expect(find.textContaining('Анна'), findsOneWidget);
    expect(find.text('Нет заявок по выбранным фильтрам.'), findsNothing);
    expect(find.textContaining('Не удалось загрузить заявки пассажиров'),
        findsOneWidget);
    api.fail = false;
    await tester.ensureVisible(find.text('Повторить загрузку'));
    await tester.tap(find.text('Повторить загрузку'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось загрузить заявки пассажиров'),
        findsNothing);
    await tester.scrollUntilVisible(trip, -250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(trip);
    await tester.pumpAndSettle();
    expect(find.text('Opened accepted-trip'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
}

class AcceptedApi extends ApiClient {
  bool fail = true;
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    if (path.endsWith('/matching') && fail) {
      throw DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.connectionError);
    }
    return Response(
        requestOptions: RequestOptions(path: path),
        data: path.endsWith('/active')
            ? [
                {
                  'id': 'accepted-trip',
                  'fromCity': 'Риддер',
                  'toCity': 'Усть-Каменогорск',
                  'seats': 1,
                  'status': 'DRIVER_ASSIGNED',
                  'passenger': {'name': 'Анна'}
                }
              ]
            : []);
  }
}
