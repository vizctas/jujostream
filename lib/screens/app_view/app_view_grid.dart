part of 'app_view_screen.dart';

mixin _AppViewGridMixin on _AppViewScreenBase {
  @override
  Widget _buildGridLayout(
    List<NvApp> apps,
    List<NvApp> visibleApps,
    NvApp selected,
  ) {
    final lp = context.read<LauncherPreferences>();
    final accent = _accentColor ?? _tp.accent;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    final showInfoPanel = screenWidth >= 900;

    final gridWidth = showInfoPanel
        ? screenWidth - (isLandscape ? 220 : 140)
        : screenWidth - 24;
    final crossAxisCount = (gridWidth / 130).floor().clamp(2, 6);

    // independently of the grid when D-Pad focus changes.
    Widget infoPanel() {
      return ValueListenableBuilder<int?>(
        valueListenable: _selectedAppIdNotifier,
        builder: (context, selId, _) {
          final sel = selId != null
              ? visibleApps.firstWhere(
                  (a) => a.appId == selId,
                  orElse: () => selected,
                )
              : selected;
          return SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (sel.posterUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: PosterImage(
                        url: sel.posterUrl!,
                        width: double.infinity,
                        height: isLandscape ? 200 : 160,
                        fit: BoxFit.cover,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    sel.appName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),

                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (sel.isRunning)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.greenAccent.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            AppLocalizations.of(context).running,
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      if (sel.playtimeLabel.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.timer_outlined,
                              color: Colors.white38,
                              size: 12,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              sel.playtimeLabel,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      if (sel.isHdrSupported)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.cyanAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.cyanAccent.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            AppLocalizations.of(context).hdrLabel,
                            style: TextStyle(color: Colors.cyanAccent, fontSize: 9),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Text(
                    sel.pluginName ??
                        AppLocalizations.of(context).localLibrary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        _feedbackAction();
                        _handleAppTap(sel);
                      },
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: Text(
                        sel.isRunning
                            ? AppLocalizations.of(context).resume
                            : AppLocalizations.of(context).play,
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _feedbackAction();
                        _openDetailsScreen(sel);
                      },
                      icon: const Icon(Icons.tune, size: 14),
                      label: Text(
                        AppLocalizations.of(context).options,
                        style: TextStyle(fontSize: 11),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _feedbackAction();
                        _toggleFavorite(sel);
                      },
                      icon: Icon(
                        _favoriteAppIds.contains(sel.appId)
                            ? Icons.star
                            : Icons.star_outline,
                        size: 14,
                      ),
                      label: Text(
                        _favoriteAppIds.contains(sel.appId)
                            ? AppLocalizations.of(context).removeFav
                            : AppLocalizations.of(context).favorite,
                        style: const TextStyle(fontSize: 11),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    Widget gridPanel() {
      if (visibleApps.isEmpty) {
        return Center(
          child: Text(
            _searchQuery.isEmpty
                ? AppLocalizations.of(context).noResults
                : AppLocalizations.of(context).noResultsQuery(_searchQuery),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: GridView.builder(
          controller: _gridScrollController,
          clipBehavior: Clip.none,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: lp.cardWidth / lp.cardHeight,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: visibleApps.length,
          itemBuilder: (context, index) {
            final app = visibleApps[index];
            final isSelected = app.appId == selected.appId;
            Widget card = GestureDetector(
              key: ValueKey(app.appId),
              onTap: () {
                if (isSelected) {
                  _feedbackAction();
                  _openDetailsScreen(app);
                } else {
                  _feedbackNavigate();
                  setState(() => _selectedAppId = app.appId);
                  _extractAccentColor(app);
                }
              },
              onLongPress: () {
                _feedbackHeavy();
                setState(() => _selectedAppId = app.appId);
                _handleAppTap(app);
              },
              child: TweenAnimationBuilder<double>(
                key: ValueKey('scale_${app.appId}'),
                tween: Tween<double>(begin: 1.0, end: isSelected ? 1.05 : 1.0),
                duration: isSelected
                    ? const Duration(milliseconds: 450)
                    : const Duration(milliseconds: 220),
                curve: isSelected ? Curves.elasticOut : Curves.easeOutCubic,
                builder: (_, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(lp.cardBorderRadius),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(lp.cardBorderRadius),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PosterImage(
                          url: app.posterUrl ?? '',
                          fit: BoxFit.cover,
                          memCacheWidth: 400,
                          placeholder: (_, _) => Container(
                            color: Colors.white10,
                            child: const Center(
                              child: Icon(
                                Icons.gamepad,
                                color: Colors.white24,
                                size: 24,
                              ),
                            ),
                          ),
                          errorWidget: (_, _, _) => Container(
                            color: Colors.white10,
                            child: Center(
                              child: Text(
                                app.appName.substring(0, 1),
                                style: const TextStyle(
                                  color: Colors.white24,
                                  fontSize: 24,
                                ),
                              ),
                            ),
                          ),
                        ),

                        if (lp.showCardLabels)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black87],
                                ),
                              ),
                              child: Text(
                                app.appName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),

                        if (app.isRunning && lp.showRunningBadge)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.greenAccent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.black,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );

            // instead of calling setState, so the grid doesn't fully rebuild.
            // The info panel rebuilds via ValueListenableBuilder; the card
            // uses Focus.of(context).hasFocus for its visual highlight.
            card = Focus(
              autofocus: index == 0,
              onFocusChange: (focused) {
                if (focused) {
                  _feedbackNavigate();
                  _selectedAppId = app.appId;
                  _extractAccentColor(app);
                }
              },
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.enter ||
                    key == LogicalKeyboardKey.select ||
                    key == LogicalKeyboardKey.gameButtonA) {
                  _feedbackAction();
                  _handleAppTap(app);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.contextMenu) {
                  _feedbackAction();
                  _openDetailsScreen(app);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.gameButtonB ||
                    key == LogicalKeyboardKey.escape ||
                    key == LogicalKeyboardKey.goBack) {
                  Navigator.maybePop(context);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: card,
            );
            return card;
          },
        ),
      );
    }

    final infoPanelWidth = isLandscape ? 200.0 : 140.0;

    return Column(
      children: [
        _buildTransparentAppBar(apps),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _hintChip('LT', ''),
              const SizedBox(width: 4),
              Expanded(
                child: _buildCategoryBar(apps, insertRtAfterFavorites: true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: showInfoPanel
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: infoPanelWidth, child: infoPanel()),
                    Expanded(child: gridPanel()),
                  ],
                )
              : gridPanel(),
        ),
        _buildGridFooterHints(),
      ],
    );
  }

  @override
  void _onGridScroll() {}

  Widget _buildGridFooterHints() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _hintChip('X', 'Carousel'),
            _hintChip('Y', AppLocalizations.of(context).details),
            _hintChip('START', AppLocalizations.of(context).play),
            _hintChip('SELECT', AppLocalizations.of(context).settingsLabel),
            _hintChip('R3', 'Smart Filter'),
            _hintChip('RB', AppLocalizations.of(context).fav),
          ],
        ),
      ),
    );
  }

  @override
  void _scrollGridToIndex(int index) {
    if (!_gridScrollController.hasClients) return;
    final cols = _gridCrossAxisCount();
    final lp = context.read<LauncherPreferences>();
    final itemHeight =
        (lp.cardHeight / lp.cardWidth) *
            ((MediaQuery.sizeOf(context).width - 24) / cols) +
        8;
    final row = index ~/ cols;
    final targetOffset = row * itemHeight;
    final viewport = _gridScrollController.position.viewportDimension;
    final maxScroll = _gridScrollController.position.maxScrollExtent;

    final offset = (targetOffset - viewport / 2 + itemHeight / 2).clamp(
      0.0,
      maxScroll,
    );
    _gridScrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  int _gridCrossAxisCount() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final showInfoPanel = screenWidth >= 900;
    final gridWidth = showInfoPanel
        ? screenWidth - (isLandscape ? 220 : 140)
        : screenWidth - 24;
    return (gridWidth / 130).floor().clamp(2, 6);
  }
}
