import 'package:flutter/painting.dart';

/// Throttles image loading during stream initialization.
///
/// When a stream is about to start, [pauseForStream] reduces the Flutter
/// image cache's live image limit and evicts non-essential cached images.
/// This frees network bandwidth and memory for the Moonlight protocol
/// handshake, preventing the 90% connection failure rate observed when
/// poster downloads saturate the network on first load.
///
/// Call [resumeAfterStream] when the stream ends or fails to restore
/// normal image loading behavior.
class ImageLoadThrottle {
  ImageLoadThrottle._();

  static int _savedMaximumSize = 100;
  static int _savedMaximumSizeBytes = 100 << 20; // 100 MB default
  static bool _isPaused = false;

  /// Whether image loading is currently throttled for streaming.
  static bool get isPaused => _isPaused;

  /// Throttle image loading: shrink cache limits and evict live images.
  /// Safe to call multiple times — only the first call takes effect.
  static void pauseForStream() {
    if (_isPaused) return;
    _isPaused = true;

    final cache = PaintingBinding.instance.imageCache;

    _savedMaximumSize = cache.maximumSize;
    _savedMaximumSizeBytes = cache.maximumSizeBytes;

    cache.clearLiveImages();

    cache.maximumSize = 10;
    cache.maximumSizeBytes = 10 << 20; // 10 MB
  }

  /// Restore normal image loading after stream ends.
  /// Safe to call multiple times or without a prior [pauseForStream].
  static void resumeAfterStream() {
    if (!_isPaused) return;
    _isPaused = false;

    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = _savedMaximumSize;
    cache.maximumSizeBytes = _savedMaximumSizeBytes;
  }
}
