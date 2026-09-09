import 'package:flutter/foundation.dart';

typedef ArtworkCacheEviction = Future<void> Function();

/// Repairs a poisoned artwork cache entry, at most once per [retryAfter]
/// window per versioned art key.
///
/// A failed response used to remain on disk for 90 days. Keeping the retry
/// budget here prevents independent widgets and probes from creating an
/// eviction/download loop for the same source. The budget is time-bounded
/// rather than permanent: a transient TLS or network failure at first paint
/// used to leave the tile grey until the process was killed.
class ArtworkCacheRecovery {
  ArtworkCacheRecovery._();

  static final instance = ArtworkCacheRecovery._();
  static const retryAfter = Duration(seconds: 45);

  final Map<String, DateTime> _attempted = <String, DateTime>{};

  Future<bool> recoverOnce({
    required String identity,
    required ArtworkCacheEviction evict,
  }) async {
    final now = DateTime.now();
    final last = _attempted[identity];
    if (last != null && now.difference(last) < retryAfter) return false;
    _attempted[identity] = now;
    try {
      await evict();
    } catch (error) {
      debugPrint('[JUJO][art] cache eviction failed for $identity: $error');
    }
    return true;
  }

  @visibleForTesting
  void reset() => _attempted.clear();
}
