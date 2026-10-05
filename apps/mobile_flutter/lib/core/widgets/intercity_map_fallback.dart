import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';

class IntercityMapFallback extends StatelessWidget {
  const IntercityMapFallback({super.key, this.dark});

  final bool? dark;

  @override
  Widget build(BuildContext context) {
    final isDark = dark ?? Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF080812), Color(0xFF151024)]
              : const [Color(0xFFFCFBFF), Color(0xFFF1ECFF)],
        ),
      ),
      child: CustomPaint(
        painter: _IntercityMapFallbackPainter(isDark: isDark),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _IntercityMapFallbackPainter extends CustomPainter {
  const _IntercityMapFallbackPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = (isDark ? const Color(0xFF6E55A8) : Colors.white)
          .withValues(alpha: isDark ? 0.20 : 0.92)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final majorRoadPaint = Paint()
      ..color = (isDark ? const Color(0xFF302A46) : const Color(0xFFE2DEF2))
          .withValues(alpha: isDark ? 0.74 : 0.92)
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (var x = -size.width; x < size.width * 1.8; x += 38) {
      canvas.drawLine(
        Offset(x.toDouble(), 0),
        Offset(x + size.height * 0.62, size.height),
        roadPaint,
      );
    }
    for (var y = 18.0; y < size.height; y += 42) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 30), roadPaint);
    }

    for (var i = 0; i < 5; i++) {
      final y = size.height * (0.18 + i * 0.16);
      final p = ui.Path()
        ..moveTo(-20, y)
        ..cubicTo(size.width * 0.28, y - 54, size.width * 0.46, y + 42,
            size.width + 20, y - 8);
      canvas.drawPath(p, majorRoadPaint);
    }

    final river = ui.Path()
      ..moveTo(-20, size.height * 0.64)
      ..cubicTo(size.width * 0.22, size.height * 0.56, size.width * 0.46,
          size.height * 0.74, size.width + 24, size.height * 0.58);
    canvas.drawPath(
      river,
      Paint()
        ..color = (isDark ? const Color(0xFF151A35) : const Color(0xFFDCEBFF))
            .withValues(alpha: isDark ? 0.52 : 0.70)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 28
        ..strokeCap = StrokeCap.round,
    );

    final route = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFC894FF), AppTheme.primaryColor],
      ).createShader(Offset.zero & size)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = ui.Path()
      ..moveTo(size.width * 0.18, size.height * 0.78)
      ..cubicTo(
        size.width * 0.30,
        size.height * 0.58,
        size.width * 0.52,
        size.height * 0.68,
        size.width * 0.55,
        size.height * 0.48,
      )
      ..cubicTo(
        size.width * 0.58,
        size.height * 0.28,
        size.width * 0.78,
        size.height * 0.38,
        size.width * 0.84,
        size.height * 0.18,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppTheme.primaryColor.withValues(alpha: isDark ? 0.22 : 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(path, route);

    _drawPin(canvas, Offset(size.width * 0.84, size.height * 0.18), 1.0);
    _drawPin(canvas, Offset(size.width * 0.18, size.height * 0.78), 0.76);
    _drawCar(canvas, Offset(size.width * 0.60, size.height * 0.43));

    final labelStyle = TextStyle(
      color: (isDark ? Colors.white : const Color(0xFF5D6073))
          .withValues(alpha: isDark ? 0.36 : 0.54),
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    _drawLabel(canvas, 'Алматы', Offset(size.width * 0.12, size.height * 0.30),
        labelStyle);
    _drawLabel(canvas, 'Абая', Offset(size.width * 0.55, size.height * 0.26),
        labelStyle);
    _drawLabel(canvas, 'Арбат', Offset(size.width * 0.18, size.height * 0.56),
        labelStyle);
  }

  void _drawPin(Canvas canvas, Offset center, double scale) {
    final shadow = Paint()
      ..color = AppTheme.primaryColor.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center.translate(0, 8 * scale), 20 * scale, shadow);
    final pin = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFC894FF), AppTheme.primaryColor],
      ).createShader(Rect.fromCircle(center: center, radius: 20 * scale));
    canvas.drawCircle(center, 13 * scale, pin);
    canvas.drawCircle(center, 5 * scale, Paint()..color = Colors.white);
  }

  void _drawCar(Canvas canvas, Offset center) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.62);
    final shadow = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-15, -27, 30, 54),
      const Radius.circular(13),
    );
    canvas.drawRRect(
      shadow.shift(const Offset(3, 5)),
      Paint()..color = Colors.black.withValues(alpha: isDark ? 0.40 : 0.18),
    );
    canvas.drawRRect(
      shadow,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFCFCBDA)],
        ).createShader(shadow.outerRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-9, -16, 18, 24),
        const Radius.circular(7),
      ),
      Paint()..color = const Color(0xFF171426).withValues(alpha: 0.88),
    );
    canvas.drawCircle(const Offset(-10, -18), 3, Paint()..color = Colors.black);
    canvas.drawCircle(const Offset(10, 18), 3, Paint()..color = Colors.black);
    canvas.restore();
  }

  void _drawLabel(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _IntercityMapFallbackPainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}
