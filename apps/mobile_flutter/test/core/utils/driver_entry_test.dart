import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/utils/driver_entry.dart';

class EntryApi extends ApiClient {
  EntryApi(this.profile, {this.documentsRequired = false, this.statusCode});
  final dynamic profile;
  final bool documentsRequired;
  final int? statusCode;
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    if (path == '/driver/profile' && statusCode != null) {
      throw DioException(
          requestOptions: RequestOptions(path: path),
          response: Response(
              requestOptions: RequestOptions(path: path),
              statusCode: statusCode));
    }
    return Response(
        requestOptions: RequestOptions(path: path),
        data: path == '/auth/me'
            ? {'driverDocumentsRequired': documentsRequired}
            : profile);
  }
}

void main() {
  test('passenger without driver profile must enter driver registration',
      () async {
    expect(await driverEntryRedirect(EntryApi(null, statusCode: 404)),
        '/driver/verification/personal');
    expect(await driverEntryRedirect(EntryApi(null)),
        '/driver/verification/personal');
  });
  test('driver cannot enter work before documents and approval', () async {
    final profile = {
      'id': 'driver',
      'carModel': 'BMW X5',
      'carNumber': 'A123BC77',
      'status': 'PENDING'
    };
    expect(await driverEntryRedirect(EntryApi(profile)),
        '/driver/verification/docs');
    profile['status'] = 'ACTIVE';
    expect(
        await driverEntryRedirect(EntryApi(profile, documentsRequired: true)),
        '/driver/verification/docs');
    expect(await driverEntryRedirect(EntryApi(profile)), isNull);
  });
  test('network failure does not pretend that registration is missing',
      () async {
    await expectLater(driverEntryRedirect(EntryApi(null, statusCode: 503)),
        throwsA(isA<DioException>()));
  });
}
