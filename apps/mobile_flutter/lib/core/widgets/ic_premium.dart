import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';

class ICPremiumBackground extends StatelessWidget {
  const ICPremiumBackground({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF080713), Color(0xFF11101F)]
              : const [Color(0xFFFBFAFF), Color(0xFFF6F2FF)],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ICPremiumBackgroundPainter(isDark: isDark),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

class _ICPremiumBackgroundPainter extends CustomPainter {
  const _ICPremiumBackgroundPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = (isDark ? Colors.white : AppTheme.primaryColor)
          .withValues(alpha: isDark ? 0.035 : 0.045)
      ..strokeWidth = 1;
    for (var y = 86.0; y < size.height; y += 132) {
      canvas.drawLine(Offset(24, y), Offset(size.width - 24, y), line);
    }
    final wash = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppTheme.primaryColor.withValues(alpha: isDark ? 0.10 : 0.06),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.55));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.55), wash);
  }

  @override
  bool shouldRepaint(covariant _ICPremiumBackgroundPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

class ICLogoMark extends StatelessWidget {
  const ICLogoMark({
    super.key,
    this.size = 56,
    this.dark = true,
  });

  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          'assets/branding/adaptive-icon.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class ICBrandHeader extends StatelessWidget {
  const ICBrandHeader({
    super.key,
    this.compact = false,
    this.subtitle = 'Премиальные поездки по городу и межгороду',
  });

  final bool compact;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logoSize = compact ? 42.0 : 56.0;
    return Row(
      children: [
        ICLogoMark(size: logoSize),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            'InterCity',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        if (!compact) ...[
          Container(
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 18),
            width: 1,
            color: theme.colorScheme.outline,
          ),
          Expanded(
            child: Text(
              subtitle.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
                height: 1.25,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class ICCard extends StatelessWidget {
  const ICCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.selected = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outline.withValues(alpha: isDark ? 0.9 : 0.75);
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171426) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
        boxShadow: isDark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x142C174C),
                  blurRadius: 22,
                  offset: Offset(0, 10),
                ),
              ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: card,
    );
  }
}

class ICGradientButton extends StatelessWidget {
  const ICGradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1 : 0.48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x407C2DFF),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (icon != null) ...[
                      const SizedBox(width: 10),
                      Icon(icon, color: Colors.white, size: 20),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class ICPremiumTextButton extends StatelessWidget {
  const ICPremiumTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.primary,
        disabledForegroundColor:
            theme.colorScheme.onSurface.withValues(alpha: 0.38),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors: enabled
              ? const [AppTheme.secondaryColor, AppTheme.primaryColor]
              : [
                  theme.colorScheme.onSurface.withValues(alpha: 0.38),
                  theme.colorScheme.onSurface.withValues(alpha: 0.38),
                ],
        ).createShader(bounds),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ICOptionTile extends StatelessWidget {
  const ICOptionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
    this.selected = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ICCard(
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: selected
                  ? const LinearGradient(
                      colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                    )
                  : null,
              color: selected ? null : theme.colorScheme.primaryContainer,
            ),
            child: Icon(
              icon,
              color: selected
                  ? Colors.white
                  : theme.colorScheme.onPrimaryContainer,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: theme.colorScheme.primary),
        ],
      ),
    );
  }
}

class ICPremiumBalanceCard extends StatelessWidget {
  const ICPremiumBalanceCard({
    super.key,
    required this.caption,
    required this.amount,
    required this.note,
    required this.badge,
  });

  final String caption;
  final String amount;
  final String note;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x407C2DFF),
            blurRadius: 26,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -8,
            bottom: -16,
            child: _ICCoinStack(),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      caption,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      amount,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 230),
                      child: Text(
                        note,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ICPremiumRouteHero extends StatelessWidget {
  const ICPremiumRouteHero({
    super.key,
    this.title = 'InterCity',
    this.subtitle = 'Город • Межгород • Такси',
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(22, compact ? 18 : 24, 22, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF120B2B), Color(0xFF3B0A6D)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x503D1B7A),
            blurRadius: 30,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ICLogoMark(size: compact ? 64 : 76),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 24 : 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: compact ? 18 : 26),
          Row(
            children: [
              const _HeroRouteDot(icon: Icons.location_on_rounded),
              Expanded(
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                    ),
                  ),
                ),
              ),
              const _HeroRouteDot(icon: Icons.local_taxi_rounded),
            ],
          ),
        ],
      ),
    );
  }
}

class ICPremiumEmptyState extends StatelessWidget {
  const ICPremiumEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ICCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.secondaryColor
                      .withValues(alpha: isDark ? 0.32 : 0.12),
                  AppTheme.primaryColor.withValues(alpha: isDark ? 0.24 : 0.08),
                ],
              ),
            ),
            child: Center(
              child: Container(
                width: 118,
                height: 118,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.white.withValues(alpha: 0.76),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            AppTheme.secondaryColor,
                            AppTheme.primaryColor,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppTheme.primaryColor.withValues(alpha: 0.26),
                            blurRadius: 22,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                    ),
                    Icon(icon, color: Colors.white, size: 38),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ICGradientButton(label: actionLabel!, onPressed: onAction),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class ICPremiumInfoBanner extends StatelessWidget {
  const ICPremiumInfoBanner({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.color = AppTheme.primaryColor,
  });

  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroRouteDot extends StatelessWidget {
  const _HeroRouteDot({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }
}

class _ICCoinStack extends StatelessWidget {
  const _ICCoinStack();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.42,
      child: SizedBox(
        width: 92,
        height: 72,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: List.generate(4, (index) {
            return Positioned(
              bottom: index * 10,
              child: Container(
                width: 74 - index * 5,
                height: 22,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.82),
                      Colors.white.withValues(alpha: 0.26),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
