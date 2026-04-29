import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../platform_channels/streaming_channel.dart';

const int vkEscape = 0x1B;
const int vkF11 = 0x7A;
const int vkF4 = 0x73;
const int vkReturn = 0x0D;
const int vkTab = 0x09;
const int vkDelete = 0x2E;
const int vkLwin = 0x5B;
const int vkD = 0x44;
const int vkG = 0x47;
const int vkV = 0x56;
const int vkCtrl = 0xA2;
const int vkAlt = 0xA4;
const int vkC = 0x43;
const int vkZ = 0x5A;
const int vkA = 0x41;
const int vkP = 0x50;
const int vkPrintScreen = 0x2C;
const int vkVolUp = 0xAF;
const int vkVolDn = 0xAE;
const int vkMute = 0xAD;
const int vkPlayPause = 0xB3;
const int vkShift = 0xA0;
const int vkLeft = 0x25;
const int vkRight = 0x27;
const int vkE = 0x45;
const int vkX = 0x58;

/// Send a single key press + release via the streaming channel.
void sendKey(int keyCode) {
  StreamingPlatformChannel.sendKeyboardInput(keyCode, true);
  Future.delayed(const Duration(milliseconds: 50), () {
    StreamingPlatformChannel.sendKeyboardInput(keyCode, false);
  });
}

/// Send a key combo (all down, then all up in reverse order).
void sendCombo(List<int> keys) {
  for (final k in keys) {
    StreamingPlatformChannel.sendKeyboardInput(k, true);
  }
  Future.delayed(const Duration(milliseconds: 50), () {
    for (final k in keys.reversed) {
      StreamingPlatformChannel.sendKeyboardInput(k, false);
    }
  });
}

/// Number of columns in the special-keys grid.
const int specialKeyCols = 3;

/// Section boundaries for gamepad D-pad navigation.
const List<int> specialKeySections = [0, 10, 16, 22];

/// Total number of special keys.
const int specialKeyCount = 26;

/// (localizationKey, shortcutLabel, action)
typedef SpecialKeyEntry = (String, String, VoidCallback);

/// Builds the canonical list of special keys.
///
/// This is a function (not a const) because each entry captures a closure.
List<SpecialKeyEntry> buildSpecialKeysList() => [
  // ── WINDOW (0–9) ──
  ('skExit', 'Esc', () => sendKey(vkEscape)),
  ('skFullscreen', 'F11', () => sendKey(vkF11)),
  ('skCloseApp', 'Alt+F4', () => sendCombo([vkAlt, vkF4])),
  ('skSwitchApp', 'Alt+Tab', () => sendCombo([vkAlt, vkTab])),
  ('skWindowed', 'Alt+Enter', () => sendCombo([vkAlt, vkReturn])),
  ('skDesktop', 'Win+D', () => sendCombo([vkLwin, vkD])),
  ('skTaskView', 'Win+Tab', () => sendCombo([vkLwin, vkTab])),
  ('skDisplayMode', 'Win+P', () => sendCombo([vkLwin, vkP])),
  ('skDisplayLeft', 'Win+Shift+←', () => sendCombo([vkLwin, vkShift, vkLeft])),
  (
    'skDisplayRight',
    'Win+Shift+→',
    () => sendCombo([vkLwin, vkShift, vkRight]),
  ),

  // ── INPUT (10–15) ──
  ('skNextField', 'Tab', () => sendKey(vkTab)),
  ('skPaste', 'Ctrl+V', () => sendCombo([vkCtrl, vkV])),
  ('skCopy', 'Ctrl+C', () => sendCombo([vkCtrl, vkC])),
  ('skCut', 'Ctrl+X', () => sendCombo([vkCtrl, vkX])),
  ('skUndo', 'Ctrl+Z', () => sendCombo([vkCtrl, vkZ])),
  ('skSelectAll', 'Ctrl+A', () => sendCombo([vkCtrl, vkA])),

  // ── SYSTEM (16–21) ──
  ('skStartMenu', 'Win', () => sendKey(vkLwin)),
  ('skGameBar', 'Win+G', () => sendCombo([vkLwin, vkG])),
  ('skScreenshot', 'PrtScn', () => sendKey(vkPrintScreen)),
  ('skSecurity', 'Ctrl+Alt+Del', () => sendCombo([vkCtrl, vkAlt, vkDelete])),
  (
    'skTaskManager',
    'Ctrl+Shift+Esc',
    () => sendCombo([vkCtrl, vkShift, vkEscape]),
  ),
  ('skExplorer', 'Win+E', () => sendCombo([vkLwin, vkE])),

  // ── MEDIA (22–25) ──
  ('skPlayPause', 'Play/Pause', () => sendKey(vkPlayPause)),
  ('skVolUp', 'Vol +', () => sendKey(vkVolUp)),
  ('skVolDown', 'Vol −', () => sendKey(vkVolDn)),
  ('skMute', 'Mute', () => sendKey(vkMute)),
];

