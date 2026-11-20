import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/api/review_demo.dart';
import 'package:intercity_mobile/core/utils/location_session.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';
import 'package:intercity_mobile/features/driver/screens/driver_earnings_page.dart';
import '../../core/api/review_demo_test.dart' show MemoryStore;

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ReviewDemo.reset();
    ReviewDemo.active.value = true;
  });
  tearDown(ReviewDemo.reset);
  for (final mode in ['fixed', 'auction']) {
    testWidgets('reviewer can open $mode booking and choose both addresses',
        (tester) async {
      final api = ApiClient(
          dio: Dio(),
          tokenStore: MemoryStore(),
          baseUrl: 'https://never-contact.example/api');
      final router = GoRouter(initialLocation: '/order/$mode', routes: [
        GoRoute(
            path: '/order/:stage',
            builder: (_, state) => OrderScreen(
                apiClient: api,
                routeStage: state.pathParameters['stage'],
                enableLiveMap: false,
                locationSession: LocationSession())),
      ]);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('city-address-from')), findsOneWidget);
      expect(find.byKey(const ValueKey('city-address-to')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(
          find.byKey(const ValueKey('city-address-to')), 'Казахстан');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('city-suggestion-0')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('city-suggestion-0')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    });
  }
  testWidgets('reviewer earnings report displays without a server',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: DriverEarningsPage(
            apiClient: ApiClient(
                dio: Dio(),
                tokenStore: MemoryStore(),
                baseUrl: 'https://never-contact.example/api'))));
    await tester.pumpAndSettle();
    expect(find.text('Заработок'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
