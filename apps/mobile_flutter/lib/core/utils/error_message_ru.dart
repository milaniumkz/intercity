import 'package:dio/dio.dart';
import 'package:intercity_shared/intercity_shared.dart';

import 'localization_service.dart';

String errorMessage(Object error) {
  String t(String russianText, String kazakhText) {
    return LocalizationService.translate(russianText, kazakhText);
  }

  if (error is AuthSessionExpiredException) {
    return t(
      'Сессия истекла. Войдите в приложение заново.',
      'Сессия аяқталды. Қайта кіріңіз.',
    );
  }
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return t(
          'Не удалось подключиться к серверу. Проверьте интернет и попробуйте снова.',
          'Серверге қосылу мүмкін болмады. Интернетті тексеріп, қайта көріңіз.',
        );
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return t(
          'Сервер отвечает слишком долго. Попробуйте еще раз.',
          'Сервер тым ұзақ жауап беріп жатыр. Қайта көріңіз.',
        );
      case DioExceptionType.connectionError:
        return t(
          'Нет соединения с сервером. Проверьте интернет или адрес сервиса.',
          'Сервермен байланыс жоқ. Интернетті немесе сервис адресін тексеріңіз.',
        );
      case DioExceptionType.cancel:
        return t('Запрос был отменен.', 'Сұрау тоқтатылды.');
      case DioExceptionType.badCertificate:
        return t(
          'Ошибка защищенного соединения с сервером.',
          'Сервермен қорғалған байланыс қатесі.',
        );
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        final serverMessage = _extractServerMessage(error.response?.data);
        final translatedMessage = _translateServerMessage(serverMessage);
        if (code == 400) {
          return translatedMessage ??
              _safeServerMessage(serverMessage) ??
              t(
                'Некорректные данные. Проверьте заполненные поля.',
                'Деректер қате. Толтырылған өрістерді тексеріңіз.',
              );
        }
        if (code == 401) {
          return _translateServerMessage(serverMessage) ??
              t(
                'Неверный логин или пароль.',
                'Логин немесе құпия сөз қате.',
              );
        }
        if (code == 403) {
          return _translateServerMessage(serverMessage) ??
              t(
                'Недостаточно прав для выполнения действия.',
                'Бұл әрекетті орындауға құқық жеткіліксіз.',
              );
        }
        if (code == 404) {
          return _translateServerMessage(serverMessage) ??
              t('Данные не найдены.', 'Деректер табылмады.');
        }
        if (code == 409) {
          return _translateServerMessage(serverMessage) ??
              t(
                'Такое действие уже выполнено или данные уже существуют.',
                'Бұл әрекет бұрын орындалған немесе мұндай деректер бар.',
              );
        }
        if (code != null && code >= 500) {
          return _translateServerMessage(serverMessage) ??
              t(
                'Ошибка сервера. Попробуйте позже.',
                'Сервер қатесі. Кейінірек қайталап көріңіз.',
              );
        }
        return _translateServerMessage(serverMessage) ??
            t('Ошибка запроса к серверу.', 'Серверге сұрау қатесі.');
      case DioExceptionType.unknown:
        final msg = error.message?.toLowerCase() ?? '';
        if (msg.contains('failed host lookup') ||
            msg.contains('socketexception') ||
            msg.contains('no address associated with hostname')) {
          return t(
            'Сервис временно недоступен. Проверьте интернет и попробуйте снова.',
            'Сервис уақытша қолжетімсіз. Интернетті тексеріп, қайта көріңіз.',
          );
        }
        return t(
          'Не удалось выполнить запрос. Проверьте соединение и повторите действие.',
          'Сұрауды орындау мүмкін болмады. Байланысты тексеріп, әрекетті қайталаңыз.',
        );
    }
  }

  final text = error.toString();
  final lowerText = text.toLowerCase();
  if (lowerText.contains('corelocation') ||
      lowerText.contains('kclerror') ||
      lowerText.contains('locationunknown') ||
      lowerText.contains('location unknown')) {
    return t(
      'Не удалось определить GPS. Введите адрес или выберите точку на карте.',
      'GPS анықталмады. Мекенжайды енгізіңіз немесе картадан нүкте таңдаңыз.',
    );
  }
  if (text.contains('FormatException')) {
    return t('Некорректный формат данных.', 'Деректер форматы қате.');
  }
  return t(
    'Не удалось выполнить действие. Проверьте данные и повторите попытку.',
    'Әрекетті орындау мүмкін болмады. Деректерді тексеріп, қайта көріңіз.',
  );
}

String errorMessageRu(Object error) {
  return errorMessage(error);
}

