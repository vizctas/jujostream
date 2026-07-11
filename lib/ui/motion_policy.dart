import 'package:flutter/material.dart';

import '../providers/theme_provider.dart';

@immutable
class MotionPolicy {
  const MotionPolicy({
    required this.reduceMotion,
    required this.performanceMode,
  });

  factory MotionPolicy.fromContext(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    final media = MediaQuery.maybeOf(context);
    final systemReduced =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    return MotionPolicy(
      reduceMotion: themeProvider.reduceEffects || systemReduced,
      performanceMode: themeProvider.performanceMode,
    );
  }

  final bool reduceMotion;
  final bool performanceMode;

  bool get allowContinuousEffects => !reduceMotion && !performanceMode;

  Duration get focusDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 160);

  Duration get microDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 140);

  Duration get dialogDuration => reduceMotion
      ? const Duration(milliseconds: 100)
      : const Duration(milliseconds: 220);

  Duration get routeDuration => reduceMotion
      ? const Duration(milliseconds: 120)
      : const Duration(milliseconds: 260);

  Duration get backgroundDuration => reduceMotion
      ? const Duration(milliseconds: 100)
      : const Duration(milliseconds: 300);

  Curve get standardCurve => Curves.easeOutCubic;
  Curve get routeCurve => Curves.easeInOutCubic;
}
