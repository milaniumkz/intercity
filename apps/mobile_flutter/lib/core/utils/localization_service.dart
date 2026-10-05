import 'package:flutter/widgets.dart';

import '../services/app_preferences.dart';

enum AppLanguage { russian, kazakh }

class LocalizationService {
  static AppLanguage currentLanguage = AppLanguage.russian;
  static final ValueNotifier<AppLanguage> notifier = ValueNotifier(
    AppLanguage.russian,
  );

  static AppLanguage resolveInitialLanguage({
    String? storedLanguage,
    bool hasExplicitSelection = false,
  }) {
    if (hasExplicitSelection && storedLanguage == AppLanguage.kazakh.name) {
      return AppLanguage.kazakh;
    }
    return AppLanguage.russian;
  }

  static Future<void> init() async {
    String? storedLanguage;
    bool hasExplicitSelection = false;
    try {
      storedLanguage = await AppPreferences.getLanguage();
      hasExplicitSelection =
          await AppPreferences.getLanguageExplicitSelection();
    } catch (_) {
      storedLanguage = null;
      hasExplicitSelection = false;
    }
    currentLanguage = resolveInitialLanguage(
      storedLanguage: storedLanguage,
      hasExplicitSelection: hasExplicitSelection,
    );
    notifier.value = currentLanguage;
    try {
      await AppPreferences.setLanguage(currentLanguage.name);
      if (!hasExplicitSelection) {
        await AppPreferences.setLanguageExplicitSelection(false);
      }
    } catch (_) {
      // Ignore persistence failures during startup.
    }
  }

  static Future<void> setLanguage(AppLanguage language) async {
    currentLanguage = language;
    notifier.value = language;
    try {
      await AppPreferences.setLanguage(language.name);
      await AppPreferences.setLanguageExplicitSelection(true);
    } catch (_) {
      // Keep language switching functional even if persistence is unavailable.
    }
  }

  static String translate(String russianText, String kazakhText) {
    return currentLanguage == AppLanguage.kazakh ? kazakhText : russianText;
  }

  static String get appName => translate('INTERCITY', 'INTERCITY');
  static String get login => translate('Войти', 'Кіру');
  static String get register => translate('Регистрация', 'Тіркелу');
  static String get phone => translate('Телефон', 'Телефон');
  static String get password => translate('Пароль', 'Құпия сөз');
  static String get name => translate('Имя', 'Аты');
  static String get noAccount => translate('Нет аккаунта?', 'Аккаунт жоқ па?');
  static String get hasAccount => translate('Есть аккаунт?', 'Аккаунт бар ма?');
  static String get city => translate('ГОРОД', 'ҚАЛА');
  static String get intercity => translate('INTERCITY', 'INTERCITY');
  static String get cargo => translate('ГРУЗОВЫЕ', 'ЖҮК');
  static String get delivery => translate('ДОСТАВКА', 'ЖЕТКІЗУ');
  static String get from => translate('Откуда', 'Қайдан');
  static String get to => translate('Куда', 'Қайда');
  static String get createOrder => translate('Заказать', 'Тапсырыс беру');
  static String get profile => translate('Профиль', 'Профиль');
  static String get wallet => translate('Кошелёк', 'Әмияш');
  static String get orders => translate('Заказы', 'Тапсырыстар');
  static String get settings => translate('Настройки', 'Баптаулар');
}
