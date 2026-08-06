import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/tv/tv_detector.dart';
import '../services/http_api/game_art_file_service.dart';

class PosterImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final double? width;
  final double? height;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final Duration fadeInDuration;
  final Widget Function(BuildContext, String, dynamic)? errorWidget;
  final Widget Function(BuildContext, String)? placeholder;

  /// Stable disk-cache key. Host /appasset URLs embed the server address:port,
  /// so caching by URL re-downloads the same art per server and on IP changes.
  /// Pass NvApp.artCacheKey(...) to share one cached copy across servers.
  final String? cacheKey;

  const PosterImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.memCacheWidth,
    this.memCacheHeight,
    this.fadeInDuration = const Duration(milliseconds: 200),
    this.errorWidget,
    this.placeholder,
    this.cacheKey,
  });

  /// Long-lived disk cache for game art. Art rarely changes; keeping it for
  /// 90 days means re-entering a server (or another server with the same
  /// game) loads from disk instead of the network.
  static final CacheManager artCacheManager = CacheManager(
    Config(
      'gameArtCacheV2',
      stalePeriod: const Duration(days: 90),
      maxNrOfCacheObjects: 800,
      fileService: gameArtFileService,
    ),
  );

  static bool isLocalFile(String url) => url.startsWith('file://');

  static ImageProvider<Object> providerFor(
    String url, {
    String? cacheKey,
    int? maxWidth,
    int? maxHeight,
  }) {
    if (isLocalFile(url)) {
      return FileImage(File(url.replaceFirst('file://', '')));
    }
    return CachedNetworkImageProvider(
      url,
      cacheKey: cacheKey,
      cacheManager: artCacheManager,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  /// Caps the decode width at the user's Image quality setting.
  ///
  /// Every caller passed a hardcoded memCacheWidth and nothing ever read
  /// artQualityCacheWidth, so the setting did nothing at all. Applying it here
  /// covers all of them at once. It only ever lowers the width — a caller that
  /// already asks for less than the cap keeps its own value.
  int? _effectiveCacheWidth(BuildContext context) {
    // PosterImage is a leaf widget used all over the app, including in trees
    // that do not carry a ThemeProvider (tests, isolated previews). Reading it
    // unconditionally turned a missing provider into a build-time throw, so a
    // widget that only needed a size hint could take a whole screen down.
    int? cap;
    try {
      cap = context.select<ThemeProvider, int?>((t) => t.artQualityCacheWidth);
    } on ProviderNotFoundException {
      cap = null;
    }
    if (cap == null) return memCacheWidth;
    if (memCacheWidth == null) return cap;
    return memCacheWidth! < cap ? memCacheWidth : cap;
  }

  @override
  Widget build(BuildContext context) {
    final cacheWidth = _effectiveCacheWidth(context);
    // A fade runs even when the image is already decoded in memory, so every
    // poster the D-pad passes over looks like it is still loading. On a TV the
    // grid should just be there.
    final fade = TvDetector.instance.isTV ? Duration.zero : fadeInDuration;

    if (isLocalFile(url)) {
      final path = url.replaceFirst('file://', '');
      return Image.file(
        File(path),
        fit: fit,
        alignment: alignment,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        cacheHeight: memCacheHeight,
        errorBuilder: (ctx, err, stack) =>
            errorWidget?.call(ctx, url, err) ?? const SizedBox.shrink(),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      cacheKey: cacheKey,
      cacheManager: artCacheManager,
      fit: fit,
      alignment: alignment,
      width: width,
      height: height,
      memCacheWidth: cacheWidth,
      memCacheHeight: memCacheHeight,
      fadeInDuration: fade,
      placeholderFadeInDuration: fade,
      errorWidget: errorWidget,
      placeholder: placeholder,
    );
  }
}
