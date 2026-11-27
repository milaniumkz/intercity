import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/identity_video_uploader.dart';

class UploadApi extends ApiClient {
  UploadApi({this.serverStatus = 'READY', this.httpError});
  final String serverStatus;
  final int? httpError;
  int uploads = 0, statusChecks = 0;
  final bodies = <FormData>[];
  @override
  Future<Response<dynamic>> post(String path, {dynamic data,
      Map<String, dynamic>? queryParameters, Options? options}) async {
    final request = RequestOptions(path: path);
    if (path.endsWith('/challenge-status')) {
      statusChecks++;
      return Response(requestOptions: request, data: {'status': serverStatus});
    }
    expect(path, '/auth/identity/enroll/challenge/video');
    uploads++;
    final body = data as FormData;
    bodies.add(body);
    final chunks = await body.finalize().toList();
    expect(chunks.fold<int>(0, (n, b) => n + b.length), greaterThan(12000));
    if (uploads == 1 || httpError != null) {
      throw DioException(requestOptions: request,
        type: httpError == null ? DioExceptionType.connectionError : DioExceptionType.badResponse,
        response: httpError == null ? null : Response(requestOptions: request, statusCode: httpError));
    }
    return Response(requestOptions: request, data: {'status': 'VERIFIED'});
  }
}
void main() {
  final challenge = {'challengeId': 'challenge', 'challengeToken': 'camera-secret'};
  final bytes = Uint8List(12000);
  test('twenty dropped uploads resend the same recording with a fresh multipart stream', () async {
    for (var i = 0; i < 20; i++) {
      final api = UploadApi();
      final result = await IdentityVideoUploader(api).send(challenge: challenge,
        recovery: false, bytes: bytes, filename: 'camera.mp4');
      expect(result['status'], 'VERIFIED');
      expect(api.uploads, 2);
      expect(api.statusChecks, 1);
      expect(identical(api.bodies[0], api.bodies[1]), isFalse);
    }
  });
  for (final state in ['PROCESSING', 'VERIFIED', 'REJECTED', 'FAILED']) {
    test('lost response with server $state does not upload again', () async {
      final api = UploadApi(serverStatus: state);
      final result = await IdentityVideoUploader(api).send(challenge: challenge,
        recovery: false, bytes: bytes, filename: 'camera.mp4');
      expect(result['status'], state);
      expect(api.uploads, 1);
    });
  }
  for (final status in [400, 401, 403, 413, 429]) {
    test('HTTP $status is not blindly retried', () async {
      final api = UploadApi(httpError: status);
      await expectLater(IdentityVideoUploader(api).send(challenge: challenge,
        recovery: false, bytes: bytes, filename: 'camera.mp4'), throwsA(isA<DioException>()));
      expect(api.uploads, 1);
      expect(api.statusChecks, 0);
    });
  }
}
