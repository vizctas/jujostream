import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../ui/motion_scope.dart';

/// App-bar icon button with a gamepad-visible focus treatment.
///
/// Shared by `pc_view_screen.dart` and `focus_mode_screen.dart`, which each
/// carried a byte-identical private copy — including the same defect: the inner
/// `IconButton`'s `FocusNode` was constructed inside `build()` and never
/// disposed, so every rebuild leaked one. The app bar rebuilds on a 5-second
/// timer, so the leak was continuous.
class FocusableIconButton extends StatefulWidget {
  const FocusableIconButton({
    super.key,
    this.focusNode,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.onNav,
    this.color,
  });

  final FocusNode? focusNode;
  final IconData icon;

  /// Doubles as the accessibility label: this control is icon-only, so without
  /// it a screen reader announces an unnamed button.
  final String tooltip;
  final VoidCallback? onPressed;
  final void Function(LogicalKeyboardKey dir)? onNav;
  final Color? color;

  @override
  State<FocusableIconButton> createState() => _FocusableIconButtonState();
}

class _FocusableIconButtonState extends State<FocusableIconButton> {
  bool _focused = false;

  /// Owned for the lifetime of the State, not rebuilt per frame.
  /// `skipTraversal` keeps the outer [Focus] as the single traversal stop.
  final FocusNode _buttonNode = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _buttonNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select) {
      widget.onPressed?.call();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      widget.onNav?.call(key);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.gameButtonB ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape) {
      Navigator.maybePop(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.tooltip,
      button: true,
      enabled: widget.onPressed != null,
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (f) => setState(() => _focused = f),
        onKeyEvent: _handleKey,
        child: AnimatedContainer(
          duration: MotionScope.of(context).focusDuration,
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          decoration: BoxDecoration(
            color: _focused
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: _focused
                ? Border.all(color: Colors.white54, width: 1.5)
                : null,
          ),
          child: IconButton(
            icon: Icon(widget.icon, color: widget.color ?? Colors.white),
            tooltip: widget.tooltip,
            onPressed: widget.onPressed,
            focusNode: _buttonNode,
            style: IconButton.styleFrom(
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}