String? _translateServerMessage(String? message) {
  if (message == null || message.trim().isEmpty) return null;
  final m = message.trim();
  final lower = m.toLowerCase();
  String t(String russianText, String kazakhText) {
    return LocalizationService.translate(russianText, kazakhText);
  }

  if (lower.contains('не удалось построить маршрут по дорогам')) {
    return t('Не удалось построить маршрут по дорогам. Повторите попытку.',
        'Жол бойымен бағыт құру мүмкін болмады. Қайта көріңіз.');
  }
  if (lower.contains('insufficient bonus balance')) {
    return t(
      'Недостаточно бонусов для оплаты поездки. Выберите наличные или перевод.',
      'Жолақысын төлеуге бонустар жеткіліксіз. Қолма-қол немесе аударымды таңдаңыз.',
    );
  }
  if (lower.contains('unable to calculate order price')) {
    return t(
      'Не удалось рассчитать стоимость. Уточните адреса и повторите расчёт.',
      'Құнын есептеу мүмкін болмады. Мекенжайларды нақтылап, қайта есептеңіз.',
    );
  }
  if (lower.contains('vehicle class is required')) {
    return t('Выберите класс автомобиля.', 'Көлік класын таңдаңыз.');
  }
  if (lower.contains('phone already registered')) {
    return t('Этот номер уже зарегистрирован.', 'Бұл нөмір тіркеліп қойған.');
  }
  if (lower.contains('invalid credentials')) {
    return t(
      'Неверный номер телефона или пароль.',
      'Телефон нөмірі немесе құпия сөз қате.',
    );
  }
  if (lower.contains('authentication session expired') ||
      lower.contains('session expired') ||
      lower.contains('refresh expired') ||
      lower.contains('token expired') ||
      lower.contains('jwt expired')) {
    return t(
      'Сессия истекла. Войдите в приложение заново.',
      'Сессия аяқталды. Қайта кіріңіз.',
    );
  }
  if (lower.contains('admin access required')) {
    return t(
      'Доступ только для администратора.',
      'Қолжетімділік тек әкімшіге арналған.',
    );
  }
  if (lower.contains('driver profile not found')) {
    return t('Профиль водителя не найден.', 'Жүргізуші профилі табылмады.');
  }
  if (lower.contains('driver profile not approved')) {
    return t(
      'Профиль водителя еще не одобрен.',
      'Жүргізуші профилі әлі мақұлданбаған.',
    );
  }
  if (lower.contains('order not available')) {
    return t('Заказ недоступен.', 'Тапсырыс қолжетімсіз.');
  }
  if (lower.contains('invalid status transition') ||
      lower.contains('invalid intercity request status transition')) {
    return t(
      'Статус заказа уже изменился. Обновите экран и повторите действие.',
      'Тапсырыс күйі өзгерді. Экранды жаңартып, әрекетті қайталаңыз.',
    );
  }
  if (lower.contains('invalid intercity request status')) {
    return t(
      'Нельзя выполнить это действие для текущего статуса заявки.',
      'Өтінімнің ағымдағы күйінде бұл әрекетті орындау мүмкін емес.',
    );
  }
  if (lower.contains('driver temporarily blocked due to low activity')) {
    return t(
      'Доступ к заказам временно ограничен из-за низкой активности.',
      'Белсенділік төмен болғандықтан тапсырыстар уақытша шектелді.',
    );
  }
  if (lower.contains('driver activity is zero')) {
    return t(
      'Активность водителя равна нулю. Обратитесь в поддержку или дождитесь восстановления доступа.',
      'Жүргізуші белсенділігі нөл. Қолдау қызметіне хабарласыңыз немесе қолжетімділіктің қалпына келуін күтіңіз.',
    );
  }
  if (lower.contains('для аукциона отправьте') || lower.contains('auction')) {
    return t(
      'Для аукционного заказа нужно отправить свою цену.',
      'Аукцион тапсырысы үшін өз бағаңызды жіберіңіз.',
    );
  }
  if (lower.contains('request is no longer open')) {
    return t(
      'Заявка уже недоступна. Обновите список заказов.',
      'Өтінім енді қолжетімсіз. Тапсырыстар тізімін жаңартыңыз.',
    );
  }
  if (lower.contains('driver is not online')) {
    return t(
      'Включите статус "Онлайн" для получения заказов.',
      'Тапсырыс алу үшін "Онлайн" күйін қосыңыз.',
    );
  }
  if (lower.contains('invalid recipient phone')) {
    return t(
      'Введите корректный номер получателя.',
      'Алушының дұрыс нөмірін енгізіңіз.',
    );
  }
  if (lower.contains('recipient not found')) {
    return t(
      'Пользователь с таким номером не найден.',
      'Мұндай нөмірі бар пайдаланушы табылмады.',
    );
  }
  if (lower.contains('passengers cannot top up balance')) {
    return t(
      'Пополнение счёта недоступно.',
      'Шотты толықтыру қолжетімсіз.',
    );
  }
  if (lower.contains('insufficient funds')) {
    return t(
      'Недостаточно средств.',
      'Қаражат жеткіліксіз.',
    );
  }
  if (lower.contains('wallet not found')) {
    return t(
      'Кошелёк не найден. Попробуйте выйти и войти заново.',
      'Әмиян табылмады. Қайта кіріп көріңіз.',
    );
  }
  if (lower.contains('card number is required')) {
    return t(
      'Введите корректный номер карты для вывода.',
      'Шығару үшін дұрыс карта нөмірін енгізіңіз.',
    );
  }
  if (lower.contains('amount must be greater than 0')) {
    return t(
      'Введите сумму больше нуля.',
      'Нөлден үлкен соманы енгізіңіз.',
    );
  }
  if (lower.contains('minimum payout amount is')) {
    return t(
      'Сумма вывода меньше минимально допустимой.',
      'Шығару сомасы ең төменгі мөлшерден аз.',
    );
  }
  if (lower.contains('order must be completed before rating')) {
    return t(
      'Оценить водителя можно только после завершения поездки.',
      'Жүргізушіні сапар аяқталғаннан кейін ғана бағалауға болады.',
    );
  }
  if (lower.contains('driver rating already submitted')) {
    return t(
      'Вы уже оценили этого водителя.',
      'Сіз бұл жүргізушіні бұрын бағалағансыз.',
    );
  }
  if (lower.contains('passenger rating already submitted')) {
    return t(
      'Оценка пассажиру уже отправлена.',
      'Жолаушыға баға әлдеқашан жіберілген.',
    );
  }
  if (lower.contains('driver not assigned for this order')) {
    return t(
      'У этого заказа нет назначенного водителя, поэтому оценка недоступна.',
      'Бұл тапсырысқа жүргізуші тағайындалмаған, сондықтан бағалау қолжетімсіз.',
    );
  }
  if (lower.contains(
      'password reset is disabled until a verified recovery flow is configured')) {
    return t(
      'Восстановление пароля временно недоступно, пока не настроено подтверждение личности.',
      'Тұлғаны растау бапталмағанша, құпия сөзді қалпына келтіру уақытша қолжетімсіз.',
    );
  }
  if (lower.contains('cityId is required') ||
      lower.contains('cityid is required')) {
    return t('Не выбран город.', 'Қала таңдалмаған.');
  }
  if (lower.contains('lat must be a number') ||
      lower.contains('lng must be a number') ||
      lower.contains('latitude') ||
      lower.contains('longitude')) {
    return t(
      'Не удалось передать местоположение. Нажмите кнопку геолокации и попробуйте снова.',
      'Орналасқан жерді жіберу мүмкін болмады. Геолокация батырмасын басып, қайта көріңіз.',
    );
  }
  if (lower.contains('isonline must be a boolean')) {
    return t(
      'Не удалось изменить статус онлайн. Обновите страницу и попробуйте снова.',
      'Онлайн күйін өзгерту мүмкін болмады. Бетті жаңартып, қайта көріңіз.',
    );
  }
  if (lower.contains('онлайн-платёж временно недоступен') ||
      lower.contains('онлайн-платеж временно недоступен')) {
    return t(
      'Онлайн-платёж временно недоступен. Попробуйте позже.',
      'Онлайн төлем уақытша қолжетімсіз. Кейінірек қайталап көріңіз.',
    );
  }
  if (lower.contains('ссылка на онлайн-оплату не была возвращена')) {
    return t(
      'Не удалось создать ссылку на онлайн-оплату. Попробуйте позже.',
      'Онлайн төлем сілтемесін жасау мүмкін болмады. Кейінірек қайталап көріңіз.',
    );
  }
  if (lower.contains(
      'notification module is unavailable until database migrations are applied')) {
    return t(
      'Модуль уведомлений временно недоступен, пока не применены миграции базы данных.',
      'Дерекқор миграциялары қолданылғанша, хабарландыру модулі уақытша қолжетімсіз.',
    );
  }
  if (lower.contains(
      'payout module is unavailable until database migrations are applied')) {
    return t(
      'Модуль вывода временно недоступен, пока не применены миграции базы данных.',
      'Дерекқор миграциялары қолданылғанша, ақша шығару модулі уақытша қолжетімсіз.',
    );
  }

  return null;
}

String? _safeServerMessage(String? message) {
  if (message == null) return null;
  final text = message.trim();
  if (text.isEmpty) return null;
  final lower = text.toLowerCase();
  if (lower == 'bad request' || lower.contains('exception')) return null;
  if (lower.contains('must be') || lower.contains('should not')) return null;
  return text;
}

String? _extractServerMessage(dynamic data) {
  if (data == null) return null;
  if (data is String && data.trim().isNotEmpty) return data.trim();
  if (data is Map) {
    final message = data['message'];
    if (message is String && message.trim().isNotEmpty) return message.trim();
    if (message is List && message.isNotEmpty) {
      final joined = message.map((e) => e.toString()).join(', ').trim();
      if (joined.isNotEmpty) return joined;
    }
    final error = data['error'];
    if (error is String && error.trim().isNotEmpty) return error.trim();
  }
  return null;
}
