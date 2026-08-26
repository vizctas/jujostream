import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../widgets/poster_image.dart';

class BackgroundBlurService {
  BackgroundBlurService._();
  static final instance = BackgroundBlurService._();

  final Map<String, ui.Image> _cache = {};

  final Map<String, Future<ui.Image?>> _inFlight = {};

  static const int _maxCacheSize = 30;

  static const int _targetWidth = 360;

  static const double _blurSigma = 20.0;

  ui.Image? getCached(String key) => _cache[key];

  bool isAvailable(String key) => _cache.containsKey(key);
  bool isPending(String key) => _inFlight.containsKey(key);

  Future<ui.Image?> preBlur(String url, {String? cacheKey}) {
    final key = cacheKey ?? url;
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    return _inFlight.putIfAbsent(
      key,
      () => _processAndCache(url, key, cacheKey),
    );
  }

  Future<ui.Image?> _processAndCache(
    String url,
    String key,
    String? cacheKey,
  ) async {
    try {
      final image = await _processBlur(
        PosterImage.providerFor(
          url,
          cacheKey: cacheKey,
          maxWidth: _targetWidth,
        ),
      );
      if (image != null) {
        _evictIfNeeded();
        _cache[key] = image;
      }
      return image;
    } finally {
      _inFlight.remove(key);
    }
  }

  void preBlurAsync(String url, {String? cacheKey}) {
    final key = cacheKey ?? url;
    if (_cache.containsKey(key) || _inFlight.containsKey(key)) return;
    unawaited(preBlur(url, cacheKey: cacheKey));
  }

  Future<ui.Image?> _processBlur(ImageProvider<Object> provider) async {
    try {
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
        ui.Rect.fromLTWH(
          0,
          0,
          _targetWidth.toDouble(),
          targetHeight.toDouble(),
        ),
        paint,
      );

      final picture = recorder.endRecording();
      final blurredImage = await picture.toImage(_targetWidth, targetHeight);
      picture.dispose();
      imageInfo.dispose();

      return blurredImage;
    } catch (e) {
      debugPrint('[JUJO][blur] pre-blur failed: $e');
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
