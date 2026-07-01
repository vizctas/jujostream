import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class PosterImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
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
      'gameArtCache',
      stalePeriod: const Duration(days: 90),
      maxNrOfCacheObjects: 800,
    ),
  );

  static bool isLocalFile(String url) => url.startsWith('file://');

  @override
  Widget build(BuildContext context) {
    if (isLocalFile(url)) {
      final path = url.replaceFirst('file://', '');
      return Image.file(
        File(path),
        fit: fit,
        width: width,
        height: height,
        cacheWidth: memCacheWidth,
        cacheHeight: memCacheHeight,
        errorBuilder: (ctx, err, stack) =>
            errorWidget?.call(ctx, url, err) ??
            const SizedBox.shrink(),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      cacheKey: cacheKey,
      cacheManager: artCacheManager,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      fadeInDuration: fadeInDuration,
      errorWidget: errorWidget,
      placeholder: placeholder,
    );
  }
}
