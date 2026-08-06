import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/stream_configuration.dart';

const List<LaunchRevealEffect> concreteLaunchRevealEffects = [
  LaunchRevealEffect.cinematicIris,
  LaunchRevealEffect.prismBloom,
  LaunchRevealEffect.signalVeil,
  LaunchRevealEffect.posterReveal,
  LaunchRevealEffect.minimalLuxe,
];

LaunchRevealEffect resolveLaunchRevealEffect(
  LaunchRevealEffect selected, {
  required bool reduceMotion,
  required bool performanceMode,
  math.Random? random,
}) {
  if (reduceMotion || performanceMode) return LaunchRevealEffect.minimalLuxe;
  if (selected != LaunchRevealEffect.random) return selected;
  final source = random ?? math.Random();
  return concreteLaunchRevealEffects[source.nextInt(
    concreteLaunchRevealEffects.length,
  )];
}

Duration launchRevealDuration(
  LaunchRevealEffect effect, {
  required bool reduceMotion,
  required bool performanceMode,
}) {
  if (reduceMotion || performanceMode) {
    return const Duration(milliseconds: 180);
  }
  return switch (effect) {
    LaunchRevealEffect.cinematicIris => const Duration(milliseconds: 880),
    LaunchRevealEffect.prismBloom => const Duration(milliseconds: 760),
    LaunchRevealEffect.signalVeil => const Duration(milliseconds: 820),
    LaunchRevealEffect.posterReveal => const Duration(milliseconds: 720),
    LaunchRevealEffect.minimalLuxe => const Duration(milliseconds: 460),
    LaunchRevealEffect.random => const Duration(milliseconds: 720),
  };
}

/// Animates an already-opaque launch surface away from a video frame that the
/// privacy gate has proven safe. It never decides when the video may appear.
class LaunchRevealTransition extends StatelessWidget {
  const LaunchRevealTransition({
    super.key,
    required this.effect,
    required this.animation,
    required this.child,
    this.accent = const Color(0xFF70E1FF),
  });

  final LaunchRevealEffect effect;
  final Animation<double> animation;
  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, opaqueSurface) {
        final t = Curves.easeInOutCubic.transform(
          animation.value.clamp(0.0, 1.0),
        );
        return switch (effect) {
          LaunchRevealEffect.cinematicIris => _cinematicIris(opaqueSurface!, t),
          LaunchRevealEffect.prismBloom => _prismBloom(opaqueSurface!, t),
          LaunchRevealEffect.signalVeil => _signalVeil(opaqueSurface!, t),
          LaunchRevealEffect.posterReveal => _posterReveal(opaqueSurface!, t),
          LaunchRevealEffect.minimalLuxe ||
          LaunchRevealEffect.random => _minimalLuxe(opaqueSurface!, t),
        };
      },
    );
  }

  Widget _cinematicIris(Widget surface, double t) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipPath(clipper: _IrisClipper(t), child: surface),
        IgnorePointer(
          child: CustomPaint(
            painter: _IrisEdgePainter(progress: t, accent: accent),
          ),
        ),
      ],
    );
  }

  Widget _prismBloom(Widget surface, double t) {
    final opacity = (1 - Curves.easeIn.transform(t)).clamp(0.0, 1.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: opacity,
          child: Transform.scale(scale: 1 + (0.025 * t), child: surface),
        ),
        IgnorePointer(
          child: Opacity(
            opacity: (math.sin(t * math.pi) * 0.48).clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.15, -0.08),
                  radius: 0.85 + (0.3 * t),
                  colors: [
                    Colors.white.withValues(alpha: 0.78),
                    accent.withValues(alpha: 0.22),
                    const Color(0xFF9D6CFF).withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.18, 0.46, 1],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _signalVeil(Widget surface, double t) {
    final opacity = (1 - ((t - 0.12) / 0.88)).clamp(0.0, 1.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(opacity: opacity, child: surface),
        IgnorePointer(
          child: CustomPaint(
            painter: _SignalVeilPainter(progress: t, accent: accent),
          ),
        ),
      ],
    );
  }

  Widget _posterReveal(Widget surface, double t) {
    final opacity = (1 - Curves.easeInCubic.transform(t)).clamp(0.0, 1.0);
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: 1 + (0.075 * Curves.easeIn.transform(t)),
        child: surface,
      ),
    );
  }

  Widget _minimalLuxe(Widget surface, double t) {
    return Opacity(
      opacity: (1 - t).clamp(0.0, 1.0),
      child: Transform.scale(scale: 1 + (0.012 * t), child: surface),
    );
  }
}

class _IrisClipper extends CustomClipper<Path> {
  const _IrisClipper(this.progress);

  final double progress;

  @override
  Path getClip(Size size) {
    final remaining = (1 - progress).clamp(0.0, 1.0);
    final upper = size.height * 0.5 * remaining;
    final lower = size.height - upper;
    return Path()
      ..addRect(Rect.fromLTRB(0, 0, size.width, upper))
      ..addRect(Rect.fromLTRB(0, lower, size.width, size.height));
  }

  @override
  bool shouldReclip(covariant _IrisClipper oldClipper) =>
      oldClipper.progress != progress;
}

class _IrisEdgePainter extends CustomPainter {
  const _IrisEdgePainter({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1) return;
    final remaining = 1 - progress;
    final upper = size.height * 0.5 * remaining;
    final lower = size.height - upper;
    final glow = (math.sin(progress * math.pi) * 0.7).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = accent.withValues(alpha: glow)
      ..strokeWidth = 1.2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawLine(
      Offset.zero.translate(0, upper),
      Offset(size.width, upper),
      paint,
    );
    canvas.drawLine(Offset(0, lower), Offset(size.width, lower), paint);
  }

  @override
  bool shouldRepaint(covariant _IrisEdgePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.accent != accent;
}

class _SignalVeilPainter extends CustomPainter {
  const _SignalVeilPainter({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1) return;
    final fade = (1 - progress).clamp(0.0, 1.0);
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.055 * fade)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 7) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final sweepY = (size.height + 120) * progress - 60;
    final sweepPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          accent.withValues(alpha: 0.34 * fade),
          Colors.white.withValues(alpha: 0.2 * fade),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, sweepY - 42, size.width, 84));
    canvas.drawRect(Rect.fromLTWH(0, sweepY - 42, size.width, 84), sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _SignalVeilPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.accent != accent;
}
