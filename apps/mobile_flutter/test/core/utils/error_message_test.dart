import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/utils/error_message_ru.dart';
import 'package:intercity_mobile/core/utils/localization_service.dart';

void main() {
  group('errorMessage localization', () {
    test('returns Russian text when Russian is active', () async {
      await LocalizationService.setLanguage(AppLanguage.russian);

      final message = errorMessage(
        DioException(
          requestOptions: RequestOptions(path: '/wallet'),
          type: DioExceptionType.connectionError,
        ),
      );

      expect(
        message,
        'Нет соединения с сервером. Проверьте интернет или адрес сервиса.',
      );
    });

    test('returns Kazakh text when Kazakh is active', () async {
      await LocalizationService.setLanguage(AppLanguage.kazakh);

      final message = errorMessage(
        DioException(
          requestOptions: RequestOptions(path: '/wallet'),
          type: DioExceptionType.connectionError,
        ),
      );

      expect(
        message,
        'Сервермен байланыс жоқ. Интернетті немесе сервис адресін тексеріңіз.',
      );
    });

    test('translates known server messages to active language', () async {
      await LocalizationService.setLanguage(AppLanguage.kazakh);

      final message = errorMessage(
        DioException(
          requestOptions: RequestOptions(path: '/wallet/transfer'),
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/wallet/transfer'),
            statusCode: 404,
            data: const <String, dynamic>{'message': 'Recipient not found'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      expect(message, 'Мұндай нөмірі бар пайдаланушы табылмады.');
    });
  });
}
