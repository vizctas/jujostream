import 'dart:io';
import 'dart:ui' as ui;

import '../../widgets/poster_image.dart';
import 'game_art_policy.dart';

class GameArtValidator {
  GameArtValidator._();

  static final Map<String, Future<bool>> _heroChecks = {};

  static Future<bool> isEligibleHero(String url, {String? cacheKey}) {
    final key = cacheKey ?? url;
    return _heroChecks.putIfAbsent(key, () => _probe(url, cacheKey));
  }

  static Future<bool> _probe(String url, String? cacheKey) async {
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
      return GameArtPolicy.isEligibleHero(
        width: descriptor.width,
        height: descriptor.height,
      );
    } catch (_) {
      return false;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
