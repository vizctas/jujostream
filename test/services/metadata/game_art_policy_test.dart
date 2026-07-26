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

  test('selects official Steam background before RAWG and poster', () {
    final app = NvApp(
      appId: 1,
      appName: 'Hades',
      posterUrl: 'poster',
      steamBackgroundUrl: 'steam-background',
      rawgBackgroundUrl: 'rawg-background',
    );

    final selected = GameArtPolicy.selectBackdrop(app);

    expect(selected.role, GameBackdropRole.hero);
    expect(selected.url, 'steam-background');
    expect(selected.cacheKey, app.artCacheKey('steambg'));
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

  test('full-bleed hero requires landscape 720p minimum', () {
    expect(GameArtPolicy.isEligibleHero(width: 1920, height: 1080), isTrue);
    expect(GameArtPolicy.isEligibleHero(width: 1280, height: 720), isTrue);
    expect(GameArtPolicy.isEligibleHero(width: 1024, height: 576), isFalse);
    expect(GameArtPolicy.isEligibleHero(width: 1080, height: 1920), isFalse);
  });
}
