import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/navigation_back.dart';
import '../../../core/widgets/ic_premium.dart';

class RegisterRoleChoiceScreen extends StatelessWidget {
  const RegisterRoleChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ref = GoRouterState.of(context).uri.queryParameters['ref'];
    final refQuery = (ref ?? '').isEmpty ? '' : '?ref=$ref';
    return Scaffold(
      body: ICPremiumBackground(
        padding: EdgeInsets.zero,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _CircleBackButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: () => goBackOr(context, fallback: '/login'),
                      ),
                    ),
                    const Spacer(flex: 2),
                    Text(
                      'Кто вы?',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                        fontSize: 31,
                        height: 1.08,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Выберите роль, чтобы мы могли подобрать для вас лучший опыт.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 34),
                    _RoleChoiceCard(
                      title: 'Пассажир',
                      subtitle: 'Ищу поездку',
                      icon: Icons.person_rounded,
                      selected: true,
                      onTap: () => context.push('/register/passenger$refQuery'),
                    ),
                    const SizedBox(height: 16),
                    _RoleChoiceCard(
                      title: 'Водитель',
                      subtitle: 'Хочу выполнять поездки',
                      icon: Icons.directions_car_filled_rounded,
                      onTap: () => context.push('/register/driver$refQuery'),
                    ),
                    const Spacer(flex: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Вы сможете изменить роль в настройках позже.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleChoiceCard extends StatelessWidget {
  const _RoleChoiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ICCard(
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: selected
                  ? const LinearGradient(
                      colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                    )
                  : null,
              color:
                  selected ? null : theme.colorScheme.surfaceContainerHighest,
              border: Border.all(
                color: selected
                    ? Colors.white.withValues(alpha: 0.22)
                    : AppTheme.primaryColor.withValues(alpha: 0.12),
              ),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x407C2DFF),
                        blurRadius: 22,
                        offset: Offset(0, 12),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              color: selected ? Colors.white : AppTheme.deepViolet,
              size: 30,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  selected
                      ? 'Заказывать город, межгород и доставку.'
                      : 'Принимать заявки, откликаться ценой и управлять балансом.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? AppTheme.primaryColor.withValues(alpha: 0.12)
                  : theme.colorScheme.surfaceContainerHighest,
            ),
            child: Icon(
              Icons.chevron_right_rounded,
              color:
                  selected ? AppTheme.primaryColor : theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleBackButton extends StatelessWidget {
  const _CircleBackButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.54),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}
