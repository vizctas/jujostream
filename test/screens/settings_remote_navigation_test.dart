import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/screens/settings/settings_remote_navigation.dart';

void main() {
  test('D-pad horizontal arrows stay with the focused control', () {
    // Stealing them at the page boundary made horizontal lists, sliders and
    // chip rows inside a settings page unreachable with a TV remote.
    expect(settingsPageDeltaForKey(LogicalKeyboardKey.arrowRight), isNull);
    expect(settingsPageDeltaForKey(LogicalKeyboardKey.arrowLeft), isNull);
  });

  test('controller shoulder shortcuts keep switching settings pages', () {
    expect(
      settingsPageDeltaForKey(LogicalKeyboardKey.gameButtonRight1),
      SettingsPageDelta.next,
    );
    expect(
      settingsPageDeltaForKey(LogicalKeyboardKey.gameButtonLeft1),
      SettingsPageDelta.previous,
    );
  });

  test('unrelated keys remain available to focused controls', () {
    expect(settingsPageDeltaForKey(LogicalKeyboardKey.arrowUp), isNull);
    expect(settingsPageDeltaForKey(LogicalKeyboardKey.enter), isNull);
  });
}
