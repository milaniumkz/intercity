import '../api/api_client.dart';

/// Optional device-reported navigation events. Business results come from the server.
class TechnicalTelemetry {
  static Future<void> screenOpened(String path) async {
    try {
      final api = ApiClient();
      if ((await api.getAccessToken() ?? '').isEmpty) return;
      // Never send referral codes, query strings, addresses or arbitrary route values.
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) return;
      const allowed = {
        'driver',
        'order',
        'intercity',
        'market',
        'profile',
        'wallet',
        'orders-history'
      };
      if (!allowed.contains(segments.first)) return;
      await api.post('/technical-client/event', data: {
        'action': 'screen.open',
        'objectId': segments.first,
      });
    } catch (_) {
      // Telemetry failure must not interrupt navigation or recurse into telemetry.
    }
  }
}
