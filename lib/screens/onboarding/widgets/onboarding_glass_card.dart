import 'dart:ui';
import 'package:flutter/material.dart';

class OnboardingGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double blur;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final double borderOpacity;

  const OnboardingGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.blur = 24,
    this.borderRadius,
    this.backgroundColor,
    this.borderOpacity = 0.15,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(24);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor ?? const Color(0xFFFFFFFF).withValues(alpha: 0.035),
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: borderOpacity),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
