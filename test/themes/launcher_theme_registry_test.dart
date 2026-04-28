import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/themes/launcher_theme.dart';
import 'package:jujostream/themes/launcher_theme_registry.dart';

void main() {
  test('Big Screen launcher theme is registered and discoverable', () {
    expect(LauncherThemeRegistry.allIds, contains(LauncherThemeId.bigScreen));
    expect(
      LauncherThemeRegistry.fromName('bigScreen'),
      LauncherThemeId.bigScreen,
    );
    expect(
      LauncherThemeRegistry.get(LauncherThemeId.bigScreen).id,
      LauncherThemeId.bigScreen,
    );
    expect(
      LauncherThemeRegistry.label(LauncherThemeId.bigScreen),
      'Big Screen',
    );
  });
}
