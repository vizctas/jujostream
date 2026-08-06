import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../ui/motion_policy.dart';

/// AppBar brand title: animated cube icon + "JUJO.Stream".
///
/// The icon plays a short damped bounce + wobble on mount and every 15 s.
/// The ticker only runs during the 2250 ms animation; the rest of the time
/// the subtree is fully static (and isolated behind a RepaintBoundary).
class JujoBrandTitle extends StatefulWidget {
  const JujoBrandTitle({super.key, this.iconSize = 24});

  final double iconSize;

  @override
  State<JujoBrandTitle> createState() => _JujoBrandTitleState();
}

class _JujoBrandTitleState extends State<JujoBrandTitle>
    with SingleTickerProviderStateMixin {
  static const _iconColor = Color(0xFFF43F5E);
  static const _accentColor = Color(0xFF22D3EE);
  // Per-segment easing, matching CSS cubic-bezier(0.25, 0.8, 0.25, 1).
  static const _segmentCurve = Cubic(0.25, 0.8, 0.25, 1);

  late final AnimationController _controller;
  late final Animation<double> _translateY;
  late final Animation<double> _rotation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2250),
    );
    _translateY = _sequence(const [0, -20, 2, -9, 1, 0]).animate(_controller);
    _rotation = _sequence(const [0, 21, -11, 7, -3, 0])
        .animate(_controller); // degrees
    // Deferred so MediaQuery/ThemeProvider are readable. This bounce lives in
    // the home screen app bar and repeated every 15s for the life of the
    // screen, ignoring both the in-app Reduce Effects toggle and the OS
    // reduce-motion setting. Its twin in cinematic_intro_screen already
    // honoured reduced motion; the two disagreed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final motion = MotionPolicy.fromContext(
        context,
        context.read<ThemeProvider>(),
      );
      if (motion.reduceMotion) return;
      _controller.forward();
      if (!motion.allowContinuousEffects) return;
      _timer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (mounted) _controller.forward(from: 0);
      });
    });
  }

  static TweenSequence<double> _sequence(List<double> keyframes) {
    return TweenSequence<double>([
      for (var i = 0; i < keyframes.length - 1; i++)
        TweenSequenceItem(
          tween: Tween(begin: keyframes[i], end: keyframes[i + 1])
              .chain(CurveTween(curve: _segmentCurve)),
          weight: 1,
        ),
    ]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final baseColor =
        brightness == Brightness.light ? Colors.black87 : Colors.white;
    final scale = widget.iconSize / 48;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _translateY.value * scale),
              child: Transform.rotate(
                angle: _rotation.value * math.pi / 180,
                child: child,
              ),
            ),
            child: CustomPaint(
              size: Size.square(widget.iconSize),
              painter: const _JujoBoxPainter(_iconColor),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text.rich(
          TextSpan(
            text: 'JUJO',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: baseColor,
            ),
            children: const [
              TextSpan(
                text: '.Stream',
                style: TextStyle(color: _accentColor),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Draws the cube/package icon from the brand SVG (viewBox 0 0 48 48):
/// a filled cube silhouette with the inner edge lines cut out to
/// transparency, replicating the SVG's mask.
class _JujoBoxPainter extends CustomPainter {
  const _JujoBoxPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 48;

    final cube = Path()
      ..moveTo(41 * s, 14 * s)
      ..lineTo(24 * s, 4 * s)
      ..lineTo(7 * s, 14 * s)
      ..lineTo(7 * s, 34 * s)
      ..lineTo(24 * s, 44 * s)
      ..lineTo(41 * s, 34 * s)
      ..close();

    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * s
      ..strokeJoin = StrokeJoin.round;

    // The inner lines must cut transparent holes (like the SVG mask), so
    // draw everything into a layer and clear the lines with BlendMode.clear.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawPath(cube, fill);
    canvas.drawPath(cube, stroke);

    final innerLines = Path()
      ..moveTo(16 * s, 18.998 * s)
      ..lineTo(23.993 * s, 24 * s)
      ..lineTo(31.995 * s, 18.998 * s)
      ..moveTo(24 * s, 24 * s)
      ..lineTo(24 * s, 33 * s);
    final clear = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(innerLines, clear);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_JujoBoxPainter oldDelegate) =>
      oldDelegate.color != color;
}
