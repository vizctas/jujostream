import 'package:flutter/material.dart';

class VirtualJoystick extends StatefulWidget {
  final double size;
  final ValueChanged<Offset> onChanged;
  final VoidCallback? onEnd;
  final Color baseColor;
  final Color thumbColor;

  const VirtualJoystick({
    super.key,
    this.size = 120,
    required this.onChanged,
    this.onEnd,
    this.baseColor = const Color(0x44FFFFFF),
    this.thumbColor = const Color(0xAAFFFFFF),
  });

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _thumbPosition = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final radius = widget.size / 2;
    final thumbRadius = radius * 0.35;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: GestureDetector(
        onPanStart: (details) => _updatePosition(details.localPosition, radius),
        onPanUpdate: (details) => _updatePosition(details.localPosition, radius),
        onPanEnd: (_) {
          setState(() => _thumbPosition = Offset.zero);
          widget.onChanged(Offset.zero);
          widget.onEnd?.call();
        },
        child: CustomPaint(
          painter: _JoystickPainter(
            baseColor: widget.baseColor,
            thumbColor: widget.thumbColor,
            thumbPosition: _thumbPosition,
            thumbRadius: thumbRadius,
          ),
        ),
      ),
    );
  }

  void _updatePosition(Offset localPosition, double radius) {
    final center = Offset(radius, radius);
    var delta = localPosition - center;

    final distance = delta.distance;
    if (distance > radius * 0.8) {
      delta = delta / distance * radius * 0.8;
    }

    final normalized = Offset(
      delta.dx / (radius * 0.8),
      delta.dy / (radius * 0.8),
    );

    setState(() => _thumbPosition = delta);
    widget.onChanged(normalized);
  }
}

class _JoystickPainter extends CustomPainter {
  final Color baseColor;
  final Color thumbColor;
  final Offset thumbPosition;
  final double thumbRadius;

  _JoystickPainter({
    required this.baseColor,
    required this.thumbColor,
    required this.thumbPosition,
    required this.thumbRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = baseColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = baseColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    canvas.drawCircle(
      center + thumbPosition,
      thumbRadius,
      Paint()
        ..color = thumbColor
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter old) =>
      old.thumbPosition != thumbPosition;
}