// ─── Grid navigation helpers ────────────────────────────────────────────────

/// Returns the flat index after moving [direction] from [current] inside the
/// special-keys grid (3 columns, sections at [specialKeySections]).
///
/// [direction] is one of `'left'`, `'right'`, `'up'`, `'down'`.
int specialKeyGridMove(int current, String direction) {
  // Determine which section the current index belongs to.
  int secStart = specialKeySections.last;
  int secEnd = specialKeyCount;
  for (int i = specialKeySections.length - 1; i >= 0; i--) {
    if (current >= specialKeySections[i]) {
      secStart = specialKeySections[i];
      secEnd = (i + 1 < specialKeySections.length)
          ? specialKeySections[i + 1]
          : specialKeyCount;
      break;
    }
  }

  final localIdx = current - secStart;
  final sectionLen = secEnd - secStart;
  final col = localIdx % specialKeyCols;
  final row = localIdx ~/ specialKeyCols;
  final totalRows = (sectionLen + specialKeyCols - 1) ~/ specialKeyCols;

  switch (direction) {
    case 'left':
      if (col > 0) return current - 1;
      return current; // already leftmost
    case 'right':
      if (col < specialKeyCols - 1 && localIdx + 1 < sectionLen) {
        return current + 1;
      }
      return current; // already rightmost or last in section
    case 'down':
      // Try moving down within section
      final nextRow = row + 1;
      if (nextRow < totalRows) {
        final nextLocal = nextRow * specialKeyCols + col;
        if (nextLocal < sectionLen) return secStart + nextLocal;
        // Column doesn't exist in last row — clamp to last item in section
        return secStart + sectionLen - 1;
      }
      // Jump to next section (same column or clamped)
      final secIdx = specialKeySections.indexOf(secStart);
      if (secIdx + 1 < specialKeySections.length) {
        final nextSecStart = specialKeySections[secIdx + 1];
        final nextSecEnd = (secIdx + 2 < specialKeySections.length)
            ? specialKeySections[secIdx + 2]
            : specialKeyCount;
        final nextSecLen = nextSecEnd - nextSecStart;
        return nextSecStart + col.clamp(0, nextSecLen - 1);
      }
      return current; // already in last section, last row
    case 'up':
      // Try moving up within section
      final prevRow = row - 1;
      if (prevRow >= 0) {
        return secStart + prevRow * specialKeyCols + col;
      }
      // Jump to previous section (same column, last row)
      final secIdx = specialKeySections.indexOf(secStart);
      if (secIdx > 0) {
        final prevSecStart = specialKeySections[secIdx - 1];
        final prevSecEnd = specialKeySections[secIdx];
        final prevSecLen = prevSecEnd - prevSecStart;
        final prevTotalRows =
            (prevSecLen + specialKeyCols - 1) ~/ specialKeyCols;
        final targetLocal = (prevTotalRows - 1) * specialKeyCols + col;
        if (targetLocal < prevSecLen) return prevSecStart + targetLocal;
        return prevSecStart + prevSecLen - 1;
      }
      return current; // already in first section, first row
  }
  return current;
}

// ─── Panel builder ──────────────────────────────────────────────────────────

