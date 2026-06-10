import 'package:flutter/material.dart';
import '../../services/tv/tv_focus_helpers.dart';

/// Gamepad-friendly virtual keyboard for TV input.
/// Uses TvFocusable for D-pad navigation and A/B/X button support.
class GamepadKeyboard extends StatelessWidget {
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback onDone;
  final bool numericOnly;

  const GamepadKeyboard({
    super.key,
    required this.onKey,
    required this.onBackspace,
    required this.onDone,
    this.numericOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: numericOnly ? _numericRows() : _qwertyRows(),
          ),
        ),
      ),
    );
  }

  List<Widget> _qwertyRows() {
    const rows = [
      ['Q','W','E','R','T','Y','U','I','O','P'],
      ['A','S','D','F','G','H','J','K','L'],
      ['Z','X','C','V','B','N','M'],
    ];
    return [
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final ch in row)
                _KeyCap(
                  label: ch,
                  onSelect: () => onKey(ch),
                  width: 36,
                ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _KeyCap(
              label: 'SPACE',
              onSelect: () => onKey(' '),
              width: 120,
            ),
            const SizedBox(width: 8),
            _KeyCap(
              label: '⌫',
              onSelect: onBackspace,
              width: 56,
              autofocus: true,
            ),
            const SizedBox(width: 8),
            _KeyCap(
              label: 'DONE',
              onSelect: onDone,
              width: 72,
              accent: true,
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _numericRows() {
    const rows = [
      ['1','2','3'],
      ['4','5','6'],
      ['7','8','9'],
    ];
    return [
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final ch in row)
                _KeyCap(
                  label: ch,
                  onSelect: () => onKey(ch),
                  width: 72,
                ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _KeyCap(
              label: '⌫',
              onSelect: onBackspace,
              width: 72,
              autofocus: true,
            ),
            const SizedBox(width: 8),
            _KeyCap(
              label: '0',
              onSelect: () => onKey('0'),
              width: 72,
            ),
            const SizedBox(width: 8),
            _KeyCap(
              label: 'DONE',
              onSelect: onDone,
              width: 72,
              accent: true,
            ),
          ],
        ),
      ),
    ];
  }
}

class _KeyCap extends StatelessWidget {
  final String label;
  final VoidCallback onSelect;
  final double width;
  final bool autofocus;
  final bool accent;

  const _KeyCap({
    required this.label,
    required this.onSelect,
    required this.width,
    this.autofocus = false,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TvFocusable(
        autofocus: autofocus,
        onSelect: onSelect,
        borderRadius: 10,
        child: Container(
          width: width,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: accent
                  ? Colors.white.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: accent ? Colors.white : Colors.white70,
              fontSize: label.length > 1 ? 13 : 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
