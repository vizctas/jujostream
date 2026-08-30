import 'package:flutter/material.dart';

import 'motion_scope.dart';

class AdaptiveFocusSurface extends StatelessWidget {
  const AdaptiveFocusSurface({
    super.key,
    required this.focused,
    required this.child,
    this.alignment = Alignment.center,
  });
  final bool focused;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    final scale = focused && !motion.reduceMotion
        ? motion.profile.focusScale
        : 1.0;
    final travel = focused && !motion.reduceMotion
        ? -motion.profile.focusTravel
        : 0.0;
    return AnimatedScale(
      scale: scale,
      alignment: alignment,
      duration: motion.focusDuration,
      curve: motion.tokens.focusCurve,
      child: AnimatedSlide(
        offset: Offset(0, travel / 100),
        duration: motion.focusDuration,
        curve: motion.tokens.focusCurve,
        child: child,
      ),
    );
  }
}

class AdaptiveContentSwitcher extends StatelessWidget {
  const AdaptiveContentSwitcher({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
  });
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    return AnimatedSwitcher(
      duration: motion.backgroundDuration,
      reverseDuration: motion.tokens.state,
      switchInCurve: motion.tokens.enterCurve,
      switchOutCurve: motion.tokens.exitCurve,
      layoutBuilder: (current, previous) =>
          Stack(alignment: alignment, children: [...previous, ?current]),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: child,
    );
  }
}

class AmbientMotionGate extends StatelessWidget {
  const AmbientMotionGate({
    super.key,
    required this.animated,
    required this.still,
    this.backdrop = false,
  });
  final Widget animated;
  final Widget still;
  final bool backdrop;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    final allowed = backdrop
        ? motion.allowBackdropMotion
        : motion.allowContinuousEffects;
    return allowed ? animated : still;
  }
}
