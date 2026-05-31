import 'package:flutter/material.dart';

class OnboardingSolidCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final double borderOpacity;
  final List<BoxShadow>? boxShadow;

  const OnboardingSolidCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(28),
    this.borderRadius,
    this.backgroundColor,
    this.borderOpacity = 0.08,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(24);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? const Color(0xFF1C1C1E),
        borderRadius: radius,
        border: Border.all(
          color: Colors.white.withValues(alpha: borderOpacity),
          width: 1,
        ),
        boxShadow: boxShadow ?? const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
