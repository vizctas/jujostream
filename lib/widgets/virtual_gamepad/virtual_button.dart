import 'package:flutter/material.dart';

class VirtualButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final double size;
  final VoidCallback onPressed;
  final VoidCallback onReleased;
  final Color color;

  const VirtualButton({
    super.key,
    this.label = '',
    this.icon,
    this.size = 48,
    required this.onPressed,
    required this.onReleased,
    this.color = const Color(0xAAFFFFFF),
  });

  @override
  State<VirtualButton> createState() => _VirtualButtonState();
}

class _VirtualButtonState extends State<VirtualButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _pressed = true);
        widget.onPressed();
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onReleased();
      },
      onTapCancel: () {
        setState(() => _pressed = false);
        widget.onReleased();
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _pressed
              ? widget.color.withValues(alpha: 0.6)
              : widget.color.withValues(alpha: 0.25),
          border: Border.all(
            color: widget.color.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        child: Center(
          child: widget.icon != null
              ? Icon(widget.icon, color: widget.color, size: widget.size * 0.5)
              : Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.color,
                    fontSize: widget.size * 0.35,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}
