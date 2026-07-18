import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/services/startup/startup_animation_preferences.dart';
import 'package:jujostream/services/startup/startup_animation_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'missing and unknown selections resolve to the cinematic default',
    () async {
      SharedPreferences.setMockInitialValues({});
      final missing = await StartupAnimationPreferences.load();
      expect(missing.selectedId, StartupAnimationRegistry.cinematicV1Id);

      SharedPreferences.setMockInitialValues({
        StartupAnimationPreferences.storageKey: 'future_animation',
      });
      final unknown = await StartupAnimationPreferences.load();
      expect(unknown.selectedId, StartupAnimationRegistry.cinematicV1Id);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(StartupAnimationPreferences.storageKey),
        'future_animation',
      );
    },
  );

  test('off persists as the selected startup animation', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await StartupAnimationPreferences.load();

    await preferences.setSelectedId(StartupAnimationRegistry.offId);

    final restored = await StartupAnimationPreferences.load();
    expect(restored.selectedId, StartupAnimationRegistry.offId);
    expect(restored.selected.buildsScreen, isFalse);
  });
}