/// Builds the special-keys grid panel shown inside the stream overlay.
///
/// [specialKeys] — the key list (from [buildSpecialKeysList]).
/// [focusedIndex] — currently focused key index (for gamepad navigation).
/// [descriptionResolver] — maps a localization key to a human-readable label.
/// [onActivate] — called when a key chip is tapped.
/// [onBack] — called when the back button is pressed.
/// [onCloseOverlay] — called when "Close menu" is tapped.
/// [closeMenuLabel] — localized label for the close-menu tile.
/// [specialKeysLabel] — localized label for the panel title.
Widget buildSpecialKeysPanel({
  required List<SpecialKeyEntry> specialKeys,
  required int focusedIndex,
  required String Function(String key) descriptionResolver,
  required ValueChanged<int> onActivate,
  required VoidCallback onBack,
  required VoidCallback onCloseOverlay,
  required String closeMenuLabel,
  required String specialKeysLabel,
  Set<int> favoriteIndices = const {},
  Widget? favoriteHintWidget,
}) {
  Widget sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Builds a 3-column grid for a range of key indices [start]..[end).
  Widget sectionGrid(int start, int end) {
    final count = end - start;
    final rows = (count + specialKeyCols - 1) ~/ specialKeyCols;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int r = 0; r < rows; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (int c = 0; c < specialKeyCols; c++)
                  Expanded(
                    child: () {
                      final flatIdx = start + r * specialKeyCols + c;
                      if (flatIdx >= end) return const SizedBox.shrink();
                      final entry = specialKeys[flatIdx];
                      return Padding(
                        padding: EdgeInsets.only(
                          left: c == 0 ? 0 : 4,
                          right: c == specialKeyCols - 1 ? 0 : 4,
                        ),
                        child: buildKeyChip(
                          descriptionResolver(entry.$1),
                          () => onActivate(flatIdx),
                          focused: flatIdx == focusedIndex,
                          subtitle: entry.$2,
                          isFavorite: favoriteIndices.contains(flatIdx),
                        ),
                      );
                    }(),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white54, size: 20),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(
              specialKeysLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),

      if (favoriteHintWidget != null) ...[
        const SizedBox(height: 4),
        Center(child: favoriteHintWidget),
        const SizedBox(height: 4),
      ],

      sectionHeader('WINDOW'),
      sectionGrid(0, 10),

      sectionHeader('INPUT'),
      sectionGrid(10, 16),

      sectionHeader('SYSTEM'),
      sectionGrid(16, 22),

      sectionHeader('MEDIA'),
      sectionGrid(22, 26),

      const SizedBox(height: 16),
      _CloseTile(label: closeMenuLabel, onTap: onCloseOverlay),
    ],
  );
}

// ─── Key chip ───────────────────────────────────────────────────────────────

/// A single key chip used in the special-keys grid.
Widget buildKeyChip(
  String label,
  VoidCallback onTap, {
  bool focused = false,
  Color? accentColor,
  String? subtitle,
  bool isFavorite = false,
}) {
  final chipAccent = accentColor ?? Colors.white54;
  return _TapFeedbackChip(
    onTap: onTap,
    focused: focused,
    chipAccent: chipAccent,
    label: label,
    subtitle: subtitle,
    isFavorite: isFavorite,
  );
}

/// Animated chip with tap feedback: scale pulse + horizontal shake.
///
/// On activation the chip briefly scales down (90%) then shakes horizontally
/// (±3 px, 3 oscillations over 300 ms) so the user gets clear visual
/// confirmation the key was sent.
class _TapFeedbackChip extends StatefulWidget {
  final VoidCallback onTap;
  final bool focused;
  final Color chipAccent;
  final String label;
  final String? subtitle;
  final bool isFavorite;

  const _TapFeedbackChip({
    required this.onTap,
    required this.focused,
    required this.chipAccent,
    required this.label,
    this.subtitle,
    this.isFavorite = false,
  });

  @override
  State<_TapFeedbackChip> createState() => _TapFeedbackChipState();
}

class _TapFeedbackChipState extends State<_TapFeedbackChip>
    with TickerProviderStateMixin {
  // ── Scale pulse ──
  late final AnimationController _scaleCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  );
  late final Animation<double> _scale = Tween<double>(begin: 1.0, end: 0.90)
      .animate(CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeInOut));

  // ── Horizontal shake ──
  late final AnimationController _shakeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void dispose() {
    _scaleCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    // Scale pulse
    _scaleCtrl.forward().then((_) => _scaleCtrl.reverse());
    // Shake — reset if already running
    _shakeCtrl.reset();
    _shakeCtrl.forward();
    // Haptic
    HapticFeedback.lightImpact();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _shakeCtrl,
        builder: (context, child) {
          // 3 oscillations over 0→1: sin(3 * 2π * t) * amplitude * (1-t)
          final t = _shakeCtrl.value;
          final dx = t == 0.0
              ? 0.0
              : math.sin(3 * 2 * math.pi * t) * 3.0 * (1.0 - t);
          return Transform.translate(
            offset: Offset(dx, 0),
            child: child,
          );
        },
        child: ScaleTransition(
          scale: _scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: widget.focused
                  ? widget.chipAccent.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.focused ? widget.chipAccent : Colors.white12,
                width: widget.focused ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.isFavorite) ...[
                      const Text('⭐', style: TextStyle(fontSize: 9)),
                      const SizedBox(width: 3),
                    ],
                    Flexible(
                      child: Text(
                        widget.label,
                        style: TextStyle(
                          color: widget.focused ? Colors.white : Colors.white70,
                          fontSize: 12,
                          fontWeight:
                              widget.focused ? FontWeight.w700 : FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle!,
                    style: TextStyle(
                      color:
                          widget.focused ? Colors.white54 : Colors.white30,
                      fontSize: 9,
                      fontWeight: FontWeight.w400,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CloseTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.close, color: Colors.white54, size: 20),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 14),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      hoverColor: Colors.white10,
    );
  }
}

