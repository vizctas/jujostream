part of 'app_view_screen.dart';

mixin _AppViewCarouselMixin on _AppViewScreenBase {
  @override
  Widget _buildCarouselHintsRow() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _hintChip('X', 'Grid', onTap: () {
              _feedbackAction();
              setState(() {
                _viewMode = _viewMode == _ViewMode.carousel
                    ? _ViewMode.grid
                    : _ViewMode.carousel;
              });
              if (_viewMode == _ViewMode.grid) {
                _disposeVideoController();
              }
            }),
            _hintChip('START', 'Play', onTap: () {
              final provider = context.read<AppListProvider>();
              final visibleApps = _visibleApps(provider.apps.toList());
              if (visibleApps.isNotEmpty) {
                _handleAppTap(_selectedApp(visibleApps));
              }
            }),
            _hintChip('SELECT', 'Settings', onTap: () {
              _feedbackAction();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AppViewPresentationSettingsScreen(
                    preferences: context.read<LauncherPreferences>(),
                  ),
                ),
              );
            }),
            _hintChip('R3', 'Smart Filter', onTap: () {
              _feedbackAction();
              _openSmartGenreFilters();
            }),
            _hintChip('Y', 'Details', onTap: () {
              _feedbackAction();
              final provider = context.read<AppListProvider>();
              final visibleApps = _visibleApps(provider.apps.toList());
              if (visibleApps.isNotEmpty) {
                _openDetailsScreen(_selectedApp(visibleApps));
              }
            }),
            _hintChip('RB', 'Fav', onTap: () {
              final provider = context.read<AppListProvider>();
              final visibleApps = _visibleApps(provider.apps.toList());
              if (visibleApps.isNotEmpty) {
                _toggleFavorite(_selectedApp(visibleApps));
              }
            }),
            if (!_postersHidden)
              _hintChip('↑', 'Hide posters', onTap: () {
                _feedbackNavigate();
                setState(() => _postersHidden = true);
              }),
            if (_postersHidden)
              _hintChip('↓', 'Show posters', onTap: () {
                _feedbackNavigate();
                setState(() => _postersHidden = false);
              }),
          ],
        ),
      ),
    );
  }

  @override
  Widget _buildHorizontalCarousel(List<NvApp> apps, NvApp selected) {
    final lp = context.read<LauncherPreferences>();

    final cw = lp.cardWidth * 0.7;
    final ch = lp.cardHeight * 0.7;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SizedBox(
        height: ch + 14,
        child: ListView.separated(
          controller: _carouselController,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: apps.length,
          separatorBuilder: (_, _) => SizedBox(width: lp.cardSpacing),
          itemBuilder: (context, index) {
            final app = apps[index];
            final isSelected = app.appId == selected.appId;
            return _CarouselCard(
              key: ValueKey(app.appId),
              app: app,
              heroTag: _heroTag(app),
              selected: isSelected,
              focused: _focusedAppId == app.appId,
              focusNode: _cardFocusNodes[app.appId],
              cardWidth: cw,
              cardRadius: lp.cardBorderRadius,
              showLabel: lp.showCardLabels,
              showRunningBadge: lp.showRunningBadge,
              onFocus: () {
                if (!mounted) return;
                setState(() {
                  _browseSection = _BrowseSection.carousel;
                  _selectedAppId = app.appId;
                  _focusedAppId = app.appId;
                });
                _queueAccentColorExtraction(app);
                _centerOnIndex(index, apps.length);
              },
              onKeyEvent: (event) => _onKeyEvent(event, apps, app),
              onTap: () {
                if (isSelected) {
                  _feedbackAction();
                  _openDetailsScreen(app);
                } else {
                  _feedbackNavigate();
                  setState(() {
                    _selectedAppId = app.appId;
                    _focusedAppId = app.appId;
                  });
                  _queueAccentColorExtraction(app);
                  _requestCardFocus(app.appId);
                  _centerOnIndex(index, apps.length);
                }
              },
              onLongPress: () {
                _feedbackHeavy();
                setState(() {
                  _selectedAppId = app.appId;
                  _focusedAppId = app.appId;
                });
                _requestCardFocus(app.appId);
                _centerOnIndex(index, apps.length);
                _showRunningSheet(app);
              },
            );
          },
        ),
      ),
    );
  }

  @override
  void _centerOnIndex(int index, int total, {bool animate = true}) {
    final lp = context.read<LauncherPreferences>();
    const sidePadding = 16.0;

    if (!_carouselController.hasClients) return;

    final itemWidth = lp.cardWidth * 0.7;
    final spacing = lp.cardSpacing;
    final viewport = _carouselController.position.viewportDimension;
    final itemCenter =
        sidePadding + (index * (itemWidth + spacing)) + (itemWidth / 2);
    final rawOffset = itemCenter - (viewport / 2);
    final maxOffset = _carouselController.position.maxScrollExtent;
    final target = rawOffset.clamp(0.0, maxOffset);

    if (animate) {
      _carouselController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _carouselController.jumpTo(target);
    }
  }
}

