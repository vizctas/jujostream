import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/screens/settings/settings_remote_navigation.dart';

void main() {
  test('D-pad horizontal arrows switch settings pages', () {
    expect(
      settingsPageDeltaForKey(LogicalKeyboardKey.arrowRight),
      SettingsPageDelta.next,
    );
    expect(
      settingsPageDeltaForKey(LogicalKeyboardKey.arrowLeft),
      SettingsPageDelta.previous,
    );
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
