import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/app_preferences.dart';

enum AppThemeMode { light, dark, system }

final themeControllerProvider =
    StateNotifierProvider<ThemeController, AppThemeMode>(
  (ref) => ThemeController(),
);

class ThemeController extends StateNotifier<AppThemeMode> {
  ThemeController() : super(AppThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final saved = await AppPreferences.getThemeMode();
    if (saved == null || saved.isEmpty) return;
    switch (saved) {
      case 'light':
        state = AppThemeMode.light;
        break;
      case 'dark':
        state = AppThemeMode.dark;
        break;
      default:
        state = AppThemeMode.system;
        break;
    }
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = mode;
    await AppPreferences.setThemeMode(mode.name);
  }

  ThemeMode get flutterThemeMode {
    switch (state) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }
}

class AppTheme {
  static const Color primaryColor = Color(0xFF7C2DFF);
  static const Color secondaryColor = Color(0xFF9D5CFF);
  static const Color deepViolet = Color(0xFF3B0A6D);
  static const Color lightBackground = Color(0xFFF8F6FF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceSoft = Color(0xFFEFE9FF);
  static const Color darkBackground = Color(0xFF090814);
  static const Color darkSurface = Color(0xFF11101D);
  static const Color darkSurfaceSoft = Color(0xFF201735);

  static final ThemeData lightTheme = _buildTheme(
    colorScheme: const ColorScheme.light(
      primary: primaryColor,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFEFE3FF),
      onPrimaryContainer: deepViolet,
      secondary: secondaryColor,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFEFE9FF),
      onSecondaryContainer: deepViolet,
      error: Color(0xFFE24A5A),
      onError: Colors.white,
      surface: lightSurface,
      onSurface: Color(0xFF111322),
      onSurfaceVariant: Color(0xFF5D6073),
      outline: Color(0xFFE3DCF3),
      shadow: Color(0x1A2C174C),
    ),
    scaffoldBackgroundColor: lightBackground,
    surfaceContainer: lightSurfaceSoft,
  );

  static final ThemeData darkTheme = _buildTheme(
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF8B35FF),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF2B1748),
      onPrimaryContainer: Color(0xFFF8F4FF),
      secondary: Color(0xFFB17AFF),
      onSecondary: Color(0xFF090814),
      secondaryContainer: Color(0xFF201735),
      onSecondaryContainer: Color(0xFFF8F4FF),
      error: Color(0xFFE24A5A),
      onError: Colors.white,
      surface: darkSurface,
      onSurface: Color(0xFFF8F4FF),
      onSurfaceVariant: Color(0xFFC9BFE0),
      outline: Color(0xFF2B2640),
      shadow: Color(0x66000000),
    ),
    scaffoldBackgroundColor: darkBackground,
    surfaceContainer: darkSurfaceSoft,
  );

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required Color scaffoldBackgroundColor,
    required Color surfaceContainer,
  }) {
    final isDark = colorScheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      cardColor: colorScheme.surface,
      dividerColor: colorScheme.outline.withValues(alpha: 0.6),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      textTheme: ThemeData(
        brightness: colorScheme.brightness,
        useMaterial3: true,
      ).textTheme.apply(
            fontFamily: 'Roboto',
            bodyColor: colorScheme.onSurface,
            displayColor: colorScheme.onSurface,
          ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.45)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainer,
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor:
            isDark ? const Color(0xFF171426) : const Color(0xFF111322),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: colorScheme.primary,
        headerForegroundColor: colorScheme.onPrimary,
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.onPrimary
              : colorScheme.onSurface,
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.primary
              : Colors.transparent,
        ),
        todayForegroundColor: WidgetStatePropertyAll(colorScheme.primary),
        todayBorder: BorderSide(color: colorScheme.primary, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        cancelButtonStyle: TextButton.styleFrom(
          foregroundColor: colorScheme.onSurfaceVariant,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: colorScheme.surface,
        hourMinuteColor: surfaceContainer,
        hourMinuteTextColor: colorScheme.onSurface,
        dialBackgroundColor: surfaceContainer,
        dialHandColor: colorScheme.primary,
        dialTextColor: colorScheme.onSurface,
        entryModeIconColor: colorScheme.primary,
        dayPeriodColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.primary
              : surfaceContainer,
        ),
        dayPeriodTextColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colorScheme.onPrimary
              : colorScheme.onSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        cancelButtonStyle: TextButton.styleFrom(
          foregroundColor: colorScheme.onSurfaceVariant,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceContainer,
        selectedColor: colorScheme.primaryContainer,
        labelStyle: TextStyle(color: colorScheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: colorScheme.outline),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: colorScheme.surface.withValues(alpha: 0.98),
        indicatorColor: colorScheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        elevation: isDark ? 0 : 12,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
