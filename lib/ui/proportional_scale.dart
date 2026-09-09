import 'package:flutter/widgets.dart';

/// Scales paint, layout footprint, and hit testing by the same factor.
///
/// [Transform.scale] alone keeps the unscaled layout size. Pairing it with an
/// unconstrained [Align] and matching factors makes the parent reserve the
/// actual painted size as well.
class ProportionalScale extends StatelessWidget {
  const ProportionalScale({
    super.key,
    required this.scale,
    required this.baseWidth,
    required this.child,
  }) : assert(scale > 0);

  final double scale;
  final double baseWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return UnconstrainedBox(
      child: Align(
        widthFactor: scale,
        heightFactor: scale,
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: SizedBox(width: baseWidth, child: child),
        ),
      ),
    );
  }
}
