import 'package:flutter/services.dart';

enum SettingsPageDelta { previous, next }

/// Maps page-level shortcuts. Only the gamepad shoulder buttons cycle pages:
/// stealing arrowLeft/arrowRight at the outer boundary made every horizontal
/// list, slider and chip row inside a page unreachable with a TV remote. The
/// remote switches pages by focusing the tab strip and pressing select.
SettingsPageDelta? settingsPageDeltaForKey(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.gameButtonRight1) {
    return SettingsPageDelta.next;
  }
  if (key == LogicalKeyboardKey.gameButtonLeft1) {
    return SettingsPageDelta.previous;
  }
  return null;
}
