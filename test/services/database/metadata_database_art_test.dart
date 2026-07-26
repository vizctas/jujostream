import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/nv_app.dart';
import 'package:jujostream/services/database/metadata_database.dart';

void main() {
  test('stored metadata preserves host poster and merges gallery', () {
    final host = NvApp(
      appId: 1,
      appName: 'Hades',
      posterUrl: 'host-poster',
      screenshotUrls: const ['host-shot'],
    );

    final merged = MetadataDatabase.mergeRowsForTest(
      [host],
      [
        {
          'app_id': 1,
          'game_name': 'Hades',
          'poster_url': 'legacy-rawg-screenshot',
          'screenshot_urls': jsonEncode(['host-shot', 'rawg-shot']),
        },
      ],
    ).single;

    expect(merged.posterUrl, 'host-poster');
    expect(merged.screenshotUrls, ['host-shot', 'rawg-shot']);
  });

  test('stored metadata restores official Steam background', () {
    final merged = MetadataDatabase.mergeRowsForTest(
      [NvApp(appId: 1, appName: 'Hades')],
      [
        {
          'app_id': 1,
          'game_name': 'Hades',
          'steam_background_url': 'https://steam/background.jpg',
        },
      ],
    ).single;

    expect(merged.steamBackgroundUrl, 'https://steam/background.jpg');
  });
}
