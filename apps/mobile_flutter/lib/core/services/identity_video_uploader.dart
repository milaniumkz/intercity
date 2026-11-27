import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../api/api_client.dart';

/// Keeps the captured bytes reusable when an upload response is lost.
class IdentityVideoUploader {
  IdentityVideoUploader(this.api);
  final ApiClient api;

  Future<Map<String, dynamic>> send({
    required Map<String, dynamic> challenge,
    required bool recovery,
    required Uint8List bytes,
    required String filename,
    void Function()? onRetry,
  }) async {
    if (bytes.length < 10000 || bytes.length > 16 * 1024 * 1024) {
      throw StateError('Не удалось сохранить полную запись. Повторите видео.');
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await api.post(
          '/auth/identity/${recovery ? 'recovery' : 'enroll'}/${challenge['challengeId']}/video',
          data: FormData.fromMap({
            'challengeToken': challenge['challengeToken'],
            'video': MultipartFile.fromBytes(bytes, filename: filename),
          }),
          options: Options(
            contentType: 'multipart/form-data',
            sendTimeout: const Duration(seconds: 120),
            receiveTimeout: const Duration(seconds: 180),
          ),
        );
        return Map<String, dynamic>.from(response.data as Map);
      } on DioException catch (error) {
        final uncertain = error.response == null ||
            (error.response?.statusCode ?? 0) >= 500;
        if (!uncertain) rethrow;
        // Never record again or blindly upload twice if the server has it.
        try {
          final response = await api.post('/auth/identity/challenge-status',
              data: {'challengeId': challenge['challengeId'],
                     'challengeToken': challenge['challengeToken']});
          final state = Map<String, dynamic>.from(response.data as Map);
          if (state['status'] != 'READY') return state;
        } catch (_) {
          // Keep the original network error; captured bytes remain available.
          rethrow;
        }
        if (attempt == 1) rethrow;
        onRetry?.call();
      }
    }
    throw StateError('Повторите отправку записи.');
  }
}
