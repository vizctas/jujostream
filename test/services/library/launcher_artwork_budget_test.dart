import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/services/library/launcher_artwork_budget.dart';
import 'package:jujostream/themes/launcher_theme.dart';

void main() {
  test('poster prefetch matches each rendered launcher role', () {
    expect(
      LauncherArtworkBudget.posterPrefetchWidth(
        LauncherThemeId.classic,
        grid: false,
      ),
      300,
    );
    expect(
      LauncherArtworkBudget.posterPrefetchWidth(
        LauncherThemeId.bigScreen,
        grid: false,
      ),
      320,
    );
    expect(
      LauncherArtworkBudget.posterPrefetchWidth(
        LauncherThemeId.ps5,
        grid: false,
      ),
      240,
    );
    expect(
      LauncherArtworkBudget.posterPrefetchWidth(
        LauncherThemeId.hero,
        grid: true,
      ),
      400,
    );
  });

  test('Big Screen reserves larger decode only for selected card', () {
    expect(LauncherArtworkBudget.bigScreenPosterWidth(selected: false), 320);
    expect(LauncherArtworkBudget.bigScreenPosterWidth(selected: true), 640);
  });
}
