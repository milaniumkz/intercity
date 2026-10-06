import 'dart:convert';
import '../constants/app_constants.dart';
import 'secure_store.dart';

class AppPreferences {
  static final SecureStore _storage =
      createSecureStore(namespace: AppConstants.secureStoreNamespace);

  static Future<void> setLastAppMode(String mode) {
    return _storage.write(AppConstants.lastAppModeKey, mode);
  }

  static Future<String?> getLastAppMode() {
    return _storage.read(AppConstants.lastAppModeKey);
  }

  static Future<void> clearLastAppMode() {
    return _storage.delete(AppConstants.lastAppModeKey);
  }

  static Future<void> setThemeMode(String mode) {
    return _storage.write(AppConstants.themeKey, mode);
  }

  static Future<String?> getThemeMode() {
    return _storage.read(AppConstants.themeKey);
  }

  static Future<void> setLanguage(String language) {
    return _storage.write(AppConstants.languageKey, language);
  }

  static Future<String?> getLanguage() {
    return _storage.read(AppConstants.languageKey);
  }

  static Future<void> setLanguageExplicitSelection(bool selected) {
    return _storage.write(
      AppConstants.languageExplicitSelectionKey,
      selected ? '1' : '0',
    );
  }

  static Future<bool> getLanguageExplicitSelection() async {
    return (await _storage.read(AppConstants.languageExplicitSelectionKey)) ==
        '1';
  }

  static Future<void> setOrderCity(Map<String, dynamic> city) =>
      _storage.write('order_city_selection', jsonEncode(city));

  static Future<Map<String, dynamic>?> getOrderCity() async {
    final value = await _storage.read('order_city_selection');
    if (value == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(value) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearOrderCity() =>
      _storage.delete('order_city_selection');

  static Future<void> setCurrentCityId(String cityId) {
    return _storage.write(AppConstants.currentCityIdKey, cityId);
  }

  static Future<String?> getCurrentCityId() {
    return _storage.read(AppConstants.currentCityIdKey);
  }

  static Future<void> clearCurrentCityId() {
    return _storage.delete(AppConstants.currentCityIdKey);
  }

  static Future<void> setCurrentCityName(String cityName) {
    return _storage.write(AppConstants.currentCityNameKey, cityName);
  }

  static Future<String?> getCurrentCityName() {
    return _storage.read(AppConstants.currentCityNameKey);
  }

  static Future<void> clearCurrentCityName() {
    return _storage.delete(AppConstants.currentCityNameKey);
  }

  static Future<void> setOrderDraft(String draftJson) {
    return _storage.write(AppConstants.orderDraftKey, draftJson);
  }

  static Future<String?> getOrderDraft() {
    return _storage.read(AppConstants.orderDraftKey);
  }

  static Future<void> clearOrderDraft() {
    return _storage.delete(AppConstants.orderDraftKey);
  }

  static Future<void> setPendingReferralCode(String code) {
    return _storage.write(AppConstants.pendingReferralCodeKey, code);
  }

  static Future<String?> getPendingReferralCode() {
    return _storage.read(AppConstants.pendingReferralCodeKey);
  }

  static Future<void> clearPendingReferralCode() {
    return _storage.delete(AppConstants.pendingReferralCodeKey);
  }
}
