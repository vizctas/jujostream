import 'package:flutter/foundation.dart';

typedef ArtworkCacheEviction = Future<void> Function();

/// Repairs a poisoned artwork cache entry at most once per versioned art key.
///
/// A failed response used to remain on disk for 90 days. Keeping the retry
/// budget here prevents independent widgets and probes from creating an
/// eviction/download loop for the same source.
class ArtworkCacheRecovery {
  ArtworkCacheRecovery._();

  static final instance = ArtworkCacheRecovery._();

  final Set<String> _attempted = <String>{};

  Future<bool> recoverOnce({
    required String identity,
    required ArtworkCacheEviction evict,
  }) async {
    if (!_attempted.add(identity)) return false;
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
