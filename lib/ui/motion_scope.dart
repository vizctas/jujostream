import 'package:flutter/widgets.dart';
import 'motion_policy.dart';

class MotionScope extends InheritedWidget {
  const MotionScope({super.key, required this.policy, required super.child});
  final MotionPolicy policy;
  static MotionPolicy of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MotionScope>()?.policy ??
      const MotionPolicy(
        reduceMotion: false,
        performanceMode: false,
        resolvedTier: MotionTier.standard,
      );
  static MotionPolicy read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MotionScope>()?.policy ??
      const MotionPolicy(
        reduceMotion: false,
        performanceMode: false,
        resolvedTier: MotionTier.standard,
      );
  @override
  bool updateShouldNotify(MotionScope oldWidget) => oldWidget.policy != policy;
}
