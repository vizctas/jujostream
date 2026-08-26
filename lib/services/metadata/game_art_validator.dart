import 'dart:io';
import 'dart:ui' as ui;

import '../../widgets/poster_image.dart';
import 'artwork_cache_recovery.dart';
import 'game_art_policy.dart';

class GameHeroProbe {
  const GameHeroProbe({required this.width, required this.height});

  final int width;
  final int height;

  bool get isEligible =>
      GameArtPolicy.isEligibleHero(width: width, height: height);

  bool isEligibleFor({
    required double viewportWidth,
    required double viewportHeight,
  }) {
    return GameArtPolicy.isEligibleHeroForViewport(
      width: width,
      height: height,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
    );
  }

  double retainedFractionFor({
    required double viewportWidth,
    required double viewportHeight,
  }) {
    return GameArtPolicy.coverRetainedFraction(
      width: width,
      height: height,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
    );
  }
}

class GameArtValidator {
  GameArtValidator._();

  static final Map<String, Future<GameHeroProbe>> _heroChecks = {};

  static Future<bool> isEligibleHero(String url, {String? cacheKey}) {
    return probeHero(url, cacheKey: cacheKey).then((probe) => probe.isEligible);
  }

  static Future<GameHeroProbe> probeHero(String url, {String? cacheKey}) {
    final key = cacheKey ?? url;
    return _heroChecks.putIfAbsent(
      key,
      () => _probeWithRecovery(url, cacheKey),
    );
  }

  static Future<GameHeroProbe> _probeWithRecovery(
    String url,
    String? cacheKey,
  ) async {
    final firstProbe = await _probe(url, cacheKey);
    if (firstProbe.isEligible || PosterImage.isLocalFile(url)) {
      return firstProbe;
    }

    final identity = cacheKey ?? url;
    final provider = PosterImage.providerFor(url, cacheKey: cacheKey);
    final recovered = await ArtworkCacheRecovery.instance.recoverOnce(
      identity: identity,
      evict: () async {
        await PosterImage.artCacheManager.removeFile(identity);
        await provider.evict();
      },
    );
    return recovered ? _probe(url, cacheKey) : firstProbe;
  }

  static Future<GameHeroProbe> _probe(String url, String? cacheKey) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      final File file;
      if (PosterImage.isLocalFile(url)) {
        file = File(url.replaceFirst('file://', ''));
      } else if (cacheKey != null) {
        file = await PosterImage.artCacheManager.getSingleFile(
          url,
          key: cacheKey,
        );
      } else {
        file = await PosterImage.artCacheManager.getSingleFile(url);
      }
      buffer = await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes());
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return GameHeroProbe(width: descriptor.width, height: descriptor.height);
    } catch (_) {
      return const GameHeroProbe(width: 0, height: 0);
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
