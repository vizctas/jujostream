import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/services/metadata/game_art_policy.dart';

void main() {
  test('16:9 hero on a 16:9 viewport keeps cover', () {
    final fit = GameArtPolicy.heroFitFor(
      width: 1920,
      height: 1080,
      viewportWidth: 1920,
      viewportHeight: 1080,
    );
    expect(fit.fit, BoxFit.cover);
  });

  test('Steam 3.1:1 library hero is shown whole, pinned to the top', () {
    final fit = GameArtPolicy.heroFitFor(
      width: 3840,
      height: 1240,
      viewportWidth: 1920,
      viewportHeight: 1080,
    );
    expect(fit.fit, BoxFit.fitWidth);
    expect(fit.alignment, Alignment.topCenter);
  });

  test('mild 2:1 crop stays cover', () {
    final fit = GameArtPolicy.heroFitFor(
      width: 2000,
      height: 1000,
      viewportWidth: 1920,
      viewportHeight: 1080,
    );
    expect(fit.fit, BoxFit.cover);
  });
}
