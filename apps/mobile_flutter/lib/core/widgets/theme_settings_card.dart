import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/theme_controller.dart';
import '../utils/localization_service.dart';

class ThemeSettingsCard extends ConsumerWidget {
  const ThemeSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeControllerProvider);
    final controller = ref.read(themeControllerProvider.notifier);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    Widget option({
      required AppThemeMode value,
      required IconData icon,
      required String label,
      required List<Color> swatchColors,
    }) {
      final selected = mode == value;
      return Expanded(
        child: InkWell(
          onTap: () => controller.setThemeMode(value),
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            decoration: BoxDecoration(
              gradient: selected
                  ? const LinearGradient(
                      colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: selected ? null : colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? AppTheme.primaryColor.withValues(alpha: 0.28)
                    : AppTheme.secondaryColor.withValues(alpha: 0.14),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: swatchColors
                      .map(
                        (color) => Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 10),
                Icon(icon,
                    color: selected ? Colors.white : AppTheme.primaryColor),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? Colors.white : colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget languageOption({
      required AppLanguage value,
      required String label,
      required String subtitle,
    }) {
      return ValueListenableBuilder<AppLanguage>(
        valueListenable: LocalizationService.notifier,
        builder: (context, language, _) {
          final selected = language == value;
          return Expanded(
            child: InkWell(
              onTap: () => LocalizationService.setLanguage(value),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(
                          colors: [
                            AppTheme.secondaryColor,
                            AppTheme.primaryColor,
                          ],
                        )
                      : null,
                  color: selected ? null : colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected
                        ? AppTheme.primaryColor
                        : AppTheme.secondaryColor.withValues(alpha: 0.14),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? Colors.white.withValues(alpha: 0.18)
                            : AppTheme.primaryColor.withValues(alpha: 0.10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        label,
                        style: TextStyle(
                          color:
                              selected ? Colors.white : AppTheme.primaryColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          color:
                              selected ? Colors.white : colorScheme.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: selected
                          ? Colors.white
                          : colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    Widget preferenceRow({
      required IconData icon,
      required String title,
      required String value,
      required VoidCallback onTap,
    }) {
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFF8F6FF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTheme.secondaryColor.withValues(alpha: 0.10),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primaryColor.withValues(alpha: 0.10),
                  ),
                  child: Icon(icon, color: AppTheme.primaryColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      );
    }

    Future<void> showPreferenceDialog({
      required String title,
      required String message,
      required IconData icon,
    }) {
      return showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(icon, color: AppTheme.primaryColor),
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                LocalizationService.translate('Понятно', 'Түсінікті'),
              ),
            ),
          ],
        ),
      );
    }

    void openNotificationsInfo() {
      showPreferenceDialog(
        icon: Icons.notifications_active_outlined,
        title: LocalizationService.translate(
          'Уведомления',
          'Хабарландырулар',
        ),
        message: LocalizationService.translate(
          'Уведомления включаются автоматически после разрешения браузера или телефона. Они используются для новых заказов, статусов поездки, водителя и важных событий.',
          'Хабарландырулар браузер немесе телефон рұқсатынан кейін автоматты қосылады. Олар жаңа тапсырыстар, сапар күйлері, жүргізуші және маңызды оқиғалар үшін қолданылады.',
        ),
      );
    }

    void openSecurityInfo() {
      showPreferenceDialog(
        icon: Icons.security_rounded,
        title: LocalizationService.translate('Безопасность', 'Қауіпсіздік'),
        message: LocalizationService.translate(
          'Аккаунт защищён авторизацией по телефону и паролю. Для смены пароля используйте экран восстановления пароля при входе.',
          'Аккаунт телефон және құпиясөз арқылы қорғалған. Құпиясөзді өзгерту үшін кіру экранындағы қалпына келтіруді пайдаланыңыз.',
        ),
      );
    }

    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LocalizationService.notifier,
      builder: (context, _, __) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppTheme.secondaryColor.withValues(alpha: 0.14),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [
                              AppTheme.secondaryColor,
                              AppTheme.primaryColor,
                            ],
                          ),
                        ),
                        child:
                            const Icon(Icons.tune_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          LocalizationService.translate(
                            'Настройки',
                            'Баптаулар',
                          ),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    LocalizationService.translate(
                      'Предпочтения',
                      'Қалаулар',
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  preferenceRow(
                    icon: Icons.notifications_none_rounded,
                    title: LocalizationService.translate(
                      'Уведомления',
                      'Хабарландырулар',
                    ),
                    value: LocalizationService.translate(
                      'Заказы, статусы и важные события',
                      'Тапсырыстар, күйлер және маңызды оқиғалар',
                    ),
                    onTap: openNotificationsInfo,
                  ),
                  const SizedBox(height: 8),
                  preferenceRow(
                    icon: Icons.security_rounded,
                    title: LocalizationService.translate(
                      'Безопасность',
                      'Қауіпсіздік',
                    ),
                    value: LocalizationService.translate(
                      'Профиль, вход и защита аккаунта',
                      'Профиль, кіру және аккаунтты қорғау',
                    ),
                    onTap: openSecurityInfo,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    LocalizationService.translate(
                      'Язык приложения',
                      'Қолданба тілі',
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    LocalizationService.translate(
                      'Переключение влияет на ошибки, подсказки и основные системные тексты.',
                      'Ауысу қателерге, кеңестерге және негізгі жүйелік мәтіндерге әсер етеді.',
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : const Color(0xFFF8F6FF),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Row(
                      children: [
                        languageOption(
                          value: AppLanguage.russian,
                          label: 'RU',
                          subtitle: 'Русский',
                        ),
                        const SizedBox(width: 6),
                        languageOption(
                          value: AppLanguage.kazakh,
                          label: 'KZ',
                          subtitle: 'Қазақша',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    LocalizationService.translate(
                      'Тема приложения',
                      'Қолданба тақырыбы',
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    LocalizationService.translate(
                      'Светлая тема теперь использует яркие поверхности, тёмная — глубокий ночной контраст.',
                      'Ашық тақырып жарқын беттерді, ал қараңғы тақырып терең түнгі контрастты қолданады.',
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF090713)
                          : Colors.white.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      children: [
                        option(
                          value: AppThemeMode.light,
                          icon: Icons.light_mode_rounded,
                          label:
                              LocalizationService.translate('Светлая', 'Ашық'),
                          swatchColors: const [
                            AppTheme.lightBackground,
                            AppTheme.lightSurface,
                            Color(0xFF5B3FD6),
                          ],
                        ),
                        const SizedBox(width: 8),
                        option(
                          value: AppThemeMode.dark,
                          icon: Icons.dark_mode_rounded,
                          label: LocalizationService.translate(
                              'Тёмная', 'Қараңғы'),
                          swatchColors: const [
                            AppTheme.darkBackground,
                            AppTheme.darkSurface,
                            Color(0xFF9B87FF),
                          ],
                        ),
                        const SizedBox(width: 8),
                        option(
                          value: AppThemeMode.system,
                          icon: Icons.phone_iphone_rounded,
                          label: LocalizationService.translate(
                            'Системная',
                            'Жүйелік',
                          ),
                          swatchColors: const [
                            AppTheme.lightSurface,
                            AppTheme.darkSurface,
                            Color(0xFF2C9BEA),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
