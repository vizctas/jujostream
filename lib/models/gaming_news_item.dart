enum GamingNewsType { news, update, event, patch, recommended }

class GamingNewsItem {
  final String id;
  final GamingNewsType type;
  final String title;
  final String subtitle;
  final String dateLabel;
  final String? imageAsset;
  final String? imageUrl;
  final int? relatedAppId;
  final String actionLabel;
  final String? sourceUrl;

  const GamingNewsItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.dateLabel,
    this.imageAsset,
    this.imageUrl,
    this.relatedAppId,
    this.actionLabel = '',
    this.sourceUrl,
  });

  bool get hasImage =>
      (imageAsset != null && imageAsset!.isNotEmpty) ||
      (imageUrl != null && imageUrl!.isNotEmpty);

  String get typeLabel {
    return switch (type) {
      GamingNewsType.news => 'NEWS',
      GamingNewsType.update => 'UPDATE',
      GamingNewsType.event => 'EVENT',
      GamingNewsType.patch => 'PATCH',
      GamingNewsType.recommended => 'RECOMMENDED',
    };
  }
}
