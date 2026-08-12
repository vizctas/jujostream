class LibraryFreshnessPolicy {
  final Duration libraryTtl;
  final Duration metadataTtl;

  const LibraryFreshnessPolicy({
    this.libraryTtl = const Duration(seconds: 30),
    this.metadataTtl = const Duration(hours: 24),
  });

  bool isLibraryStale(DateTime? refreshedAt, DateTime now) =>
      refreshedAt == null || now.difference(refreshedAt) >= libraryTtl;

  bool isMetadataStale(DateTime? refreshedAt, DateTime now) =>
      refreshedAt == null || now.difference(refreshedAt) >= metadataTtl;
}
