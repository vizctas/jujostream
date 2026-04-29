import 'package:flutter/material.dart';

import '../../models/gaming_news_item.dart';
import '../../models/nv_app.dart';
import '../../providers/theme_provider.dart';
import '../poster_image.dart';

/// A single news/deal/event card used inside [NewsCarouselWidget].
///
/// All colours are derived from [ThemeProvider] — nothing is hardcoded.
class NewsCarouselCard extends StatelessWidget {
  final GamingNewsItem item;
  final bool focused;
  final double cardWidth;
  final ThemeProvider tp;

  /// Optional list of apps used to resolve a poster for related Steam games.
  final List<NvApp> allApps;

  const NewsCarouselCard({
    super.key,
    required this.item,
    required this.focused,
    required this.cardWidth,
    required this.tp,
    this.allApps = const [],
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: cardWidth,
      decoration: BoxDecoration(
        color: tp.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: focused
              ? tp.accent.withValues(alpha: 0.58)
              : Colors.white.withValues(alpha: 0.08),
          width: focused ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: focused ? 0.40 : 0.28),
            blurRadius: focused ? 22 : 14,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 150, child: _buildImage()),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.typeLabel,
                      style: TextStyle(
                        color: tp.warm,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.dateLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Image resolution
  // ---------------------------------------------------------------------------

  Widget _buildImage() {
    // Prefer the poster of a related game already in the library.
    final relatedAppId = item.relatedAppId;
    if (relatedAppId != null && relatedAppId > 0) {
      final linkedApp = allApps
          .where((app) => app.steamAppId == relatedAppId)
          .firstOrNull;
      if (linkedApp != null) {
        final posterUrl = linkedApp.posterUrl;
        if (posterUrl != null && posterUrl.isNotEmpty) {
          return PosterImage(
            url: posterUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            memCacheWidth: 720,
            errorWidget: (_, _, _) => _buildImageUrl(),
          );
        }
      }
    }
    return _buildImageUrl();
  }

  Widget _buildImageUrl() {
    if (item.imageAsset != null && item.imageAsset!.isNotEmpty) {
      return Image.asset(
        item.imageAsset!,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, _, _) => _fallbackImage(),
      );
    }
    if (item.imageUrl != null && item.imageUrl!.isNotEmpty) {
      return PosterImage(
        url: item.imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        memCacheWidth: 720,
        errorWidget: (_, _, _) => _fallbackImage(),
      );
    }
    return _fallbackImage();
  }

  Widget _fallbackImage() {
    return Image.asset(
      'assets/images/news_placeholder.png',
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (_, _, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: tp.surfaceVariant,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
