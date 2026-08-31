import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion_scope.dart';

/// Shared interaction contract for tap, keyboard, remote and assistive input.
///
/// This widget deliberately owns behavior rather than visual styling. Launcher
/// skins keep their personality while receiving the same semantics, focus and
/// minimum-target guarantees.
class AccessibleAction extends StatefulWidget {
  const AccessibleAction({
    super.key,
    required this.label,
    required this.onActivate,
    required this.child,
    this.onLongPress,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.selected,
    this.tooltip,
    this.minimumSize = const Size(48, 48),
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.showFocusRing = true,
    this.excludeChildSemantics = true,
    this.onFocusChange,
  });

  final String label;
  final VoidCallback onActivate;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final bool? selected;
  final String? tooltip;
  final Size minimumSize;
  final BorderRadius borderRadius;
  final bool showFocusRing;
  final bool excludeChildSemantics;
  final ValueChanged<bool>? onFocusChange;
  final Widget child;

  @override
  State<AccessibleAction> createState() => _AccessibleActionState();
}

class _AccessibleActionState extends State<AccessibleAction> {
  bool _focused = false;

  void _activate() {
    if (widget.enabled) widget.onActivate();
  }

  void _handleFocus(bool focused) {
    if (_focused != focused) setState(() => _focused = focused);
    widget.onFocusChange?.call(focused);
  }

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    final focusColor = Theme.of(context).colorScheme.primary;
    Widget result = FocusableActionDetector(
      enabled: widget.enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: _handleFocus,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? _activate : null,
        onLongPress: widget.enabled ? widget.onLongPress : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: widget.minimumSize.width,
            minHeight: widget.minimumSize.height,
          ),
          child: AnimatedContainer(
            duration: motion.focusDuration,
            curve: motion.standardCurve,
            foregroundDecoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              border: widget.showFocusRing && _focused
                  ? Border.all(color: focusColor, width: 2)
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );

    result = Semantics(
      container: true,
      button: true,
      enabled: widget.enabled,
      focusable: widget.enabled,
      focused: _focused,
      selected: widget.selected,
      label: widget.label,
      onTap: widget.enabled ? _activate : null,
      onLongPress: widget.enabled ? widget.onLongPress : null,
      excludeSemantics: widget.excludeChildSemantics,
      child: result,
    );

    final tooltip = widget.tooltip;
    return tooltip == null || tooltip.isEmpty
        ? result
        : Tooltip(message: tooltip, child: result);
  }
}
