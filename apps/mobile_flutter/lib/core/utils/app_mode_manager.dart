import '../api/api_client.dart';
import '../services/app_preferences.dart';
import 'driver_access.dart';
import 'role_routes.dart';

typedef AppModeReader = Future<String?> Function();
typedef AppModeWriter = Future<void> Function(String mode);
typedef DriverStatusLoader = Future<String?> Function(ApiClient api);

class AppModeManager {
  static const String passengerMode = 'passenger';
  static const String driverMode = 'driver';

  static Future<void> rememberPassengerMode() {
    return AppPreferences.setLastAppMode(passengerMode);
  }

  static Future<void> rememberDriverMode() {
    return AppPreferences.setLastAppMode(driverMode);
  }

  static Future<String> resolveHomeRoute(
    ApiClient api, {
    required String role,
    AppModeReader? readLastMode,
    AppModeWriter? writeLastMode,
    DriverStatusLoader? loadDriverStatus,
  }) async {
    final normalizedRole = role.toUpperCase();
    if (normalizedRole == 'ADMIN') {
      return '/admin/dashboard';
    }

    final readMode = readLastMode ?? AppPreferences.getLastAppMode;
    final persistMode = writeLastMode ?? AppPreferences.setLastAppMode;
    final driverStatusResolver = loadDriverStatus ?? _loadDriverStatus;
    final preferredMode = (await readMode())?.toLowerCase();
    final driverStatus = await driverStatusResolver(api);

    final canUseDriverMode = isApprovedDriverStatus(driverStatus);

    if (preferredMode == driverMode && canUseDriverMode) {
      await persistMode(driverMode);
      return '/driver/home';
    }

    if (preferredMode == passengerMode) {
      await persistMode(passengerMode);
      return '/order';
    }

    if (normalizedRole == 'DRIVER' && canUseDriverMode) {
      await persistMode(driverMode);
      return '/driver/home';
    }

    final fallbackRoute = homeRouteForRole(role);
    if (fallbackRoute == '/driver/home') {
      if (canUseDriverMode) {
        await persistMode(driverMode);
        return fallbackRoute;
      }
      await persistMode(passengerMode);
      return '/order';
    }

    await persistMode(passengerMode);
    return fallbackRoute;
  }

  static Future<String?> _loadDriverStatus(ApiClient api) async {
    try {
      final profileRes = await api.get('/driver/profile');
      final profile = profileRes.data is Map
          ? Map<String, dynamic>.from(profileRes.data as Map)
          : null;
      return profile?['status']?.toString();
    } catch (_) {
      return null;
    }
  }
}
