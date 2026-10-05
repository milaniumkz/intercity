import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_controller.dart';

class DriverBottomNav extends StatelessWidget {
  const DriverBottomNav({
    super.key,
    required this.currentIndex,
  });

  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF14111F) : Colors.white;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, bottomInset + 12),
        child: Container(
          height: 74,
          decoration: BoxDecoration(
            color: bg.withValues(alpha: isDark ? 0.94 : 0.98),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: AppTheme.secondaryColor.withValues(alpha: 0.14),
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.36)
                    : AppTheme.primaryColor.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              _DriverNavItem(
                index: 0,
                currentIndex: currentIndex,
                icon: Icons.local_taxi_outlined,
                selectedIcon: Icons.local_taxi_rounded,
                label: 'Главная',
                onTap: () => _go(context, 0),
              ),
              _DriverNavItem(
                index: 1,
                currentIndex: currentIndex,
                icon: Icons.alt_route_outlined,
                selectedIcon: Icons.alt_route_rounded,
                label: 'Заявки',
                onTap: () => _go(context, 1),
              ),
              _DriverNavItem(
                index: 2,
                currentIndex: currentIndex,
                icon: Icons.account_balance_wallet_outlined,
                selectedIcon: Icons.account_balance_wallet_rounded,
                label: 'Кошелёк',
                onTap: () => _go(context, 2),
              ),
              _DriverNavItem(
                index: 3,
                currentIndex: currentIndex,
                icon: Icons.verified_user_outlined,
                selectedIcon: Icons.verified_user_rounded,
                label: 'Проверка',
                onTap: () => _go(context, 3),
              ),
              _DriverNavItem(
                index: 4,
                currentIndex: currentIndex,
                icon: Icons.person_outline_rounded,
                selectedIcon: Icons.person_rounded,
                label: 'Профиль',
                onTap: () => _go(context, 4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _go(BuildContext context, int index) {
    if (index == currentIndex) return;
    switch (index) {
      case 0:
        context.go('/driver/home');
        break;
      case 1:
        context.go('/driver/trip-create');
        break;
      case 2:
        context.go('/driver/wallet');
        break;
      case 3:
        context.go('/driver/verification');
        break;
      case 4:
        context.go('/driver/profile');
        break;
    }
  }
}

class _DriverNavItem extends StatelessWidget {
  const _DriverNavItem({
    required this.index,
    required this.currentIndex,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });

  final int index;
  final int currentIndex;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selected = index == currentIndex;
    final idleColor =
        isDark ? Colors.white.withValues(alpha: 0.68) : const Color(0xFF7D7892);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: selected
                ? LinearGradient(
                    colors: [
                      AppTheme.primaryColor.withValues(alpha: 0.16),
                      AppTheme.secondaryColor.withValues(alpha: 0.10),
                    ],
                  )
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 42 : 28,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: selected
                      ? const LinearGradient(
                          colors: [
                            AppTheme.secondaryColor,
                            AppTheme.primaryColor,
                          ],
                        )
                      : null,
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color:
                                AppTheme.primaryColor.withValues(alpha: 0.22),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  selected ? selectedIcon : icon,
                  color: selected ? Colors.white : idleColor,
                  size: selected ? 19 : 23,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? AppTheme.primaryColor : idleColor,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
