import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('background quality targets 1080p with a 720p floor', () async {
    SharedPreferences.setMockInitialValues({'art_quality': 'high'});
    final high = await ThemeProvider.load();
    expect(high.backgroundArtCacheWidth, 1920);

    SharedPreferences.setMockInitialValues({'art_quality': 'medium'});
    final medium = await ThemeProvider.load();
    expect(medium.backgroundArtCacheWidth, 1280);

    SharedPreferences.setMockInitialValues({
      'art_quality': 'high',
      'performance_mode': true,
    });
    final performance = await ThemeProvider.load();
    expect(performance.backgroundArtCacheWidth, 1280);
  });
}
