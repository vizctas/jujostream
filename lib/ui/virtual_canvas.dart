import 'package:flutter/widgets.dart';

/// Lays [child] out on a canvas at least [designHeight] logical px tall and
/// scales the whole thing down to the real viewport.
///
/// TV boxes report 960x540 (DPR 2), so launcher themes with fixed font and
/// icon sizes rendered ~33% larger than designed. [designHeight] is the knob:
/// raise it to shrink the UI further.
class VirtualCanvas extends StatelessWidget {
  const VirtualCanvas({super.key, this.designHeight = 720, required this.child});

  final double designHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final k = (mq.size.height / designHeight).clamp(0.6, 1.0);
    if (k == 1.0) return child;
    return FittedBox(
      child: SizedBox.fromSize(
        size: mq.size / k,
        child: MediaQuery(
          data: mq.copyWith(
            size: mq.size / k,
            padding: mq.padding / k,
            viewPadding: mq.viewPadding / k,
            viewInsets: mq.viewInsets / k,
          ),
          child: child,
        ),
      ),
    );
  }
}