class _CarouselCard extends StatefulWidget {
  final NvApp app;
  final String heroTag;
  final bool selected;
  final bool focused;
  final FocusNode? focusNode;
  final double cardWidth;
  final double cardRadius;
  final bool showLabel;
  final bool showRunningBadge;
  final VoidCallback onFocus;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CarouselCard({
    super.key,
    required this.app,
    required this.heroTag,
    required this.selected,
    required this.focused,
    required this.focusNode,
    required this.onFocus,
    required this.onKeyEvent,
    required this.onTap,
    required this.onLongPress,
    this.cardWidth = 156,
    this.cardRadius = 14,
    this.showLabel = true,
    this.showRunningBadge = true,
  });

  @override
  State<_CarouselCard> createState() => _CarouselCardState();
}

class _CarouselCardState extends State<_CarouselCard>
    with SingleTickerProviderStateMixin {
  AppThemeColors get _tp => context.read<ThemeProvider>().colors;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _pulseAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.07), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.07, end: 0.98), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.98, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(_CarouselCard old) {
    super.didUpdateWidget(old);

    if (!old.selected && widget.selected) {
      _pulseCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || widget.focused;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (hasFocus) {
        if (hasFocus) widget.onFocus();
      },
      onKeyEvent: (_, event) => widget.onKeyEvent(event),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: active ? 1.0 : 0.94,
          duration: const Duration(milliseconds: 160),
          child: ScaleTransition(
            scale: _pulseAnim,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: widget.cardWidth,
              transform: active
                  ? Matrix4.translationValues(0.0, -10.0, 0.0)
                  : Matrix4.identity(),
              decoration: BoxDecoration(
                color: _tp.background,
                borderRadius: BorderRadius.circular(widget.cardRadius),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: _tp.accent.withValues(alpha: 0.35),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.app.posterUrl != null &&
                      widget.app.posterUrl!.isNotEmpty)
                    Hero(
                      tag: widget.heroTag,
                      child: PosterImage(
                        url: widget.app.posterUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 300,
                        errorWidget: (_, _, _) => _fallback(),
                        placeholder: (_, _) => _fallback(),
                      ),
                    )
                  else
                    Hero(tag: widget.heroTag, child: _fallback()),
                  if (widget.showLabel)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xCC000000)],
                          ),
                        ),
                        child: Text(
                          widget.app.appName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  if (widget.showRunningBadge && widget.app.isRunning)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),

                  if (widget.app.pluginName != null &&
                      widget.app.pluginName!.isNotEmpty)
                    Positioned(
                      bottom: widget.showLabel ? 32 : 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _storeAbbreviation(widget.app.pluginName!),
                          style: TextStyle(
                            color: _storeColor(widget.app.pluginName!),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),

                  if (AppOverrideService.instance.hasOverrides(
                    widget.app.serverUuid ?? 'default',
                    widget.app.appId,
                  ))
                    Positioned(
                      top: 6,
                      right: widget.showRunningBadge && widget.app.isRunning
                          ? 24
                          : 8,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.70),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.edit_note,
                          color: Colors.amberAccent,
                          size: 12,
                        ),
                      ),
                    ),

                  if (widget.app.playtimeMinutes > 0)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.70),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time,
                              color: Colors.white54,
                              size: 8,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              widget.app.playtimeLabel,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
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
      ),
    );
  }

  Widget _fallback() {
    return Container(
      color: _tp.secondary,
      child: const Center(
        child: Icon(Icons.gamepad, color: Colors.white24, size: 36),
      ),
    );
  }

  static String _storeAbbreviation(String pluginName) {
    final lower = pluginName.toLowerCase();
    if (lower.contains('steam')) return 'STEAM';
    if (lower.contains('epic')) return 'EPIC';
    if (lower.contains('gog')) return 'GOG';
    if (lower.contains('xbox') || lower.contains('gamepass')) return 'XBOX';
    if (lower.contains('ubisoft') || lower.contains('uplay')) return 'UPLAY';
    if (lower.contains('ea') || lower.contains('origin')) return 'EA';
    if (lower.contains('battle') || lower.contains('blizzard')) return 'BNET';

    return pluginName.toUpperCase().substring(0, pluginName.length.clamp(0, 5));
  }

  static Color _storeColor(String pluginName) {
    final lower = pluginName.toLowerCase();
    if (lower.contains('steam')) return const Color(0xFF1B9CFC);
    if (lower.contains('epic')) return const Color(0xFFFFFFFF);
    if (lower.contains('gog')) return const Color(0xFFAA59D3);
    if (lower.contains('xbox') || lower.contains('gamepass')) {
      return const Color(0xFF52B043);
    }
    if (lower.contains('ubisoft') || lower.contains('uplay')) {
      return const Color(0xFF3D85C8);
    }
    if (lower.contains('ea') || lower.contains('origin')) {
      return const Color(0xFFFF6B00);
    }
    if (lower.contains('battle') || lower.contains('blizzard')) {
      return const Color(0xFF009AE4);
    }
    return Colors.white70;
  }
}
