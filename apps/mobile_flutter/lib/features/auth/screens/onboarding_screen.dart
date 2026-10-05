import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/route_query.dart';
import '../../../core/widgets/ic_premium.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, this.routeStage});

  final String? routeStage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIntercity =
        routeStage == 'intercity' || routeHas(context, 'intercity=1');
    final isDark =
        theme.brightness == Brightness.dark || routeHas(context, 'dark=1');
    final title =
        isIntercity ? 'Межгород без\nлишних звонков' : 'Поездки\nпо городу';
    final text = isIntercity
        ? 'Междугородние поездки по фиксированной цене. Комфорт на дальних расстояниях.'
        : 'Быстрые и комфортные поездки по вашему городу. Подача за несколько минут.';
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF090814) : theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.go('/register'),
                  child: Text(
                    'Пропустить',
                    style: TextStyle(
                      color: isDark
                          ? const Color(0xFFDED1FF)
                          : AppTheme.primaryColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: isDark ? Colors.white : const Color(0xFF141326),
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                  fontSize: 31,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? const Color(0xFFC9C0DB)
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: CustomPaint(
                    painter: _OnboardingMapPainter(
                      intercity: isIntercity,
                      dark: isDark,
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 34,
                          right: 34,
                          bottom: isIntercity ? 130 : 96,
                          child: Container(
                            height: 70,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(40),
                              gradient: LinearGradient(
                                colors: [
                                  isDark
                                      ? const Color(0xFF2D2542)
                                      : Colors.white.withValues(alpha: 0.96),
                                  isDark
                                      ? const Color(0xFF191426)
                                      : const Color(0xFFEFE7FF),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryColor
                                      .withValues(alpha: 0.18),
                                  blurRadius: 24,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 58,
                          right: 58,
                          bottom: isIntercity ? 150 : 116,
                          child: Icon(
                            Icons.directions_car_filled_rounded,
                            color: isDark
                                ? const Color(0xFFE6D9FF)
                                : const Color(0xFF181629),
                            size: 112,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Dot(active: !isIntercity),
                  const SizedBox(width: 8),
                  _Dot(active: isIntercity),
                  const SizedBox(width: 8),
                  const _Dot(active: false),
                ],
              ),
              const SizedBox(height: 18),
              ICGradientButton(
                label: 'Далее',
                icon: Icons.arrow_forward_rounded,
                onPressed: () => isIntercity
                    ? context.go('/register')
                    : context.go('/onboarding/intercity'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: active ? 10 : 8,
      height: active ? 10 : 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppTheme.primaryColor : const Color(0xFFD8CFEA),
      ),
    );
  }
}

class _OnboardingMapPainter extends CustomPainter {
  const _OnboardingMapPainter({
    required this.intercity,
    required this.dark,
  });

  final bool intercity;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = LinearGradient(
        colors: dark
            ? const [Color(0xFF171126), Color(0xFF0B0817)]
            : const [Color(0xFFFBFAFF), Color(0xFFEFE8FF)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final grid = Paint()
      ..color = (dark ? AppTheme.primaryColor : Colors.white)
          .withValues(alpha: dark ? 0.13 : 0.95)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (var x = -size.width; x < size.width * 1.7; x += 36) {
      canvas.drawLine(Offset(x.toDouble(), 0),
          Offset(x + size.width * 0.58, size.height), grid);
    }
    for (var y = 18; y < size.height; y += 42) {
      canvas.drawLine(
          Offset(0, y.toDouble()), Offset(size.width, y - 26), grid);
    }

    final route = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFB66CFF), AppTheme.primaryColor],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width * 0.22, size.height * 0.28)
      ..cubicTo(
        size.width * 0.34,
        size.height * 0.38,
        size.width * 0.48,
        size.height * 0.26,
        size.width * 0.58,
        size.height * 0.40,
      )
      ..cubicTo(
        size.width * 0.70,
        size.height * 0.56,
        size.width * 0.52,
        size.height * 0.64,
        size.width * 0.78,
        size.height * 0.76,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppTheme.primaryColor.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(path, route);

    final pinPaint = Paint()..color = AppTheme.primaryColor;
    canvas.drawCircle(
        Offset(size.width * 0.78, size.height * 0.76), 9, pinPaint);
    if (intercity) {
      canvas.drawCircle(
          Offset(size.width * 0.22, size.height * 0.28), 9, pinPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
