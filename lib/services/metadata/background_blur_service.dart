import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:cached_network_image/cached_network_image.dart';

class BackgroundBlurService {
  BackgroundBlurService._();
  static final instance = BackgroundBlurService._();

  final Map<String, ui.Image> _cache = {};

  final Set<String> _pending = {};

  static const int _maxCacheSize = 30;

  static const int _targetWidth = 360;

  static const double _blurSigma = 20.0;

  ui.Image? getCached(String url) => _cache[url];

  bool isAvailable(String url) => _cache.containsKey(url);
  bool isPending(String url) => _pending.contains(url);

  Future<ui.Image?> preBlur(String url) async {
    if (_cache.containsKey(url)) return _cache[url];
    if (_pending.contains(url)) {

      while (_pending.contains(url)) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _cache[url];
    }

    _pending.add(url);
    try {
      final image = await _processBlur(url);
      if (image != null) {
        _evictIfNeeded();
        _cache[url] = image;
      }
      return image;
    } finally {
      _pending.remove(url);
    }
  }

  void preBlurAsync(String url) {
    if (_cache.containsKey(url) || _pending.contains(url)) return;
    unawaited(preBlur(url));
  }

  Future<ui.Image?> _processBlur(String url) async {
    try {

      final provider = CachedNetworkImageProvider(url, maxWidth: _targetWidth);
      final completer = Completer<ImageInfo>();
      final stream = provider.resolve(ImageConfiguration.empty);
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete(info);
          stream.removeListener(listener);
        },
        onError: (error, _) {
          if (!completer.isCompleted) completer.completeError(error);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);

      final imageInfo = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Image load timeout'),
      );

      final srcImage = imageInfo.image;
      final srcWidth = srcImage.width;
      final srcHeight = srcImage.height;

      final scale = _targetWidth / srcWidth;
      final targetHeight = (srcHeight * scale).round();

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);

      final paint = ui.Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: _blurSigma,
          sigmaY: _blurSigma,
          tileMode: ui.TileMode.clamp,
        );

      canvas.drawImageRect(
        srcImage,
        ui.Rect.fromLTWH(0, 0, srcWidth.toDouble(), srcHeight.toDouble()),
        ui.Rect.fromLTWH(0, 0, _targetWidth.toDouble(), targetHeight.toDouble()),
        paint,
      );

      final picture = recorder.endRecording();
      final blurredImage = await picture.toImage(_targetWidth, targetHeight);

      return blurredImage;
    } catch (e) {
      debugPrint('[JUJO][blur] pre-blur failed for $url: $e');
      return null;
    }
  }

  void _evictIfNeeded() {
    while (_cache.length >= _maxCacheSize) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest)?.dispose();
    }
  }

  void clearCache() {
    for (final img in _cache.values) {
      img.dispose();
    }
    _cache.clear();
  }
}
