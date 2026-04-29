import 'package:flutter/material.dart';
import 'special_keys.dart';

/// Left-edge slide-in panel showing the user's favorite special keys.
///
/// Max 5 keys, vertically stacked, with D-pad Up/Down navigation.
/// Slides in from `Offset(-1, 0)` → `Offset(0, 0)` over 250ms.
class QuickFavKeysPanel extends StatefulWidget {
  /// Ordered list of favorite key indices (max 5).
  final List<int> favoriteIndices;

  /// The full special keys list (from [buildSpecialKeysList]).
  final List<SpecialKeyEntry> specialKeys;

  /// Resolves a localization key to a human-readable label.
  final String Function(String key) descriptionResolver;

  /// Called when a key is activated (A button / tap).
  final ValueChanged<int> onActivate;

  /// Called when the panel should close (B button / tap outside).
  final VoidCallback onClose;

  /// Currently focused index within the favorites list (0-based).
  final int focusedIndex;

  const QuickFavKeysPanel({
    super.key,
    required this.favoriteIndices,
    required this.specialKeys,
    required this.descriptionResolver,
    required this.onActivate,
    required this.onClose,
    this.focusedIndex = 0,
  });

  @override
  State<QuickFavKeysPanel> createState() => _QuickFavKeysPanelState();
}

class _QuickFavKeysPanelState extends State<QuickFavKeysPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.favoriteIndices.isEmpty) {
      return SlideTransition(
        position: _slideAnim,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(left: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'No favorites yet\nOpen Special Keys → press Ⓨ',
              style: TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return SlideTransition(
      position: _slideAnim,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(left: 12),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < widget.favoriteIndices.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  _buildFavChip(i),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFavChip(int listIndex) {
    final keyIdx = widget.favoriteIndices[listIndex];
    if (keyIdx < 0 || keyIdx >= widget.specialKeys.length) {
      return const SizedBox.shrink();
    }
    final entry = widget.specialKeys[keyIdx];
    final label = widget.descriptionResolver(entry.$1);
    final focused = listIndex == widget.focusedIndex;

    return SizedBox(
      width: 100,
      child: buildKeyChip(
        label,
        () => widget.onActivate(keyIdx),
        focused: focused,
        subtitle: entry.$2,
      ),
    );
  }
}
