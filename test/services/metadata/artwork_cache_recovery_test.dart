import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/services/metadata/artwork_cache_recovery.dart';

void main() {
  setUp(ArtworkCacheRecovery.instance.reset);

  test('evicts each versioned artwork key only once', () async {
    var evictions = 0;

    final first = await ArtworkCacheRecovery.instance.recoverOnce(
      identity: 'nvart_v3_game_poster',
      evict: () async {
        evictions++;
      },
    );
    final second = await ArtworkCacheRecovery.instance.recoverOnce(
      identity: 'nvart_v3_game_poster',
      evict: () async {
        evictions++;
      },
    );

    expect(first, isTrue);
    expect(second, isFalse);
    expect(evictions, 1);
  });

  test('a new source fingerprint receives its own repair budget', () async {
    var evictions = 0;
    for (final key in ['nvart_v3_source_a', 'nvart_v3_source_b']) {
      await ArtworkCacheRecovery.instance.recoverOnce(
        identity: key,
        evict: () async {
          evictions++;
        },
      );
    }

    expect(evictions, 2);
  });
}
