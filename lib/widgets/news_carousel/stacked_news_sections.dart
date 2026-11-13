import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/gaming_news_item.dart';
import '../../models/nv_app.dart';
import '../../providers/theme_provider.dart';
import '../../services/audio/ui_sound_service.dart';
import '../../services/news/gaming_news_service.dart';
import '../../services/tv/tv_detector.dart';
import '../../ui/motion_scope.dart';
import '../poster_image.dart';
import 'gaming_news_reader_dialog.dart';

class _SectionSpec {
  final GamingNewsType type;
  final double cardWidth;
  final double cardHeight;
  final double imageHeight;
  final int maxSubtitleLines;

  double get gap => 14;

  const _SectionSpec({
    required this.type,
    required this.cardWidth,
    required this.cardHeight,
    required this.imageHeight,
    this.maxSubtitleLines = 1,
  });

  ({String title, String subtitle}) labels(AppLocalizations l) => switch (type) {
    GamingNewsType.news => (
      title: l.newsSectionNewsTitle,
      subtitle: l.newsSectionNewsSub,
    ),
    GamingNewsType.update => (
      title: l.newsSectionUpdatesTitle,
      subtitle: l.newsSectionUpdatesSub,
    ),
    GamingNewsType.event => (
      title: l.newsSectionEventsTitle,
      subtitle: l.newsSectionEventsSub,
    ),
    GamingNewsType.patch => (
      title: l.newsSectionPatchesTitle,
      subtitle: l.newsSectionPatchesSub,
    ),
    GamingNewsType.recommended => (
      title: l.newsSectionDealsTitle,
      subtitle: l.newsSectionDealsSub,
    ),
  };
}

class _RenderedSection {
  final _SectionSpec spec;
  final List<GamingNewsItem> items;

  const _RenderedSection({required this.spec, required this.items});
}

/// Vertically stacked horizontal news/discovery shelves shared across all
/// launcher themes. Each section adapts card dimensions to its content while
/// keeping all cards inside that same row strictly symmetrical.
class StackedNewsSections extends StatefulWidget {
  final List<NvApp> allApps;
  final List<NvApp> apps;
  final bool hasFocus;
  final ScrollController? parentScrollController;
  final VoidCallback onExitUp;
  final ValueChanged<NvApp>? onPlayApp;
  final ValueChanged<NvApp>? onAppDetails;
  final double topPeekExtent;
  final EdgeInsetsGeometry padding;
  final List<GamingNewsItem>? initialItems;

  const StackedNewsSections({
    super.key,
    required this.allApps,
    required this.apps,
    required this.hasFocus,
    required this.onExitUp,
    this.parentScrollController,
    this.onPlayApp,
    this.onAppDetails,
    this.topPeekExtent = 150.0,
    this.padding = const EdgeInsets.fromLTRB(28, 18, 28, 72),
    this.initialItems,
  });

  @override
  State<StackedNewsSections> createState() => StackedNewsSectionsState();
}

class StackedNewsSectionsState extends State<StackedNewsSections> {
  static const List<_SectionSpec> _specs = [
    _SectionSpec(
      type: GamingNewsType.news,
      cardWidth: 356,
      cardHeight: 214,
      imageHeight: 124,
      maxSubtitleLines: 1,
    ),
    _SectionSpec(
      type: GamingNewsType.update,
      cardWidth: 296,
      cardHeight: 194,
      imageHeight: 110,
      maxSubtitleLines: 1,
    ),
    _SectionSpec(
      type: GamingNewsType.event,
      cardWidth: 248,
      cardHeight: 228,
      imageHeight: 132,
      maxSubtitleLines: 1,
    ),
    _SectionSpec(
      type: GamingNewsType.patch,
      cardWidth: 268,
      cardHeight: 170,
      imageHeight: 88,
      maxSubtitleLines: 1,
    ),
    _SectionSpec(
      type: GamingNewsType.recommended,
      cardWidth: 228,
      cardHeight: 204,
      imageHeight: 116,
      maxSubtitleLines: 1,
    ),
  ];

