import '../../models/nv_app.dart';

enum GameBackdropRole { hero, poster, none }

class GameBackdropSelection {
  const GameBackdropSelection({required this.role, this.url, this.cacheKey});

  final GameBackdropRole role;
  final String? url;
  final String? cacheKey;

  bool get hasArt => role != GameBackdropRole.none && url != null;
}

class GameArtPolicy {
  const GameArtPolicy._();

  static GameBackdropSelection selectBackdrop(NvApp app) {
    final hostHero = _usable(app.heroImageUrl);
    if (hostHero != null) {
      return GameBackdropSelection(
        role: GameBackdropRole.hero,
        url: hostHero,
        cacheKey: app.artCacheKey('hero'),
      );
    }

    final steamHero = _usable(app.steamBackgroundUrl);
    if (steamHero != null) {
      return GameBackdropSelection(
        role: GameBackdropRole.hero,
        url: steamHero,
        cacheKey: app.artCacheKey('steambg'),
      );
    }

    final providerHero = _usable(app.rawgBackgroundUrl);
    if (providerHero != null) {
      return GameBackdropSelection(
        role: GameBackdropRole.hero,
        url: providerHero,
        cacheKey: app.artCacheKey('rawgbg'),
      );
    }

    final poster = _usable(app.posterUrl);
    if (poster != null) {
      return GameBackdropSelection(
        role: GameBackdropRole.poster,
        url: poster,
        cacheKey: app.artCacheKey('poster'),
      );
    }

    return const GameBackdropSelection(role: GameBackdropRole.none);
  }

  static NvApp applyProviderArtwork(
    NvApp app, {
    String? primaryBackgroundUrl,
    Iterable<String> screenshots = const [],
  }) {
    return app.copyWith(
      rawgBackgroundUrl: _usable(primaryBackgroundUrl),
      screenshotUrls: mergeGallery([...app.screenshotUrls, ...screenshots]),
    );
  }

  static List<String> mergeGallery(
    Iterable<String> images, {
    int maxImages = 8,
  }) {
    final unique = <String>{};
    for (final image in images) {
      final clean = image.trim();
      if (clean.isNotEmpty) unique.add(clean);
      if (unique.length == maxImages) break;
    }
    return List<String>.unmodifiable(unique);
  }

  static bool isEligibleHero({required int width, required int height}) {
    if (width < 1280 || height < 720) return false;
    return width / height >= 1.4;
  }

  static String? _usable(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}
