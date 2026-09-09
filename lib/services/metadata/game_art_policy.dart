import 'package:flutter/widgets.dart';

import '../../models/nv_app.dart';

enum GameBackdropRole { hero, poster, none }

class GameBackdropSelection {
  const GameBackdropSelection({
    required this.role,
    this.url,
    this.cacheKey,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final GameBackdropRole role;
  final String? url;
  final String? cacheKey;

  /// How the accepted hero is placed in the viewport. Wide Steam-style heroes
  /// (3.1:1) are shown whole, pinned to the top, instead of being cover-zoomed.
  final BoxFit fit;
  final Alignment alignment;

  bool get hasArt => role != GameBackdropRole.none && url != null;

  GameBackdropSelection withFit(BoxFit fit, Alignment alignment) =>
      GameBackdropSelection(
        role: role,
        url: url,
        cacheKey: cacheKey,
        fit: fit,
        alignment: alignment,
      );
}

class GameArtPolicy {
  const GameArtPolicy._();

  static GameBackdropSelection selectBackdrop(NvApp app) {
    final candidates = heroCandidates(app);
    if (candidates.isNotEmpty) return candidates.first;
    return const GameBackdropSelection(role: GameBackdropRole.none);
  }

  static List<GameBackdropSelection> heroCandidates(NvApp app) {
    final candidates = <GameBackdropSelection>[];
    final seen = <String>{};

    void add(String? value, String cacheKind) {
      final url = _usable(value);
      if (url == null || !seen.add(url)) return;
      candidates.add(
        GameBackdropSelection(
          role: GameBackdropRole.hero,
          url: url,
          cacheKey: app.artCacheKey(cacheKind),
        ),
      );
    }

    // Prefer curated/provider artwork over Steam background_raw images. The
    // latter are often landscape close-ups rather than composed heroes.
    add(app.heroImageUrl, 'hero');
    add(app.rawgBackgroundUrl, 'rawgbg');
    add(app.steamBackgroundUrl, 'steambg');
    return List.unmodifiable(candidates);
  }

  static GameBackdropSelection posterFallback(NvApp app) {
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
    if (width < 960 || height < 360) return false;
    final aspect = width / height;
    return aspect >= 1.4 && aspect <= 4.2;
  }

  /// Fraction of source content retained when rendered with [BoxFit.cover].
  static double coverRetainedFraction({
    required int width,
    required int height,
    required double viewportWidth,
    required double viewportHeight,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        viewportWidth <= 0 ||
        viewportHeight <= 0) {
      return 0;
    }
    final imageAspect = width / height;
    final viewportAspect = viewportWidth / viewportHeight;
    return imageAspect < viewportAspect
        ? imageAspect / viewportAspect
        : viewportAspect / imageAspect;
  }

  /// Cover keeps composition when little is cropped. Heroes much wider than
  /// the viewport (Steam `library_hero` is 3.1:1) would lose ~40% to a cover
  /// zoom, so they render whole, pinned to the top, over the fallback colour.
  /// Taller viewports (phones) always cover: a pillarboxed banner is worse.
  static const coverMaxCrop = 0.20;

  static ({BoxFit fit, Alignment alignment}) heroFitFor({
    required int width,
    required int height,
    required double viewportWidth,
    required double viewportHeight,
  }) {
    if (width <= 0 || height <= 0 || viewportWidth <= 0 || viewportHeight <= 0) {
      return (fit: BoxFit.cover, alignment: Alignment.center);
    }
    final imageAspect = width / height;
    final viewportAspect = viewportWidth / viewportHeight;
    final wideEnoughToCrop = imageAspect > viewportAspect / (1 - coverMaxCrop);
    return wideEnoughToCrop
        ? (fit: BoxFit.fitWidth, alignment: Alignment.topCenter)
        : (fit: BoxFit.cover, alignment: Alignment.center);
  }

  static bool isEligibleHeroForViewport({
    required int width,
    required int height,
    required double viewportWidth,
    required double viewportHeight,
  }) {
    if (!isEligibleHero(width: width, height: height)) return false;
    return coverRetainedFraction(
          width: width,
          height: height,
          viewportWidth: viewportWidth,
          viewportHeight: viewportHeight,
        ) >=
        0.52;
  }

  static String? _usable(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}
