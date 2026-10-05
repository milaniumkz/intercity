import 'localization_service.dart';

bool isApprovedDriverStatus(String? status) {
  final s = (status ?? '').toUpperCase();
  return s == 'ACTIVE' || s == 'APPROVED';
}

String driverAccessMessageRu(String? status, {String? rejectionReason}) {
  final s = (status ?? '').toUpperCase();
  if (s.isEmpty) {
    return LocalizationService.translate(
      'Профиль водителя не найден. Сначала зарегистрируйтесь как водитель.',
      'Жүргізуші профилі табылмады. Алдымен жүргізуші ретінде тіркеліңіз.',
    );
  }
  if (s == 'ACTIVE' || s == 'APPROVED') {
    return LocalizationService.translate(
      'Профиль водителя одобрен. Вход в режим водителя доступен.',
      'Жүргізуші профилі мақұлданды. Жүргізуші режиміне кіруге болады.',
    );
  }
  if (s == 'PENDING') {
    return LocalizationService.translate(
      'Аккаунт водителя на проверке. Пока проверка идет, вы остаетесь в режиме пассажира.',
      'Жүргізуші аккаунты тексерілуде. Тексеру жүріп жатқанда жолаушы режимінде қаласыз.',
    );
  }
  if (s == 'REJECTED') {
    final reason = rejectionReason?.trim();
    final suffix = reason == null || reason.isEmpty ? '' : '\nПричина: $reason';
    return LocalizationService.translate(
      'Профиль водителя отклонен. Заполните проверку повторно.$suffix',
      'Жүргізуші профилі қабылданбады. Тексеруді қайта толтырыңыз.$suffix',
    );
  }
  return LocalizationService.translate(
    'Вход в режим водителя недоступен. Статус профиля: $s',
    'Жүргізуші режиміне кіру қолжетімсіз. Профиль күйі: $s',
  );
}
