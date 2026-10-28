import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/utils/error_message_ru.dart';
import 'package:intercity_mobile/core/utils/localization_service.dart';

void main() {
  group('errorMessage localization', () {
    test('intercity balance errors from an older server are shown in Russian',
        () async {
      await LocalizationService.setLanguage(AppLanguage.russian);
      final error = DioException(
          type: DioExceptionType.badResponse,
          requestOptions: RequestOptions(path: '/intercity/requests'),
          response: Response(
              requestOptions: RequestOptions(path: '/intercity/requests'),
              statusCode: 400,
              data: {
                'message':
                    'Insufficient balance to respond to intercity request. Please top up wallet.'
              }));
      expect(errorMessageRu(error),
          'Недостаточно средств на балансе для межгорода. Пополните кошелёк.');
    });
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