// LogicalKeyboardKey to Windows VK code mapping
//
// Used by game_stream_screen to forward desktop keyboard events to the stream.
// Returns null for unmapped keys (gamepad buttons, etc.).

int? logicalKeyToVk(LogicalKeyboardKey key) => _logicalToVk[key];

final Map<LogicalKeyboardKey, int> _logicalToVk = {
  // Letters A-Z → VK 0x41-0x5A
  LogicalKeyboardKey.keyA: 0x41, LogicalKeyboardKey.keyB: 0x42,
  LogicalKeyboardKey.keyC: 0x43, LogicalKeyboardKey.keyD: 0x44,
  LogicalKeyboardKey.keyE: 0x45, LogicalKeyboardKey.keyF: 0x46,
  LogicalKeyboardKey.keyG: 0x47, LogicalKeyboardKey.keyH: 0x48,
  LogicalKeyboardKey.keyI: 0x49, LogicalKeyboardKey.keyJ: 0x4A,
  LogicalKeyboardKey.keyK: 0x4B, LogicalKeyboardKey.keyL: 0x4C,
  LogicalKeyboardKey.keyM: 0x4D, LogicalKeyboardKey.keyN: 0x4E,
  LogicalKeyboardKey.keyO: 0x4F, LogicalKeyboardKey.keyP: 0x50,
  LogicalKeyboardKey.keyQ: 0x51, LogicalKeyboardKey.keyR: 0x52,
  LogicalKeyboardKey.keyS: 0x53, LogicalKeyboardKey.keyT: 0x54,
  LogicalKeyboardKey.keyU: 0x55, LogicalKeyboardKey.keyV: 0x56,
  LogicalKeyboardKey.keyW: 0x57, LogicalKeyboardKey.keyX: 0x58,
  LogicalKeyboardKey.keyY: 0x59, LogicalKeyboardKey.keyZ: 0x5A,

  // Digits 0-9 → VK 0x30-0x39
  LogicalKeyboardKey.digit0: 0x30, LogicalKeyboardKey.digit1: 0x31,
  LogicalKeyboardKey.digit2: 0x32, LogicalKeyboardKey.digit3: 0x33,
  LogicalKeyboardKey.digit4: 0x34, LogicalKeyboardKey.digit5: 0x35,
  LogicalKeyboardKey.digit6: 0x36, LogicalKeyboardKey.digit7: 0x37,
  LogicalKeyboardKey.digit8: 0x38, LogicalKeyboardKey.digit9: 0x39,

  // F-keys (F1–F24)
  LogicalKeyboardKey.f1: 0x70, LogicalKeyboardKey.f2: 0x71,
  LogicalKeyboardKey.f3: 0x72, LogicalKeyboardKey.f4: 0x73,
  LogicalKeyboardKey.f5: 0x74, LogicalKeyboardKey.f6: 0x75,
  LogicalKeyboardKey.f7: 0x76, LogicalKeyboardKey.f8: 0x77,
  LogicalKeyboardKey.f9: 0x78, LogicalKeyboardKey.f10: 0x79,
  LogicalKeyboardKey.f11: 0x7A, LogicalKeyboardKey.f12: 0x7B,
  LogicalKeyboardKey.f13: 0x7C, LogicalKeyboardKey.f14: 0x7D,
  LogicalKeyboardKey.f15: 0x7E, LogicalKeyboardKey.f16: 0x7F,
  LogicalKeyboardKey.f17: 0x80, LogicalKeyboardKey.f18: 0x81,
  LogicalKeyboardKey.f19: 0x82, LogicalKeyboardKey.f20: 0x83,
  LogicalKeyboardKey.f21: 0x84, LogicalKeyboardKey.f22: 0x85,
  LogicalKeyboardKey.f23: 0x86, LogicalKeyboardKey.f24: 0x87,

  // Modifiers
  LogicalKeyboardKey.shiftLeft: 0xA0, LogicalKeyboardKey.shiftRight: 0xA1,
  LogicalKeyboardKey.controlLeft: 0xA2, LogicalKeyboardKey.controlRight: 0xA3,
  LogicalKeyboardKey.altLeft: 0xA4, LogicalKeyboardKey.altRight: 0xA5,
  LogicalKeyboardKey.metaLeft: 0x5B, LogicalKeyboardKey.metaRight: 0x5C,
  LogicalKeyboardKey.capsLock: 0x14,

  // Navigation
  LogicalKeyboardKey.arrowUp: 0x26, LogicalKeyboardKey.arrowDown: 0x28,
  LogicalKeyboardKey.arrowLeft: 0x25, LogicalKeyboardKey.arrowRight: 0x27,
  LogicalKeyboardKey.home: 0x24, LogicalKeyboardKey.end: 0x23,
  LogicalKeyboardKey.pageUp: 0x21, LogicalKeyboardKey.pageDown: 0x22,
  LogicalKeyboardKey.insert: 0x2D, LogicalKeyboardKey.delete: 0x2E,

  // Whitespace / control
  LogicalKeyboardKey.enter: 0x0D, LogicalKeyboardKey.tab: 0x09,
  LogicalKeyboardKey.space: 0x20, LogicalKeyboardKey.backspace: 0x08,
  LogicalKeyboardKey.escape: 0x1B,

  // Punctuation / symbols
  LogicalKeyboardKey.semicolon: 0xBA, LogicalKeyboardKey.equal: 0xBB,
  LogicalKeyboardKey.comma: 0xBC, LogicalKeyboardKey.minus: 0xBD,
  LogicalKeyboardKey.period: 0xBE, LogicalKeyboardKey.slash: 0xBF,
  LogicalKeyboardKey.backquote: 0xC0, LogicalKeyboardKey.bracketLeft: 0xDB,
  LogicalKeyboardKey.backslash: 0xDC, LogicalKeyboardKey.bracketRight: 0xDD,
  LogicalKeyboardKey.quoteSingle: 0xDE,

  // Numpad
  LogicalKeyboardKey.numpad0: 0x60, LogicalKeyboardKey.numpad1: 0x61,
  LogicalKeyboardKey.numpad2: 0x62, LogicalKeyboardKey.numpad3: 0x63,
  LogicalKeyboardKey.numpad4: 0x64, LogicalKeyboardKey.numpad5: 0x65,
  LogicalKeyboardKey.numpad6: 0x66, LogicalKeyboardKey.numpad7: 0x67,
  LogicalKeyboardKey.numpad8: 0x68, LogicalKeyboardKey.numpad9: 0x69,
  LogicalKeyboardKey.numpadMultiply: 0x6A, LogicalKeyboardKey.numpadAdd: 0x6B,
  LogicalKeyboardKey.numpadSubtract: 0x6D,
  LogicalKeyboardKey.numpadDecimal: 0x6E,
  LogicalKeyboardKey.numpadDivide: 0x6F, LogicalKeyboardKey.numpadEnter: 0x0D,
  LogicalKeyboardKey.numLock: 0x90,

  // Media
  LogicalKeyboardKey.audioVolumeUp: 0xAF,
  LogicalKeyboardKey.audioVolumeDown: 0xAE,
  LogicalKeyboardKey.audioVolumeMute: 0xAD,
  LogicalKeyboardKey.mediaPlayPause: 0xB3,
  LogicalKeyboardKey.mediaStop: 0xB2,
  LogicalKeyboardKey.mediaTrackNext: 0xB0,
  LogicalKeyboardKey.mediaTrackPrevious: 0xB1,

  // Misc
  LogicalKeyboardKey.printScreen: 0x2C,
  LogicalKeyboardKey.scrollLock: 0x91,
  LogicalKeyboardKey.pause: 0x13,
  LogicalKeyboardKey.contextMenu: 0x5D,
};