  final Map<GamingNewsType, GlobalKey> _sectionKeys = {
    for (final spec in _specs) spec.type: GlobalKey(),
  };
  final Map<GamingNewsType, ScrollController> _rowControllers = {
    for (final spec in _specs) spec.type: ScrollController(),
  };
  final Map<GamingNewsType, int> _colByType = {
    for (final spec in _specs) spec.type: 0,
  };

  List<GamingNewsItem> _items = const <GamingNewsItem>[];
  bool _loading = true;
  int _sectionIdx = 0;

  @override
  void initState() {
    super.initState();
    final seeded = widget.initialItems;
    if (seeded != null) {
      _items = seeded;
      _loading = false;
    } else {
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(covariant StackedNewsSections oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.allApps.length != oldWidget.allApps.length) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    for (final sc in _rowControllers.values) {
      sc.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted && _items.isEmpty) {
      setState(() => _loading = true);
    }
    final loaded = await GamingNewsService.fetchDashboardItems(
      allApps: widget.allApps,
      visibleApps: widget.apps,
    );
    if (!mounted) return;
    setState(() {
      _items = loaded;
      _loading = false;
    });
  }

  List<_RenderedSection> _visibleSections() {
    if (_loading && _items.isEmpty) {
      return const [];
    }
    final result = <_RenderedSection>[];
    for (final spec in _specs) {
      final bucket = GamingNewsService.filterByType(_items, spec.type);
      if (bucket.isNotEmpty) {
        result.add(_RenderedSection(spec: spec, items: bucket));
      }
    }
    return result;
  }

  /// Moves focus into the top section and gently scrolls the parent page so
  /// the previous view stays visible near the top of the viewport.
  void enterFromTop() {
    if (!mounted) return;
    final sections = _visibleSections();
    setState(() {
      _sectionIdx = 0;
      if (sections.isNotEmpty) {
        final type = sections[0].spec.type;
        final current = _colByType[type] ?? 0;
        _colByType[type] = current.clamp(0, sections[0].items.length - 1);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollParentToActiveSection();
    });
  }

  void _navFeedback() {
    UiSoundService.playClick();
    if (!TvDetector.instance.isTV) HapticFeedback.lightImpact();
  }

  void _scrollParentToZero() {
    final sc = widget.parentScrollController;
    if (sc == null || !sc.hasClients) return;
    unawaited(
      sc.animateTo(
        0.0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _scrollParentToActiveSection() {
    final sc = widget.parentScrollController;
    if (sc == null || !sc.hasClients || !mounted) return;

    final sections = _visibleSections();
    final targetType = sections.isNotEmpty
        ? sections[_sectionIdx.clamp(0, sections.length - 1)].spec.type
        : _specs[_sectionIdx.clamp(0, 2)].type;
    final sectionCtx = _sectionKeys[targetType]?.currentContext;
    if (sectionCtx == null) return;

    final sectionBox = sectionCtx.findRenderObject() as RenderBox?;
    final viewportBox =
        sc.position.context.storageContext.findRenderObject() as RenderBox?;
    if (sectionBox == null ||
        viewportBox == null ||
        !sectionBox.attached ||
        !viewportBox.attached) {
      return;
    }

    final dy = sectionBox.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
    final desiredTop = _sectionIdx == 0 ? widget.topPeekExtent : 138.0;
    final target = (sc.offset + dy - desiredTop).clamp(
      0.0,
      sc.position.maxScrollExtent,
    );

    unawaited(
      sc.animateTo(
        target,
        duration: MotionScope.read(context).focusDuration,
        curve: MotionScope.read(context).standardCurve,
      ),
    );
  }

  void _scrollHorizontal(_SectionSpec spec, int col) {
    final sc = _rowControllers[spec.type];
    if (sc == null || !sc.hasClients) return;
    final pos = sc.position;
    final itemLeft = col * (spec.cardWidth + spec.gap);
    final target =
        (itemLeft - (pos.viewportDimension - spec.cardWidth) / 2).clamp(
          0.0,
          pos.maxScrollExtent,
        );
    unawaited(
      sc.animateTo(
        target,
        duration: MotionScope.read(context).focusDuration,
        curve: MotionScope.read(context).standardCurve,
      ),
    );
  }

  /// Processes gamepad/keyboard navigation when this widget has active focus.
  bool handleKeyEvent(LogicalKeyboardKey key) {
    final sections = _visibleSections();
    final sectionCount = sections.isNotEmpty ? sections.length : 3;
    final safeSection = _sectionIdx.clamp(0, sectionCount - 1);

    if (key == LogicalKeyboardKey.arrowDown) {
      if (safeSection < sectionCount - 1) {
        _navFeedback();
        setState(() => _sectionIdx = safeSection + 1);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollParentToActiveSection();
        });
      }
      return true;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (safeSection > 0) {
        _navFeedback();
        setState(() => _sectionIdx = safeSection - 1);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollParentToActiveSection();
        });
      } else {
        _scrollParentToZero();
        widget.onExitUp();
      }
      return true;
    }

    if (key == LogicalKeyboardKey.gameButtonB ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      _scrollParentToZero();
      widget.onExitUp();
      return true;
    }

    if (sections.isEmpty) return false;
    final active = sections[safeSection];
    final col = (_colByType[active.spec.type] ?? 0).clamp(
      0,
      active.items.length - 1,
    );

    if (key == LogicalKeyboardKey.arrowLeft) {
      final next = (col - 1).clamp(0, active.items.length - 1);
      if (next != col) {
        _navFeedback();
        setState(() => _colByType[active.spec.type] = next);
        _scrollHorizontal(active.spec, next);
      }
      return true;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      final next = (col + 1).clamp(0, active.items.length - 1);
      if (next != col) {
        _navFeedback();
        setState(() => _colByType[active.spec.type] = next);
        _scrollHorizontal(active.spec, next);
      }
      return true;
    }

    if (key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select) {
      UiSoundService.playClick();
      unawaited(
        GamingNewsReaderDialog.show(
          context,
          item: active.items[col],
          allApps: widget.allApps,
          onPlayApp: widget.onPlayApp,
          onAppDetails: widget.onAppDetails,
        ),
      );
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final sections = _visibleSections();

    return Container(
      width: double.infinity,
      padding: widget.padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.72),
            tp.background.withValues(alpha: 0.96),
          ],
        ),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: _loading && sections.isEmpty
          ? _buildSkeletonSections(tp)
          : sections.isEmpty
          ? _buildEmptyState(tp)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < sections.length; i++) ...[
                  if (i > 0) const SizedBox(height: 28),
                  _buildSectionRow(tp, sections[i], i),
                ],
              ],
            ),
    );
  }

  Widget _buildEmptyState(ThemeProvider tp) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.newspaper_rounded,
              color: Colors.white.withValues(alpha: 0.28),
              size: 36,
            ),
            const SizedBox(height: 10),
            Text(
              l.newsEmptyState,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionRow(
    ThemeProvider tp,
    _RenderedSection section,
    int sectionIndex,
  ) {
    final spec = section.spec;
    final labels = spec.labels(AppLocalizations.of(context));
    final items = section.items;
    final isRowActive = widget.hasFocus && _sectionIdx == sectionIndex;
    final selectedCol = (_colByType[spec.type] ?? 0).clamp(0, items.length - 1);

    return Column(
      key: _sectionKeys[spec.type],
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: isRowActive ? 14 : 6,
              height: 4,
              decoration: BoxDecoration(
                color: isRowActive
                    ? tp.accentLight
                    : tp.accent.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              labels.title,
              style: TextStyle(
                color: isRowActive ? Colors.white : Colors.white.withValues(alpha: 0.85),
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              labels.subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.36),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const Spacer(),
            Text(
              '${items.length}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.30),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: spec.cardHeight + 12,
          child: ListView.separated(
            controller: _rowControllers[spec.type],
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: items.length,
            separatorBuilder: (_, _) => SizedBox(width: spec.gap),
            itemBuilder: (context, index) {
              final focused = isRowActive && index == selectedCol;
              final item = items[index];
              return _SectionNewsCard(
                spec: spec,
                item: item,
                focused: focused,
                tp: tp,
                allApps: widget.allApps,
                onTap: () {
                  setState(() {
                    _sectionIdx = sectionIndex;
                    _colByType[spec.type] = index;
                  });
                  _scrollHorizontal(spec, index);
                  unawaited(
                    GamingNewsReaderDialog.show(
                      context,
                      item: item,
                      allApps: widget.allApps,
                      onPlayApp: widget.onPlayApp,
                      onAppDetails: widget.onAppDetails,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonSections(ThemeProvider tp) {
    final l = AppLocalizations.of(context);
    final previewSpecs = _specs.take(3).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < previewSpecs.length; i++) ...[
          if (i > 0) const SizedBox(height: 26),
          Column(
            key: _sectionKeys[previewSpecs[i].type],
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tp.accent.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    previewSpecs[i].labels(l).title,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: previewSpecs[i].cardHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 4,
                  separatorBuilder: (_, _) =>
                      SizedBox(width: previewSpecs[i].gap),
                  itemBuilder: (_, _) => Container(
                    width: previewSpecs[i].cardWidth,
                    height: previewSpecs[i].cardHeight,
                    decoration: BoxDecoration(
                      color: tp.surface.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SectionNewsCard extends StatelessWidget {
  final _SectionSpec spec;
  final GamingNewsItem item;
  final bool focused;
  final ThemeProvider tp;
  final List<NvApp> allApps;
  final VoidCallback onTap;

  const _SectionNewsCard({
    required this.spec,
    required this.item,
    required this.focused,
    required this.tp,
    required this.allApps,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: focused ? 1.04 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: spec.cardWidth,
          height: spec.cardHeight,
          decoration: BoxDecoration(
            color: tp.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: focused
                  ? tp.accentLight.withValues(alpha: 0.90)
                  : Colors.white.withValues(alpha: 0.08),
              width: focused ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: focused
                    ? tp.accent.withValues(alpha: 0.28)
                    : Colors.black.withValues(alpha: 0.26),
                blurRadius: focused ? 18 : 10,
                offset: Offset(0, focused ? 6 : 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: spec.imageHeight,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildImage(),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 36,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                tp.surface.withValues(alpha: 0.92),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const Spacer(),
                        if (item.subtitle.isNotEmpty) ...[
                          Text(
                            item.subtitle,
                            maxLines: spec.maxSubtitleLines,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.54),
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 3),
                        ],
                        Text(
                          item.dateLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: focused
                                ? tp.accentLight
                                : tp.warm.withValues(alpha: 0.85),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    final relatedAppId = item.relatedAppId;
    if (relatedAppId != null && relatedAppId > 0) {
      for (final app in allApps) {
        if (app.steamAppId == relatedAppId &&
            app.posterUrl != null &&
            app.posterUrl!.isNotEmpty) {
          return PosterImage(
            url: app.posterUrl!,
            cacheKey: app.artCacheKey('poster'),
            fit: BoxFit.cover,
            width: double.infinity,
            memCacheWidth: 720,
            errorWidget: (_, _, _) => _buildExternalUrl(),
          );
        }
      }
    }
    return _buildExternalUrl();
  }

  Widget _buildExternalUrl() {
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
        decoration: BoxDecoration(color: tp.surfaceVariant),
      ),
    );
  }
}

