import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/services/library/library_freshness_policy.dart';

void main() {
  const policy = LibraryFreshnessPolicy(
    libraryTtl: Duration(seconds: 30),
    metadataTtl: Duration(hours: 24),
  );
  final now = DateTime.utc(2026, 8, 11, 20);

  test('missing timestamps are stale', () {
    expect(policy.isLibraryStale(null, now), isTrue);
    expect(policy.isMetadataStale(null, now), isTrue);
  });

  test('library remains fresh inside its TTL', () {
    expect(
      policy.isLibraryStale(now.subtract(const Duration(seconds: 29)), now),
      isFalse,
    );
    expect(
      policy.isLibraryStale(now.subtract(const Duration(seconds: 30)), now),
      isTrue,
    );
  });

  test('metadata remains fresh inside its independent TTL', () {
    expect(
      policy.isMetadataStale(now.subtract(const Duration(hours: 23)), now),
      isFalse,
    );
    expect(
      policy.isMetadataStale(now.subtract(const Duration(hours: 24)), now),
      isTrue,
    );
  });
}
