import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'special_keys.dart';

/// Default special key index always shown in the Quick Keys overlay.
/// Index 16 = "Win" (skStartMenu) in [buildSpecialKeysList].
const int quickKeysDefaultIndex = 16;

/// Slide-in overlay that shows the user's favourite special keys plus the
/// default "Win" key.  Transparent background, glassmorphism pills, gamepad
/// navigation (↑↓ A B).
class QuickKeysOverlay extends StatefulWidget {
  /// Indices of user-selected favourite special keys (max 5).
  final List<int> favoriteIndices;

  /// Full special keys list (from [buildSpecialKeysList]).
  final List<SpecialKeyEntry> specialKeys;

  /// Resolves a localization key (e.g. 'skStartMenu') to a human label.
  final String Function(String key) descriptionResolver;

  /// Called when the user activates a key (gamepad A or tap).
  final ValueChanged<int> onActivate;

  /// Called when the overlay should close (gamepad B or tap outside).
  final VoidCallback onClose;

  const QuickKeysOverlay({
    super.key,
    required this.favoriteIndices,
    required this.specialKeys,
    required this.descriptionResolver,
    required this.onActivate,
    required this.onClose,
  });

  @override
  State<QuickKeysOverlay> createState() => QuickKeysOverlayState();
}

class QuickKeysOverlayState extends State<QuickKeysOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<Offset> _slideAnim = Tween<Offset>(
    begin: const Offset(-1.0, 0.0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

  int _focusedIdx = 0;

  /// Ordered list of special key indices shown in the overlay.
  late List<int> _visibleKeys;

  /// GlobalKeys for each pill so we can trigger shake from activateFocused().
  final List<GlobalKey<_QuickKeyPillState>> _pillKeys = [];

  final FocusNode _focusNode = FocusNode(debugLabel: 'quick-keys-overlay');

  @override
  void initState() {
    super.initState();
    _buildVisibleKeys();
    _slideCtrl.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant QuickKeysOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.favoriteIndices != widget.favoriteIndices) {
      _buildVisibleKeys();
    }
  }

  void _buildVisibleKeys() {
    // Default key first, then user favourites (excluding the default if
    // the user also favourited it to avoid duplicates).
    _visibleKeys = [
      quickKeysDefaultIndex,
      ...widget.favoriteIndices.where((i) => i != quickKeysDefaultIndex),
    ];
    // Keep pill GlobalKeys in sync with visible keys count.
    while (_pillKeys.length < _visibleKeys.length) {
      _pillKeys.add(GlobalKey<_QuickKeyPillState>());
    }
    if (_pillKeys.length > _visibleKeys.length) {
      _pillKeys.length = _visibleKeys.length;
    }
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Move focus by [delta] (±1).  Called from host for native D-pad events.
  void moveFocus(int delta) {
    if (_visibleKeys.isEmpty) return;
    setState(() {
      _focusedIdx = (_focusedIdx + delta).clamp(0, _visibleKeys.length - 1);
    });
  }

  /// Activate the currently focused key.
  void activateFocused() {
    if (_visibleKeys.isEmpty) return;
    final keyIdx = _visibleKeys[_focusedIdx];
    // Trigger the pill's shake animation so the user sees visual feedback.
    if (_focusedIdx < _pillKeys.length) {
      _pillKeys[_focusedIdx].currentState?.triggerShake();
    }
    HapticFeedback.lightImpact();
    widget.onActivate(keyIdx);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.gameButtonB ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      widget.onClose();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      moveFocus(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      moveFocus(1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.select) {
      activateFocused();
      return KeyEventResult.handled;
    }

    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onClose,
        child: SlideTransition(
          position: _slideAnim,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < _visibleKeys.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _QuickKeyPill(
                        key: _pillKeys[i],
                        label: _labelFor(_visibleKeys[i]),
                        subtitle: _subtitleFor(_visibleKeys[i]),
                        focused: i == _focusedIdx,
                        isDefault: _visibleKeys[i] == quickKeysDefaultIndex,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          widget.onActivate(_visibleKeys[i]);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _labelFor(int keyIdx) {
    if (keyIdx < 0 || keyIdx >= widget.specialKeys.length) return '?';
    return widget.descriptionResolver(widget.specialKeys[keyIdx].$1);
  }

  String _subtitleFor(int keyIdx) {
    if (keyIdx < 0 || keyIdx >= widget.specialKeys.length) return '';
    return widget.specialKeys[keyIdx].$2;
  }
}

class _QuickKeyPill extends StatefulWidget {
  final String label;
  final String subtitle;
  final bool focused;
  final bool isDefault;
  final VoidCallback onTap;

  const _QuickKeyPill({
    super.key,
    required this.label,
    required this.subtitle,
    required this.focused,
    required this.isDefault,
    required this.onTap,
  });

  @override
  State<_QuickKeyPill> createState() => _QuickKeyPillState();
}

class _QuickKeyPillState extends State<_QuickKeyPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _shakeOffset = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: 4), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 4, end: -4), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -4, end: 2), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 2, end: -1), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -1, end: 0), weight: 1),
  ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeOut));

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  /// Public API so the parent can trigger shake via GlobalKey.
  void triggerShake() {
    _shakeCtrl.forward(from: 0);
  }

  void _handleTap() {
    _shakeCtrl.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _shakeOffset,
        builder: (context, child) => Transform.translate(
          offset: Offset(_shakeOffset.value, 0),
          child: child,
        ),
        child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: widget.focused
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.focused
                    ? Colors.white.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.12),
                width: widget.focused ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isDefault) ...[
                  Icon(
                    Icons.window_rounded,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.70),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.focused ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight: widget.focused ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.subtitle,
                  style: TextStyle(
                    color: widget.focused
                        ? Colors.white.withValues(alpha: 0.50)
                        : Colors.white.withValues(alpha: 0.30),
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
