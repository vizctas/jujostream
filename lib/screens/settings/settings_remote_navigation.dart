import 'package:flutter/services.dart';

enum SettingsPageDelta { previous, next }

/// Maps page-level remote shortcuts. Applied at the outer focus boundary so
/// focused sliders and other controls keep first refusal over arrow keys.
SettingsPageDelta? settingsPageDeltaForKey(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.gameButtonRight1) {
    return SettingsPageDelta.next;
  }
  if (key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.gameButtonLeft1) {
    return SettingsPageDelta.previous;
  }
  return null;
}
