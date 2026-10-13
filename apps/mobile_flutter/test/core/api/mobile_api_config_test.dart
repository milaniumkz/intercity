import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/constants/app_constants.dart';

void main() {
  test(
      'default mobile API works without build flags and replaces stale overrides',
      () {
    expect(AppConstants.baseUrl,
        'https://api.intercity.89-207-255-27.sslip.io/api');
    expect(
      ApiClient.resolveInitialBaseUrlForTesting(
        buildTimeBaseUrl: AppConstants.baseUrl,
        storedBaseUrl: 'https://old-backend.example.com/api',
      ),
      AppConstants.baseUrl,
    );
  });
}
