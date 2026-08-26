import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/nv_app.dart';
import 'package:jujostream/services/metadata/game_art_policy.dart';

void main() {
  test('selects hero before provider background and poster', () {
    final app = NvApp(
      appId: 1,
      appName: 'Hades',
      posterUrl: 'poster',
      heroImageUrl: 'host-hero',
      rawgBackgroundUrl: 'provider-hero',
    );

    final selected = GameArtPolicy.selectBackdrop(app);

    expect(selected.role, GameBackdropRole.hero);
    expect(selected.url, 'host-hero');
  });

  test('selects provider hero before Steam close-up and poster', () {
    final app = NvApp(
      appId: 1,
      appName: 'Hades',
      posterUrl: 'poster',
      steamBackgroundUrl: 'steam-background',
      rawgBackgroundUrl: 'rawg-background',
    );

    final selected = GameArtPolicy.selectBackdrop(app);

    expect(selected.role, GameBackdropRole.hero);
    expect(selected.url, 'rawg-background');
    expect(selected.cacheKey, app.artCacheKey('rawgbg'));
  });

  test('provider screenshots join gallery without replacing poster', () {
    final app = NvApp(
      appId: 1,
      appName: 'Hades',
      posterUrl: 'host-poster',
      screenshotUrls: const ['host-shot', 'duplicate'],
    );

    final enriched = GameArtPolicy.applyProviderArtwork(
      app,
      primaryBackgroundUrl: 'provider-hero',
      screenshots: const ['duplicate', 'provider-shot'],
    );

    expect(enriched.posterUrl, 'host-poster');
    expect(enriched.rawgBackgroundUrl, 'provider-hero');
    expect(enriched.screenshotUrls, [
      'host-shot',
      'duplicate',
      'provider-shot',
    ]);
  });

  test('gallery is deduplicated and bounded to eight images', () {
    final gallery = GameArtPolicy.mergeGallery([
      'shot-1',
      'shot-1',
      for (var i = 2; i <= 10; i++) 'shot-$i',
    ]);

    expect(gallery, hasLength(8));
    expect(gallery.toSet(), hasLength(8));
  });

  test('full-screen hero accepts dedicated landscape and panoramic art', () {
    expect(GameArtPolicy.isEligibleHero(width: 1920, height: 1080), isTrue);
    expect(GameArtPolicy.isEligibleHero(width: 1280, height: 720), isTrue);
    expect(GameArtPolicy.isEligibleHero(width: 1920, height: 620), isTrue);
    expect(GameArtPolicy.isEligibleHero(width: 3840, height: 1240), isTrue);
    expect(GameArtPolicy.isEligibleHero(width: 900, height: 600), isFalse);
    expect(GameArtPolicy.isEligibleHero(width: 1080, height: 1920), isFalse);
  });

  test('evaluates fullscreen artwork against the actual viewport', () {
    expect(
      GameArtPolicy.isEligibleHeroForViewport(
        width: 1280,
        height: 720,
        viewportWidth: 1920,
        viewportHeight: 1080,
      ),
      isTrue,
    );
    expect(
      GameArtPolicy.isEligibleHeroForViewport(
        width: 1600,
        height: 400,
        viewportWidth: 1280,
        viewportHeight: 800,
      ),
      isFalse,
    );
    expect(
      GameArtPolicy.coverRetainedFraction(
        width: 1280,
        height: 720,
        viewportWidth: 1024,
        viewportHeight: 768,
      ),
      closeTo(0.75, 0.001),
    );
  });

  test('exposes hero candidates in fallback order', () {
    final app = NvApp(
      appId: 1,
      appName: 'Hades',
      heroImageUrl: 'host',
      steamBackgroundUrl: 'steam',
      rawgBackgroundUrl: 'rawg',
      posterUrl: 'poster',
    );

    expect(
      GameArtPolicy.heroCandidates(app).map((candidate) => candidate.url),
      ['host', 'rawg', 'steam'],
    );
    expect(GameArtPolicy.posterFallback(app).url, 'poster');
  });

  test('poster-only app selects premium fallback, not portrait art', () {
    final selected = GameArtPolicy.selectBackdrop(
      NvApp(appId: 1, appName: 'Hades', posterUrl: 'poster'),
    );

    expect(selected.role, GameBackdropRole.none);
    expect(selected.url, isNull);
  });
}
