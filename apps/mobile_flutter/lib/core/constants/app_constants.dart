import 'package:intercity_shared/intercity_shared.dart';

class AppConstants {
  static const String appName = 'INTERCITY';

  // API
  static String get baseUrl => IntercityApiConfig.normalize(
        const String.fromEnvironment(
          IntercityApiConfig.envKey,
          defaultValue: IntercityApiConfig.safePlaceholderBaseUrl,
        ),
      );

  // Storage Keys
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String apiBaseUrlKey = 'api_base_url';
  static const String userKey = 'user';
  static const String themeKey = 'theme_mode';
  static const String languageKey = 'language';
  static const String languageExplicitSelectionKey = 'language_explicit';
  static const String lastAppModeKey = 'last_app_mode';
  static const String currentCityIdKey = 'current_city_id';
  static const String currentCityNameKey = 'current_city_name';
  static const String orderDraftKey = 'order_draft';
  static const String pendingReferralCodeKey = 'pending_referral_code';
  static const String secureStoreNamespace = 'intercity.mobile.secure';
  static const String publicWebUrl = String.fromEnvironment(
    'INTERCITY_PUBLIC_WEB_URL',
    defaultValue: 'https://inter-city-pkzpps.web.app',
  );

  // Theme Colors
  static const int primaryColor = 0xFF7C2DFF;

  // Map
  static const String osmTileUrl =
      'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png';
  static const List<String> mapTileSubdomains = ['a', 'b', 'c'];
}
