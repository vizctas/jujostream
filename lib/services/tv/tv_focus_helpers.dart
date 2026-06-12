import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/audio/ui_sound_service.dart';
import 'tv_detector.dart';

class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSelect;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final FocusNode? focusNode;
  final Color? focusColor;
  final Color? focusFillColor;
  final double focusBorderWidth;
  final double focusScale;
  final double borderRadius;

  /// Removes the child's own focus nodes (TextField, buttons) from traversal
  /// so each element is a single focus stop handled by this wrapper.
  final bool excludeChildFocus;

  const TvFocusable({
    super.key,
    required this.child,
    this.onSelect,
    this.onLongPress,
    this.autofocus = false,
    this.focusNode,
    this.focusColor,
    this.focusFillColor,
    this.focusBorderWidth = 3,
    this.focusScale = 1.06,
    this.borderRadius = 12,
    this.excludeChildFocus = false,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late final FocusNode _focus;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();
    if (widget.autofocus) {
      // Flutter's Focus.autofocus is skipped when the scope already has a
      // focused child (e.g. swapping between auth and MFA layouts). Force it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    if (focused) UiSoundService.playUiMove();
    setState(() => _hasFocus = focused);
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (widget.onSelect == null) return KeyEventResult.ignored;
      UiSoundService.playClick();
      widget.onSelect!();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.gameButtonX) {
      if (widget.onLongPress == null) return KeyEventResult.ignored;
      UiSoundService.playClick();
      widget.onLongPress!();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveFocusColor =
        widget.focusColor ?? context.read<ThemeProvider>().accentLight;

    return Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onFocusChange: _onFocusChange,
      onKeyEvent: _onKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (widget.onSelect != null) {
            UiSoundService.playClick();
            widget.onSelect!();
          }
        },
        onLongPress: () {
          if (widget.onLongPress != null) {
            UiSoundService.playClick();
            widget.onLongPress!();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hasFocus ? widget.focusFillColor : null,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: _hasFocus ? effectiveFocusColor : Colors.transparent,
              width: _hasFocus ? widget.focusBorderWidth : 0,
            ),
            boxShadow: _hasFocus && widget.focusScale > 1
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          transform: _hasFocus
              ? Matrix4.diagonal3Values(
                  widget.focusScale,
                  widget.focusScale,
                  widget.focusScale,
                )
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          child: widget.excludeChildFocus
              ? ExcludeFocus(child: widget.child)
              : widget.child,
        ),
      ),
    );
  }
}

double tvFontSize(double base) => base * TvDetector.instance.fontScale;

double tvSpacing(double base) => base * TvDetector.instance.spacingScale;
