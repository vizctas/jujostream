import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('launcher theme game posters always provide stable cache keys', () {
    const files = [
      'lib/themes/backbone/backbone_theme.dart',
      'lib/themes/hero/hero_theme.dart',
      'lib/themes/ps5/ps5_theme.dart',
    ];
    final posterCall = RegExp(
      r'PosterImage\(\s*url:\s*([as])\.posterUrl!',
      multiLine: true,
    );
    final keyedPosterCall = RegExp(
      r"PosterImage\(\s*url:\s*([as])\.posterUrl!,\s*"
      r"cacheKey:\s*\1\.artCacheKey\('poster'\),",
      multiLine: true,
    );

    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(
        keyedPosterCall.allMatches(source).length,
        posterCall.allMatches(source).length,
        reason: '$path contains a game poster without NvApp.artCacheKey',
      );
    }

    final bigScreen = File(
      'lib/themes/big_screen/big_screen_theme.dart',
    ).readAsStringSync();
    expect(bigScreen, contains("cacheKey: app.artCacheKey('poster')"));
  });
}
