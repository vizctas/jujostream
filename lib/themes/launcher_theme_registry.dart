import 'launcher_theme.dart';
import 'classic/classic_theme.dart';
import 'backbone/backbone_theme.dart';
import 'ps5/ps5_theme.dart';
import 'hero/hero_theme.dart';
import 'big_screen/big_screen_theme.dart';

class LauncherThemeRegistry {
  LauncherThemeRegistry._();

  static final Map<LauncherThemeId, LauncherTheme> _themes = {
    LauncherThemeId.classic: ClassicTheme(),
    LauncherThemeId.bigScreen: BigScreenTheme(),
    LauncherThemeId.backbone: BackboneTheme(),
    LauncherThemeId.ps5: Ps5Theme(),
    LauncherThemeId.hero: HeroTheme(),
  };

  static LauncherTheme get(LauncherThemeId id) {
    return _themes[id] ?? _themes[LauncherThemeId.classic]!;
  }

  static List<LauncherTheme> get all => _themes.values.toList();

  static List<LauncherThemeId> get allIds => _themes.keys.toList();

  static LauncherThemeId fromName(String? name) {
    if (name == null) return LauncherThemeId.classic;
    return LauncherThemeId.values.firstWhere(
      (e) => e.name == name,
      orElse: () => LauncherThemeId.classic,
    );
  }

  static String label(LauncherThemeId id) {
    return switch (id) {
      LauncherThemeId.classic => 'Classic',
      LauncherThemeId.backbone => 'Backbone',
      LauncherThemeId.ps5 => 'PS5',
      LauncherThemeId.hero => 'Hero',
      LauncherThemeId.bigScreen => 'Big Screen',
    };
  }
}
