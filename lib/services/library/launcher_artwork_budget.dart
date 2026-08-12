import '../../themes/launcher_theme.dart';

class LauncherArtworkBudget {
  const LauncherArtworkBudget._();

  static int posterPrefetchWidth(LauncherThemeId theme, {required bool grid}) {
    if (grid) return 400;
    return switch (theme) {
      LauncherThemeId.bigScreen => 320,
      LauncherThemeId.backbone => 340,
      LauncherThemeId.ps5 => 240,
      LauncherThemeId.hero => 200,
      LauncherThemeId.classic => 300,
    };
  }

  static int bigScreenPosterWidth({required bool selected}) =>
      selected ? 640 : 320;
}
