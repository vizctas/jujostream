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

class _QuickKeyPill extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool focused;
  final bool isDefault;
  final VoidCallback onTap;

  const _QuickKeyPill({
    required this.label,
    required this.subtitle,
    required this.focused,
    required this.isDefault,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: focused
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: focused
                    ? Colors.white.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.12),
                width: focused ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDefault) ...[
                  Icon(
                    Icons.window_rounded,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.70),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: focused ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight: focused ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: focused
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
    );
  }
}
