import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/audio/ui_sound_service.dart';
import '../../ui/motion_policy.dart';
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
  final String? semanticLabel;
  final bool selected;
  final bool enabled;
  final bool playFocusSound;

  /// Removes the child's own focus nodes (TextField, buttons) from traversal
  /// so each element is a single focus stop handled by this wrapper.
  final bool excludeChildFocus;

  /// When true, on gaining focus this widget scrolls its nearest [Scrollable]
  /// ancestor so it becomes visible (centered). Use inside long lists that
  /// move focus programmatically (e.g. looping traversal) where Flutter's
  /// default ensure-visible doesn't fire. Off by default so existing usages
  /// are unaffected.
  final bool scrollOnFocus;

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
    this.semanticLabel,
    this.selected = false,
    this.enabled = true,
    this.playFocusSound = true,
    this.excludeChildFocus = false,
    this.scrollOnFocus = false,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late final FocusNode _focus;
  bool _hasFocus = false;
  bool _suppressNextFocusSound = false;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();
    if (widget.autofocus) {
      _suppressNextFocusSound = true;
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
    if (focused) {
      if (_suppressNextFocusSound) {
        _suppressNextFocusSound = false;
      } else if (widget.playFocusSound) {
        UiSoundService.playUiMove();
      }
      if (widget.scrollOnFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_focus.hasFocus) return;
          final ctx = context;
          if (!ctx.mounted) return;
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        });
      }
    }
    if (mounted) setState(() => _hasFocus = focused);
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!widget.enabled) return KeyEventResult.ignored;
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
    final themeProvider = context.watch<ThemeProvider>();
    final motion = MotionPolicy.fromContext(context, themeProvider);
    final effectiveFocusColor = widget.focusColor ?? themeProvider.accentLight;

    return Semantics(
      button: widget.onSelect != null,
      label: widget.semanticLabel,
      selected: widget.selected,
      enabled: widget.enabled,
      focusable: true,
      focused: _hasFocus,
      onTap: widget.enabled ? widget.onSelect : null,
      child: Focus(
        focusNode: _focus,
        autofocus: widget.autofocus,
        canRequestFocus: widget.enabled,
        onFocusChange: _onFocusChange,
        onKeyEvent: _onKeyEvent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled
              ? () {
                  if (widget.onSelect != null) {
                    UiSoundService.playClick();
                    widget.onSelect!();
                  }
                }
              : null,
          onLongPress: widget.enabled
              ? () {
                  if (widget.onLongPress != null) {
                    UiSoundService.playClick();
                    widget.onLongPress!();
                  }
                }
              : null,
          child: AnimatedContainer(
            duration: motion.focusDuration,
            curve: motion.standardCurve,
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
            transform: _hasFocus && !motion.reduceMotion
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
      ),
    );
  }
}

double tvFontSize(double base) => base * TvDetector.instance.fontScale;

double tvSpacing(double base) => base * TvDetector.instance.spacingScale;
