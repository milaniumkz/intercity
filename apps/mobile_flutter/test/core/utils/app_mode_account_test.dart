import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/core/utils/app_mode_manager.dart';

void main() {
  test('each account retains its own mode through logout and login', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = ApiClient();
    await AppPreferences.setAppModeUser('oleg');
    await AppModeManager.rememberDriverMode();
    await api.clearTokens();
    expect(
        await AppModeManager.resolveHomeRoute(api,
            role: 'DRIVER',
            userId: 'oleg',
            loadDriverStatus: (_) async => 'APPROVED'),
        '/driver/home');
    await AppModeManager.rememberPassengerMode();
    await api.clearTokens();
    expect(
        await AppModeManager.resolveHomeRoute(api,
            role: 'DRIVER',
            userId: 'oleg',
            loadDriverStatus: (_) async => 'APPROVED'),
        '/order');
    await AppPreferences.setAppModeUser('other');
    await AppModeManager.rememberDriverMode();
    expect(
        await AppModeManager.resolveHomeRoute(api,
            role: 'DRIVER',
            userId: 'oleg',
            loadDriverStatus: (_) async => 'APPROVED'),
        '/order');
    expect(
        await AppModeManager.resolveHomeRoute(api,
            role: 'DRIVER',
            userId: 'other',
            loadDriverStatus: (_) async => 'APPROVED'),
        '/driver/home');
  });
}
