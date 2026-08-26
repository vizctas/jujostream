import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/nv_app.dart';
import 'package:jujostream/providers/app_list_provider.dart';

void main() {
  test('content equality detects hero and gallery changes', () {
    final base = NvApp(
      appId: 1,
      appName: 'Hades',
      heroImageUrl: 'https://host/hero.jpg',
      screenshotUrls: const ['https://host/shot-1.jpg'],
    );

    expect(
      base.contentEquals(
        base.copyWith(heroImageUrl: 'https://host/hero-new.jpg'),
      ),
      isFalse,
    );
    expect(
      base.contentEquals(
        base.copyWith(
          screenshotUrls: const [
            'https://host/shot-1.jpg',
            'https://host/shot-2.jpg',
          ],
        ),
      ),
      isFalse,
    );
    expect(
      base.contentEquals(
        base.copyWith(steamBackgroundUrl: 'https://steam/background.jpg'),
      ),
      isFalse,
    );
  });

  test('host app normalization preserves hero and complete gallery', () {
    final hostApp = NvApp(
      appId: 7,
      appName: 'Hades\u200B',
      posterUrl: 'https://host/poster.jpg',
      heroImageUrl: 'https://host/hero.jpg',
      screenshotUrls: const [
        'https://host/shot-1.jpg',
        'https://host/shot-2.jpg',
      ],
    );

    final normalized = normalizeHostApp(hostApp, runningId: 7);

    expect(normalized.appName, 'Hades');
    expect(normalized.isRunning, isTrue);
    expect(normalized.posterUrl, hostApp.posterUrl);
    expect(normalized.heroImageUrl, hostApp.heroImageUrl);
    expect(normalized.screenshotUrls, hostApp.screenshotUrls);
  });

  test('art cache key changes when source artwork changes', () {
    final first = NvApp(
      appId: 1,
      appName: 'Hades',
      serverUuid: 'server',
      posterUrl: 'https://host/first-poster.jpg',
    );
    final second = NvApp(
      appId: 1,
      appName: 'Hades',
      serverUuid: 'server',
      posterUrl: 'https://host/new-poster.jpg',
    );

    expect(first.artCacheKey('poster'), isNot(second.artCacheKey('poster')));
    expect(first.artCacheKey('poster'), startsWith('nvart_v3_'));
  });

  test('host artwork cache survives address and session-id changes', () {
    final first = NvApp(
      appId: 7,
      appName: 'Hades',
      serverUuid: 'server',
      posterUrl:
          'https://192.168.3.6:47984/appasset?uniqueid=one&appid=7&AssetType=2&AssetIdx=0',
    );
    final second = NvApp(
      appId: 7,
      appName: 'Hades',
      serverUuid: 'server',
      posterUrl:
          'https://192.168.3.9:47984/appasset?uniqueid=two&appid=7&AssetType=2&AssetIdx=0',
    );

    expect(first.artCacheKey('poster'), second.artCacheKey('poster'));
  });

  test('landscape background getter never promotes poster', () {
    final app = NvApp(
      appId: 1,
      appName: 'Hades',
      posterUrl: 'https://host/poster.jpg',
    );

    expect(app.backgroundUrl, isNull);
  });

  test('official Steam background persists and is preferred over RAWG', () {
    final app = NvApp(
      appId: 1,
      appName: 'Hades',
      steamBackgroundUrl: 'https://steam/background.jpg',
      rawgBackgroundUrl: 'https://rawg/background.jpg',
    );

    final restored = NvApp.fromJson(app.toJson());

    expect(restored.steamBackgroundUrl, app.steamBackgroundUrl);
    expect(restored.backgroundUrl, app.steamBackgroundUrl);
    expect(restored.backgroundCacheKey, app.artCacheKey('steambg'));
  });
}
