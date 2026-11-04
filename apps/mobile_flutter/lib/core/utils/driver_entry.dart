import 'package:dio/dio.dart';
import '../api/api_client.dart';
import 'driver_access.dart';

Future<String?> driverEntryRedirect(ApiClient api) async {
  try {
    final response = await api.get('/driver/profile');
    final profile = response.data;
    if (profile is! Map || profile['id'] == null) {
      return '/driver/verification/personal';
    }
    if ((profile['carModel'] ?? '').toString().trim().isEmpty ||
        (profile['carNumber'] ?? '').toString().trim().isEmpty) {
      return '/driver/verification/personal';
    }
    if (!isApprovedDriverStatus(profile['status']?.toString())) {
      return '/driver/verification/docs';
    }
    final me = await api.get('/auth/me');
    if (me.data is Map && me.data['driverDocumentsRequired'] == true) {
      return '/driver/verification/docs';
    }
    return null;
  } on DioException catch (error) {
    if (error.response?.statusCode == 404) {
      return '/driver/verification/personal';
    }
    rethrow;
  }
}
