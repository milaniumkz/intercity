import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/utils/app_mode_manager.dart';

void main() {
  group('AppModeManager.resolveHomeRoute', () {
    final api = ApiClient(
      dio: Dio(),
      refreshDio: Dio(),
      tokenStore: _MemoryTokenStore(),
      baseUrl: 'https://api.intercity.invalid/api',
    );

    test('routes admins to admin dashboard without consulting driver status',
        () async {
      var driverStatusCalls = 0;
      final route = await AppModeManager.resolveHomeRoute(
        api,
        role: 'ADMIN',
        loadDriverStatus: (_) async {
          driverStatusCalls++;
          return 'APPROVED';
        },
      );

      expect(route, '/admin/dashboard');
      expect(driverStatusCalls, 0);
    });

    test('keeps approved driver in remembered driver mode', () async {
      String? persistedMode;
      final route = await AppModeManager.resolveHomeRoute(
        api,
        role: 'PASSENGER',
        readLastMode: () async => AppModeManager.driverMode,
        writeLastMode: (mode) async => persistedMode = mode,
        loadDriverStatus: (_) async => 'APPROVED',
      );

      expect(route, '/driver/home');
      expect(persistedMode, AppModeManager.driverMode);
    });

    test('falls back to passenger mode when driver is not approved', () async {
      String? persistedMode;
      final route = await AppModeManager.resolveHomeRoute(
        api,
        role: 'DRIVER',
        readLastMode: () async => AppModeManager.driverMode,
        writeLastMode: (mode) async => persistedMode = mode,
        loadDriverStatus: (_) async => 'PENDING',
      );

      expect(route, '/order');
      expect(persistedMode, AppModeManager.passengerMode);
    });

    test('prefers driver home for approved driver without saved mode',
        () async {
      String? persistedMode;
      final route = await AppModeManager.resolveHomeRoute(
        api,
        role: 'DRIVER',
        readLastMode: () async => null,
        writeLastMode: (mode) async => persistedMode = mode,
        loadDriverStatus: (_) async => 'ACTIVE',
      );

      expect(route, '/driver/home');
      expect(persistedMode, AppModeManager.driverMode);
    });
  });
}

class _MemoryTokenStore implements ApiTokenStore {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}
