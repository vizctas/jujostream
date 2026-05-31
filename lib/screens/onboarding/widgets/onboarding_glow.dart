import 'package:flutter/material.dart';

class OnboardingGlow extends StatelessWidget {
  final ValueNotifier<double> scrollOffset;

  const OnboardingGlow({super.key, required this.scrollOffset});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: scrollOffset,
      builder: (context, offset, _) {
        final size = MediaQuery.sizeOf(context);
        return Stack(
          children: [
            _glow(
              top: -120 + offset * 0.06,
              left: size.width * 0.05,
              diameter: 420,
              colors: [
                const Color(0xFF4F46E5).withValues(alpha: 0.18),
                Colors.transparent,
              ],
            ),
            _glow(
              top: size.height * 0.65 + offset * 0.10,
              right: -100,
              diameter: 560,
              colors: [
                const Color(0xFF7C3AED).withValues(alpha: 0.13),
                Colors.transparent,
              ],
            ),
            _glow(
              top: size.height * 1.55 + offset * 0.08,
              left: size.width * 0.25,
              diameter: 400,
              colors: [
                const Color(0xFF0EA5E9).withValues(alpha: 0.11),
                Colors.transparent,
              ],
            ),
            _glow(
              top: size.height * 2.45 + offset * 0.12,
              right: size.width * 0.08,
              diameter: 480,
              colors: [
                const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                Colors.transparent,
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _glow({
    required double top,
    double? left,
    double? right,
    required double diameter,
    required List<Color> colors,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: colors,
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}
