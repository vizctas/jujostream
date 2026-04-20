part of 'app_view_screen.dart';

mixin _AppViewFiltersMixin on _AppViewScreenBase {
  @override
  Widget _buildInlineFilterBar(List<NvApp> apps) {
    final categories = _categoryItems(apps);
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: _showBottomFilterBar
          ? Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _hintChip('LT', ''),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (int i = 0; i < categories.length; i++) ...[
                            _inlineFilterChip(categories[i]),
                          ],
                        ],
                      ),
                    ),
                  ),
                  _hintChip('RT', ''),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _inlineFilterChip(_CategoryItem cat) {
    final active =
        cat.filter == _activeFilter &&
        (cat.playniteCategory == null ||
            cat.playniteCategory == _activePlayniteCategory) &&
        (cat.filter != _AppFilter.collection ||
            cat.collectionId == _activeCollectionId);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () =>
            _applyFilter(cat.filter, playniteCategory: cat.playniteCategory, collectionId: cat.collectionId),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? (_accentColor ?? _tp.accent)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${cat.label} (${cat.count})',
            style: TextStyle(
              color: active ? Colors.white : Colors.white60,
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Future<void> _openSearch() async {
    final controller = TextEditingController(text: _searchQuery);
    final textFieldFocusNode = FocusNode();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Focus(
            skipTraversal: true,
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final key = event.logicalKey;
              if (key == LogicalKeyboardKey.gameButtonB ||
                  key == LogicalKeyboardKey.escape ||
                  key == LogicalKeyboardKey.goBack) {

                Navigator.pop(ctx);
                return KeyEventResult.handled;
              }

              if (key == LogicalKeyboardKey.arrowDown &&
                  textFieldFocusNode.hasFocus) {
                textFieldFocusNode.unfocus();
                node.nextFocus();
                return KeyEventResult.handled;
              }

              if (key == LogicalKeyboardKey.arrowUp &&
                  !textFieldFocusNode.hasFocus) {
                textFieldFocusNode.requestFocus();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: AlertDialog(
              backgroundColor: _tp.surface,
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).searchGame,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  IconButton(
                    tooltip: AppLocalizations.of(context).smartFilters,
                    icon: const Icon(
                      Icons.auto_awesome_outlined,
                      color: Colors.cyanAccent,
                    ),
                    onPressed: () => Navigator.pop(ctx, '__smart_filters__'),
                  ),
                ],
              ),
              content: TextField(
                controller: controller,
                focusNode: textFieldFocusNode,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).typeGameName,
                  hintStyle: TextStyle(color: Colors.white38),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
              actions: [
                FocusTraversalOrder(
                  order: const NumericFocusOrder(0),
                  child: Focus(
                    onKeyEvent: (_, event) {
                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                      if (event.logicalKey == LogicalKeyboardKey.gameButtonA ||
                          event.logicalKey == LogicalKeyboardKey.select) {
                        Navigator.pop(ctx, '');
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, ''),
                      child: Text(AppLocalizations.of(context).clear),
                    ),
                  ),
                ),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: Focus(
                    onKeyEvent: (_, event) {
                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                      if (event.logicalKey == LogicalKeyboardKey.gameButtonA ||
                          event.logicalKey == LogicalKeyboardKey.select) {
                        Navigator.pop(ctx, controller.text.trim());
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                      child: Text(AppLocalizations.of(context).apply),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    textFieldFocusNode.dispose();

    if (value == null || !mounted) return;
    if (value == '__smart_filters__') {
      await _openSmartGenreFilters();
      return;
    }
    setState(() {
      _searchQuery = value;
      _browseSection = _BrowseSection.carousel;
    });
    _screenFocusNode.requestFocus();
  }

  @override
  Future<void> _openFilterPicker() async {
    final provider = context.read<AppListProvider>();
    final playniteCategories = provider.playniteCategories;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _tp.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Focus(
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.gameButtonB ||
              key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            Navigator.pop(ctx);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SafeArea(
          child: FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  _FilterFocusableTile(
                    title: AppLocalizations.of(ctx).all,
                    autofocus: true,
                    onTap: () {
                      Navigator.pop(ctx);
                      _applyFilter(_AppFilter.all);
                    },
                  ),
                  _FilterFocusableTile(
                    title: AppLocalizations.of(ctx).recent,
                    onTap: () {
                      Navigator.pop(ctx);
                      _applyFilter(_AppFilter.recent);
                    },
                  ),
                  _FilterFocusableTile(
                    title: AppLocalizations.of(ctx).running,
                    onTap: () {
                      Navigator.pop(ctx);
                      _applyFilter(_AppFilter.running);
                    },
                  ),
                  _FilterFocusableTile(
                    title: AppLocalizations.of(ctx).favorites,
                    onTap: () {
                      Navigator.pop(ctx);
                      _applyFilter(_AppFilter.favorites);
                    },
                  ),
                  if (playniteCategories.isNotEmpty) ...[
                    const Divider(color: Colors.white12),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Text(
                        AppLocalizations.of(ctx).playniteCategories,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ...playniteCategories.map(
                      (cat) => _FilterFocusableTile(
                        title: cat.name,
                        onTap: () {
                          Navigator.pop(ctx);
                          _applyFilter(
                            _AppFilter.playniteCategory,
                            playniteCategory: cat.name,
                          );
                        },
                      ),
                    ),
                  ],
                  if (_collections.isNotEmpty) ...[
                    const Divider(color: Colors.white12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Text(
                        AppLocalizations.of(ctx).myCollections,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ..._collections.map(
                      (col) => _FilterFocusableTile(
                        title: col.name,
                        leading: Icon(Icons.folder_outlined, color: Color(col.colorValue), size: 20),
                        subtitle: '${col.appIds.length} ${AppLocalizations.of(ctx).gamesCount}',
                        onTap: () {
                          Navigator.pop(ctx);
                          _applyFilter(_AppFilter.collection, collectionId: col.id);
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
    ),
    );
  }

  @override
  Future<void> _openSmartGenreFilters() async {
    final pluginsProvider = context.read<PluginsProvider>();
    if (!pluginsProvider.canUseSmartGenreFilters) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).enableMetadataHint),
        ),
      );
      return;
    }

    final apps = context.read<AppListProvider>().apps;
    final counts = <String, int>{};
    for (final app in apps) {
      for (final label in MacroGenreClassifier.classify(app.metadataGenres)) {
        counts.update(label, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final orderedGenres = MacroGenreClassifier.displayOrder
        .where((label) => (counts[label] ?? 0) > 0)
        .toList(growable: false);

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _tp.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      builder: (ctx) => Focus(
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.gameButtonB ||
              key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            Navigator.pop(ctx);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  AppLocalizations.of(ctx).smartFilters,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppLocalizations.of(ctx).smartFiltersExplain,
                  style: const TextStyle(color: Colors.white60, height: 1.4),
                ),
                const SizedBox(height: 14),
                if (orderedGenres.isEmpty)
                  Text(
                    AppLocalizations.of(ctx).noGenresYet,
                    style: const TextStyle(color: Colors.white70, height: 1.4),
                  )
                else
                  Flexible(
                    child: FocusTraversalGroup(
                      policy: WidgetOrderTraversalPolicy(),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _genreFilterChip(
                              label: AppLocalizations.of(ctx).all,
                              count: apps.length,
                              active: _activeFilter == _AppFilter.all,
                              autofocus: true,
                              onTap: () {
                                Navigator.pop(ctx);
                                _applyFilter(_AppFilter.all);
                              },
                            ),
                            ...orderedGenres.map(
                              (label) => _genreFilterChip(
                                label: MacroGenreClassifier.localizedLabel(label, AppLocalizations.of(ctx)),
                                count: counts[label] ?? 0,
                                active:
                                    _activeFilter == _AppFilter.macroGenre &&
                                    _activeMacroGenre == label,
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _applyFilter(
                                    _AppFilter.macroGenre,
                                    macroGenre: label,
                                  );
                                },
                              ),
                            ),
                          ],
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
  }

  Widget _genreFilterChip({
    required String label,
    required int count,
    required bool active,
    required VoidCallback onTap,
    bool autofocus = false,
  }) {
    return Focus(
      autofocus: autofocus,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final hasFocus = Focus.of(ctx).hasFocus;
        return InkWell(
          onTap: onTap,
          focusColor: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: active
                  ? _tp.accentLight.withValues(alpha: 0.22)
                  : hasFocus
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: active || hasFocus ? Colors.white : Colors.white70,
                    fontWeight: active || hasFocus ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    color: active || hasFocus ? Colors.white70 : Colors.white38,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  @override
  void _applyFilter(
    _AppFilter filter, {
    String? playniteCategory,
    String? macroGenre,
    int? collectionId,
  }) {

    if (filter != _AppFilter.all) {
      final allApps = context.read<AppListProvider>().apps.toList();
      final categories = _categoryItems(allApps);
      final match = categories.where((c) {
        if (c.filter != filter) return false;
        if (filter == _AppFilter.playniteCategory) return c.playniteCategory == playniteCategory;
        if (filter == _AppFilter.collection) return c.collectionId == collectionId;
        return true;
      }).firstOrNull;
      if (match != null && match.count == 0) {
        return;
      }
    }

    if (filter != _activeFilter ||
        playniteCategory != _activePlayniteCategory ||
        macroGenre != _activeMacroGenre) {
      _feedbackNavigate();
    }

    final allApps = context.read<AppListProvider>().apps.toList();
    final categories = _categoryItems(allApps);
    int categoryIndex = categories.indexWhere((c) {
      if (c.filter != filter) return false;
      if (filter == _AppFilter.playniteCategory) return c.playniteCategory == playniteCategory;
      if (filter == _AppFilter.collection) return c.collectionId == collectionId;
      return true;
    });
    if (categoryIndex < 0) categoryIndex = 0;
    setState(() {
      _activeFilter = filter;
      _activePlayniteCategory = filter == _AppFilter.playniteCategory
          ? playniteCategory
          : null;
      _activeMacroGenre = filter == _AppFilter.macroGenre ? macroGenre : null;
      _activeCollectionId = filter == _AppFilter.collection ? collectionId : null;
      _selectedCategoryIndex = categoryIndex >= 0 ? categoryIndex : 0;
      _browseSection = _BrowseSection.carousel;
    });
    _screenFocusNode.requestFocus();
  }

  @override
  String _filterLabel(_AppFilter filter) {
    switch (filter) {
      case _AppFilter.recent:
        return AppLocalizations.of(context).recent;
      case _AppFilter.running:
        return AppLocalizations.of(context).running;
      case _AppFilter.favorites:
        return AppLocalizations.of(context).favorites;
      case _AppFilter.mostPlayed:
        return AppLocalizations.of(context).mostPlayed;
      case _AppFilter.collection:
        final col = _collections.where((c) => c.id == _activeCollectionId).firstOrNull;
        return col?.name ?? AppLocalizations.of(context).collectionFallback;
      case _AppFilter.playniteCategory:
        return _activePlayniteCategory ??
            AppLocalizations.of(context).categoryLabel;
      case _AppFilter.macroGenre:
        return _activeMacroGenre != null
            ? MacroGenreClassifier.localizedLabel(_activeMacroGenre!, AppLocalizations.of(context))
            : AppLocalizations.of(context).genreLabel;
      case _AppFilter.achievements100:
        return AppLocalizations.of(context).achievements100;
      case _AppFilter.achievementsPending:
        return AppLocalizations.of(context).achievementsPending;
      case _AppFilter.achievementsNever:
        return AppLocalizations.of(context).achievementsNeverStarted;
      case _AppFilter.all:
        return AppLocalizations.of(context).all;
    }
  }

  @override
  List<NvApp> _visibleApps(List<NvApp> apps) {
    final visible = apps
        .where((app) {
          final matchesSearch =
              _searchQuery.isEmpty ||
              app.appName.toLowerCase().contains(_searchQuery.toLowerCase());
          final matchesFilter = switch (_activeFilter) {
            _AppFilter.recent =>
              (_profilesByAppId[app.appId]?.lastSessionAtMs ?? 0) > 0,
            _AppFilter.running => app.isRunning,
            _AppFilter.favorites => _favoriteAppIds.contains(app.appId),
            _AppFilter.mostPlayed => _topPlayedAppIds.contains(app.appId),
            _AppFilter.collection =>
              _activeCollectionId != null &&
              (_collections
                .where((c) => c.id == _activeCollectionId)
                .firstOrNull
                ?.appIds
                .contains(app.appId) ?? false),
            _AppFilter.playniteCategory =>
              _activePlayniteCategory != null &&
                  app.tags.contains(_activePlayniteCategory),
            _AppFilter.macroGenre =>
              _activeMacroGenre != null &&
                  MacroGenreClassifier.classify(
                    app.metadataGenres,
                  ).contains(_activeMacroGenre),
            _AppFilter.achievements100 =>
              (_achievementCache[app.appId]?.isComplete ?? false),
            _AppFilter.achievementsPending =>
              (_achievementCache[app.appId]?.inProgress ?? false),
            _AppFilter.achievementsNever =>
              (_achievementCache[app.appId]?.neverStarted ?? false),
            _ => true,
          };
          return matchesSearch && matchesFilter;
        })
        .toList(growable: false);

    visible.sort((left, right) => _compareVisibleApps(left, right));

    if (_activeFilter == _AppFilter.recent) {
      final lp = context.read<LauncherPreferences>();
      if (visible.length > lp.maxRecentCount) {
        return visible.sublist(0, lp.maxRecentCount);
      }
    }

    return visible;
  }

  int _compareVisibleApps(NvApp left, NvApp right) {
    final leftProfile = _profilesByAppId[left.appId];
    final rightProfile = _profilesByAppId[right.appId];

    if (_activeFilter == _AppFilter.all) {
      if (left.isRunning != right.isRunning) {
        return right.isRunning ? 1 : -1;
      }
      return left.appName.toLowerCase().compareTo(right.appName.toLowerCase());
    }

    if (_activeFilter == _AppFilter.recent ||
        _activeFilter == _AppFilter.mostPlayed) {

      if (_activeFilter == _AppFilter.mostPlayed) {
        final leftRank = _topPlayedAppIds.contains(left.appId)
            ? _topPlayedAppIds.indexOf(left.appId)
            : 9999;
        final rightRank = _topPlayedAppIds.contains(right.appId)
            ? _topPlayedAppIds.indexOf(right.appId)
            : 9999;
        return leftRank.compareTo(rightRank);
      }
      return (rightProfile?.lastSessionAtMs ?? 0).compareTo(
        leftProfile?.lastSessionAtMs ?? 0,
      );
    }

    if (left.isRunning != right.isRunning) {
      return right.isRunning ? 1 : -1;
    }

    final leftFavorite = _favoriteAppIds.contains(left.appId);
    final rightFavorite = _favoriteAppIds.contains(right.appId);
    if (leftFavorite != rightFavorite) {
      return rightFavorite ? 1 : -1;
    }

    final recencyDelta = (rightProfile?.lastSessionAtMs ?? 0).compareTo(
      leftProfile?.lastSessionAtMs ?? 0,
    );
    if (recencyDelta != 0) {
      return recencyDelta;
    }

    return left.appName.toLowerCase().compareTo(right.appName.toLowerCase());
  }

  @override
  List<_CategoryItem> _categoryItems(List<NvApp> apps) {
    final lp = context.read<LauncherPreferences>();
    final rawRecentCount = apps
        .where((app) => (_profilesByAppId[app.appId]?.lastSessionAtMs ?? 0) > 0)
        .length;
    final recentCount = rawRecentCount.clamp(0, lp.maxRecentCount);
    final runningCount = apps.where((app) => app.isRunning).length;
    final favoriteCount = apps
        .where((app) => _favoriteAppIds.contains(app.appId))
        .length;

    final items = [
      _CategoryItem(
        filter: _AppFilter.all,
        label: AppLocalizations.of(context).all,
        count: apps.length,
      ),
      _CategoryItem(
        filter: _AppFilter.recent,
        label: AppLocalizations.of(context).recent,
        count: recentCount,
      ),
      _CategoryItem(
        filter: _AppFilter.running,
        label: AppLocalizations.of(context).running,
        count: runningCount,
      ),
      _CategoryItem(
        filter: _AppFilter.favorites,
        label: AppLocalizations.of(context).favorites,
        count: favoriteCount,
      ),

      for (final col in _collections)
        _CategoryItem(
          filter: _AppFilter.collection,
          label: col.name,
          count: col.appIds.where((id) => apps.any((a) => a.appId == id)).length,
          collectionId: col.id,
        ),
    ];

    final provider = context.read<AppListProvider>();
    for (final cat in provider.playniteCategories) {
      if (cat.name.isEmpty) continue;
      final catCount = apps.where((app) => app.tags.contains(cat.name)).length;
      if (catCount == 0) continue;
      items.add(
        _CategoryItem(
          filter: _AppFilter.playniteCategory,
          label: cat.name,
          count: catCount,
          playniteCategory: cat.name,
        ),
      );
    }

    final pluginsProvider = context.read<PluginsProvider>();
    if (pluginsProvider.canUseAchievementsOverlay) {
      if (_achievementsLoading) {
        items.add(
          _CategoryItem(
            filter: _AppFilter.all,
            label: AppLocalizations.of(context).achievements,
            count: 0,
            isLoadingPlaceholder: true,
          ),
        );
      } else if (_achievementCache.isNotEmpty) {
        final count100 = apps
            .where((a) => _achievementCache[a.appId]?.isComplete ?? false)
            .length;
        final countPending = apps
            .where((a) => _achievementCache[a.appId]?.inProgress ?? false)
            .length;
        final countNever = apps
            .where((a) => _achievementCache[a.appId]?.neverStarted ?? false)
            .length;
        if (count100 > 0) {
          items.add(
            _CategoryItem(
              filter: _AppFilter.achievements100,
              label: AppLocalizations.of(context).achievements100,
              count: count100,
            ),
          );
        }
        if (countPending > 0) {
          items.add(
            _CategoryItem(
              filter: _AppFilter.achievementsPending,
              label: AppLocalizations.of(context).achievementsPending,
              count: countPending,
            ),
          );
        }
        if (countNever > 0) {
          items.add(
            _CategoryItem(
              filter: _AppFilter.achievementsNever,
              label: AppLocalizations.of(context).achievementsNeverStarted,
              count: countNever,
            ),
          );
        }
      }
    }

    return items;
  }

  @override
  Widget _buildCategoryBar(
    List<NvApp> apps, {
    bool insertRtAfterFavorites = false,
  }) {
    final categories = _categoryItems(apps);
    final lp = context.read<LauncherPreferences>();

    final recalc = categories.indexWhere((c) {
      if (c.filter != _activeFilter) return false;
      if (_activeFilter == _AppFilter.playniteCategory) return c.playniteCategory == _activePlayniteCategory;
      if (_activeFilter == _AppFilter.collection) return c.collectionId == _activeCollectionId;
      return true;
    });
    _selectedCategoryIndex = (recalc >= 0 ? recalc : 0).clamp(0, categories.length - 1);

    if (!lp.showCategoryBar) return const SizedBox.shrink();

    final accent = _accentColor ?? _tp.accent;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _hintChip('LT', ''),
          const SizedBox(width: 4),
          for (int index = 0; index < categories.length; index++) ...[
            _buildCategoryChip(
              categories[index],
              index,
              categories.length,
              accent,
            ),
          ],
          const SizedBox(width: 4),
          _hintChip('RT', ''),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(
    _CategoryItem item,
    int index,
    int total,
    Color accent,
  ) {
    final active =
        _activeFilter == item.filter &&
        (_activeFilter != _AppFilter.playniteCategory ||
            _activePlayniteCategory == item.playniteCategory) &&
        (_activeFilter != _AppFilter.collection ||
            _activeCollectionId == item.collectionId);
    final focused =
        _browseSection == _BrowseSection.categories &&
        _selectedCategoryIndex == index;
    final lp = context.read<LauncherPreferences>();
    return Padding(
      padding: EdgeInsets.only(right: index < total - 1 ? 4 : 0),
      child: InkWell(
        onTap: item.isLoadingPlaceholder
            ? null
            : () => _applyFilter(
                item.filter,
                playniteCategory: item.playniteCategory,
                collectionId: item.collectionId,
              ),
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: focused
                ? _tp.accentLight.withValues(alpha: 0.18)
                : active
                ? accent.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.isLoadingPlaceholder) ...[
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Colors.white38,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                item.label,
                style: TextStyle(
                  color: active || focused ? Colors.white : Colors.white54,
                  fontWeight: active || focused
                      ? FontWeight.w600
                      : FontWeight.w400,
                  fontSize: 13,
                ),
              ),
              if (!item.isLoadingPlaceholder &&
                  lp.showCategoryCounts &&
                  item.count > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '${item.count}',
                  style: TextStyle(
                    color: active || focused ? Colors.white60 : Colors.white30,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

}

class _CategoryItem {
  final _AppFilter filter;
  final String label;
  final int count;
  final String? playniteCategory;
  final int? collectionId;
  final bool isLoadingPlaceholder;

  const _CategoryItem({
    required this.filter,
    required this.label,
    required this.count,
    this.playniteCategory,
    this.collectionId,
    this.isLoadingPlaceholder = false,
  });
}

class _FilterFocusableTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool autofocus;
  final VoidCallback onTap;

  const _FilterFocusableTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.autofocus = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: autofocus,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final hasFocus = Focus.of(ctx).hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            color: hasFocus
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            leading: leading,
            title: Text(
              title,
              style: TextStyle(
                color: hasFocus ? Colors.white : Colors.white,
                fontWeight: hasFocus ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: subtitle != null
                ? Text(subtitle!,
                    style: const TextStyle(color: Colors.white38, fontSize: 11))
                : null,
            onTap: onTap,
          ),
        );
      }),
    );
  }
}
