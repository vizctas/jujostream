import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Cheap, deterministic console-grade backdrop used only when no valid
/// landscape artwork exists. It never stretches the portrait poster.
class PremiumGameBackdrop extends StatelessWidget {
  const PremiumGameBackdrop({
    super.key,
    required this.title,
    this.baseColor = const Color(0xFF07111C),
  });

  final String title;
  final Color baseColor;

  int get _seed {
    var hash = 0x811C9DC5;
    for (final unit in title.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  @override
  Widget build(BuildContext context) {
    final seed = _seed;
    final hue = (seed % 360).toDouble();
    final accent = HSLColor.fromAHSL(1, hue, 0.72, 0.48).toColor();
    final secondary = HSLColor.fromAHSL(
      1,
      (hue + 52 + ((seed >> 8) % 46)) % 360,
      0.65,
      0.38,
    ).toColor();

    return RepaintBoundary(
      key: const Key('game-backdrop-premium'),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final titleSize = math.min(size.height * 0.13, 126.0);
            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _PremiumBackdropPainter(
                    seed: seed,
                    base: baseColor,
                    accent: accent,
                    secondary: secondary,
                  ),
                ),
                Positioned(
                  left: size.width * 0.34,
                  right: size.width * 0.045,
                  bottom: size.height * 0.11,
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      title.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.fade,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.075),
                        fontSize: titleSize,
                        height: 0.88,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -3,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PremiumBackdropPainter extends CustomPainter {
  const _PremiumBackdropPainter({
    required this.seed,
    required this.base,
    required this.accent,
    required this.secondary,
  });

  final int seed;
  final Color base;
  final Color accent;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(base, accent, 0.12)!,
            base,
            Color.lerp(base, secondary, 0.16)!,
          ],
          stops: const [0, 0.56, 1],
        ).createShader(Offset.zero & size),
    );

    final focalX = size.width * (0.67 + ((seed >> 4) % 16) / 100);
    final focalY = size.height * (0.28 + ((seed >> 12) % 24) / 100);
    final glowRect = Rect.fromCircle(
      center: Offset(focalX, focalY),
      radius: size.longestSide * 0.48,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(
            (focalX / size.width) * 2 - 1,
            (focalY / size.height) * 2 - 1,
          ),
          radius: 0.78,
          colors: [
            accent.withValues(alpha: 0.22),
            secondary.withValues(alpha: 0.07),
            Colors.transparent,
          ],
        ).createShader(glowRect),
    );

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.055);
    for (var i = 0; i < 5; i++) {
      final inset = size.shortestSide * (0.08 + i * 0.08);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(focalX, focalY), radius: inset * 1.9),
        -math.pi * 0.72,
        math.pi * (0.72 + ((seed >> i) & 3) * 0.12),
        false,
        linePaint,
      );
    }

    final slashPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, size.width * 0.0012)
      ..color = accent.withValues(alpha: 0.1);
    final shift = ((seed >> 20) % 18) / 100;
    canvas.drawLine(
      Offset(size.width * (0.48 + shift), size.height * 1.04),
      Offset(size.width * (0.83 + shift), -size.height * 0.04),
      slashPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PremiumBackdropPainter oldDelegate) =>
      seed != oldDelegate.seed || base != oldDelegate.base;
}
