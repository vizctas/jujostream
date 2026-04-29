import 'dart:async';
import 'dart:io' as io;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import '../../l10n/app_localizations.dart';
import '../../models/computer_details.dart';
import '../../models/game_collection.dart';
import '../../models/nv_app.dart';
import '../../providers/app_list_provider.dart';
import '../../providers/computer_provider.dart';

import '../../providers/plugins_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../models/theme_config.dart';
import '../../services/metadata/macro_genre_classifier.dart';
import '../../services/database/achievement_service.dart';
import '../../services/metadata/steam_achievement_service.dart';
import '../../services/preferences/game_preferences_store.dart';
import '../../services/preferences/launcher_preferences.dart';
import 'app_details_screen.dart';
import 'app_view_presentation_settings_screen.dart';
import '../../services/audio/ui_sound_service.dart';
import '../../services/input/gamepad_button_helper.dart';
import '../../services/database/app_override_service.dart';
import '../../services/database/collections_service.dart';
import '../../services/database/session_history_service.dart';
import '../../services/http_api/nv_http_client.dart';
import '../../services/network/smart_bitrate_service.dart';
import '../../services/stream/image_load_throttle.dart';
import '../../services/tv/tv_detector.dart';
import '../../themes/launcher_theme.dart';
import '../../widgets/poster_image.dart';
import '../../widgets/screensaver_overlay.dart';
import '../game/game_stream_screen.dart';
import '../../models/stream_configuration.dart';

part 'app_view_cards.dart';
part 'app_view_carousel.dart';
part 'app_view_discovery.dart';
part 'app_view_filters.dart';
part 'app_view_gamepad_handler.dart';
part 'app_view_grid.dart';
part 'app_view_video_preview.dart';

enum _BrowseSection { categories, carousel }

enum _AppFilter {
  all,
  recent,
  running,
  favorites,
  mostPlayed,
  collection,
  playniteCategory,
  macroGenre,
  achievements100,
  achievementsPending,
  achievementsNever,
}

enum _ViewMode { carousel, grid }

class AppViewScreen extends StatefulWidget {
  final ComputerDetails computer;

  const AppViewScreen({super.key, required this.computer});

  @override
  State<AppViewScreen> createState() => _AppViewScreenState();
}

abstract class _AppViewScreenBase extends State<AppViewScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Widget _buildGridLayout(
    List<NvApp> apps,
    List<NvApp> visibleApps,
    NvApp selected,
  );
  void _onGridScroll();
  void _scrollGridToIndex(int index);
  int _gridCrossAxisCount();
  Widget _buildHorizontalCarousel(List<NvApp> apps, NvApp selected);
  Widget _buildCarouselHintsRow();
  void _centerOnIndex(int index, int total, {bool animate = true});
  Widget _buildCategoryBar(
    List<NvApp> apps, {
    bool insertRtAfterFavorites = false,
  });
  Widget _buildInlineFilterBar(List<NvApp> apps);
  List<NvApp> _visibleApps(List<NvApp> apps);
  List<_CategoryItem> _categoryItems(List<NvApp> apps);
  void _applyFilter(
    _AppFilter filter, {
    String? playniteCategory,
    int? collectionId,
  });
  String _filterLabel(_AppFilter filter);
  Future<void> _openSearch();
  Future<void> _openFilterPicker();
  Future<void> _openSmartGenreFilters();
  Widget _buildDiscoveryBoostSection(NvApp selected, List<NvApp> allApps);
  void _queueAccentColorExtraction(NvApp app);
  Future<void> _extractAccentColor(NvApp app);
  void _scheduleVideoPreview(NvApp app);
  String? _previewUrlFor(NvApp app);
  void _disposeVideoController();
  KeyEventResult _onKeyEvent(KeyEvent event, List<NvApp> apps, NvApp selected);
  void _moveSelection(List<NvApp> apps, int delta);
  Timer? _refreshTimer;
  // Only widgets wrapped in ValueListenableBuilder rebuild when selection moves.
  final ValueNotifier<int?> _selectedAppIdNotifier = ValueNotifier<int?>(null);
  int? get _selectedAppId => _selectedAppIdNotifier.value;
  set _selectedAppId(int? v) => _selectedAppIdNotifier.value = v;
  int? _focusedAppId;
  String _searchQuery = '';
  _AppFilter _activeFilter = _AppFilter.all;
  _ViewMode _viewMode = _ViewMode.carousel;
  String? _activePlayniteCategory;
  String? _activeMacroGenre;
  _BrowseSection _browseSection = _BrowseSection.carousel;
  int _selectedCategoryIndex = 0;
  Set<int> _favoriteAppIds = <int>{};
  List<int> _topPlayedAppIds = const <int>[];
  int? _activeCollectionId;
  List<GameCollection> _collections = const <GameCollection>[];
  final GamePreferencesStore _gamePreferencesStore =
      const GamePreferencesStore();
  final Map<int, GamePreferencesProfile> _profilesByAppId = {};
  final ScrollController _carouselController = ScrollController();
  final ScrollController _gridScrollController = ScrollController();
  final FocusNode _screenFocusNode = FocusNode(debugLabel: 'app-view-screen');
  final Map<int, FocusNode> _cardFocusNodes = {};
  late final AnimationController _backgroundMotionController;
  late final Animation<Offset> _backgroundDrift;
  late final Animation<double> _burnScale;

  bool _profilesLoading = false;
  bool _profilesPrimed = false;

  Color? _accentColor;

  AppThemeColors get _tp => context.read<ThemeProvider>().colors;
  int? _accentAppId;
  Timer? _accentDebounce;
  int _accentRequestId = 0;

  VideoPlayerController? _videoController;
  Timer? _videoDelayTimer;
  int? _videoForAppId;
  bool _videoReady = false;
  bool? _videoPluginWasEnabled;

  final SteamAchievementService _achievementService =
      const SteamAchievementService();
  final Map<int, AchievementProgress?> _achievementCache = {};
  bool _achievementsLoading = false;
  bool _achievementsInitiated = false;
  bool _focusRequested = false;
  String _achievementCredentialsKey = '';

  final ScrollController _discoveryController = ScrollController();

  bool _showBottomFilterBar = false;

  bool _postersHidden = false;

  bool _isLaunching = false;

  bool _isDetailView = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppListProvider>().loadApps(widget.computer);

      if (widget.computer.activeAddress.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          unawaited(
            NvHttpClient()
                .getServerInfoHttps(
                  widget.computer.activeAddress,
                  httpsPort: widget.computer.httpsPort,
                )
                .catchError((_) => null),
          );
        });
      }
    });
    _loadFavorites();
    unawaited(_loadTopPlayed());
    unawaited(_loadCollections());
    _gridScrollController.addListener(_onGridScroll);
    _backgroundMotionController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduce = context.read<ThemeProvider>().reduceEffects;
      if (!TvDetector.instance.isTV && !reduce) {
        _backgroundMotionController.repeat(reverse: true);
      }
    });
    _backgroundDrift =
        Tween<Offset>(
          begin: const Offset(-12, -6),
          end: const Offset(12, 8),
        ).animate(
          CurvedAnimation(
            parent: _backgroundMotionController,
            curve: Curves.easeInOut,
          ),
        );

    _burnScale = Tween<double>(begin: 1.04, end: 1.18).animate(
      CurvedAnimation(
        parent: _backgroundMotionController,
        curve: Curves.easeInOut,
      ),
    );

    _startAutoRefreshTimer();
  }

  void _startAutoRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final provider = context.read<AppListProvider>();
      if (!provider.isLoading && !provider.isEnriching) {
        provider.refresh();
      }
    });
  }

  void _stopAutoRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _stopAutoRefreshTimer();
      _videoController?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _startAutoRefreshTimer();
      _videoController?.play();
      if (!context.read<ComputerProvider>().isPairing) {
        context.read<AppListProvider>().refresh();
      }
    }
  }

  Future<void> _primeProfilesForCurrentApps() async {
    if (_profilesLoading || !mounted) return;
    final apps = context.read<AppListProvider>().apps;
    await _primeProfiles(apps.toList());
  }

  Future<void> _loadAllAchievements(List<NvApp> apps) async {
    if (_achievementsLoading || !mounted) return;
    final pluginsProvider = context.read<PluginsProvider>();
    if (!pluginsProvider.canUseAchievementsOverlay) return;

    final apiKey = await pluginsProvider.getApiKey('steam_connect');
    final steamId = await pluginsProvider.getSetting(
      'steam_connect',
      'steam_id',
    );
    if (apiKey == null ||
        apiKey.isEmpty ||
        steamId == null ||
        steamId.isEmpty) {
      return;
    }

    final credKey = '${apiKey}_$steamId';
    if (credKey != _achievementCredentialsKey) {
      _achievementCredentialsKey = credKey;
      _achievementCache.clear();
    }

    if (!mounted) return;
    setState(() => _achievementsLoading = true);

    final targets = apps.where((a) => a.steamAppId != null).toList();

    for (var i = 0; i < targets.length; i += 4) {
      if (!mounted) break;
      final batch = targets.sublist(i, (i + 4).clamp(0, targets.length));
      await Future.wait(
        batch.map((app) async {
          final progress = await _achievementService.fetchGameProgress(
            apiKey: apiKey,
            steamId: steamId,
            steamAppId: app.steamAppId!,
          );
          if (mounted) setState(() => _achievementCache[app.appId] = progress);
        }),
      );
    }

    if (mounted) setState(() => _achievementsLoading = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAutoRefreshTimer();
    _accentDebounce?.cancel();
    _videoDelayTimer?.cancel();
    _videoController?.dispose();
    _backgroundMotionController.dispose();
    _carouselController.dispose();
    _gridScrollController.dispose();
    _discoveryController.dispose();
    _screenFocusNode.dispose();
    for (final node in _cardFocusNodes.values) {
      node.dispose();
    }
    _selectedAppIdNotifier.dispose();
    super.dispose();
  }

  String get _favoritesKey {
    return 'favorite_apps_$_hostId';
  }

  String get _hostId => widget.computer.uuid.isNotEmpty
      ? widget.computer.uuid
      : widget.computer.localAddress;

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_favoritesKey) ?? const [];
    if (!mounted) return;
    setState(() {
      _favoriteAppIds = values.map(int.parse).toSet();
    });
  }

  Future<void> _loadTopPlayed() async {
    final ids = await SessionHistoryService.topPlayedAppIds(limit: 200);
    if (!mounted) return;
    setState(() => _topPlayedAppIds = ids);
  }

  Future<void> _loadCollections() async {
    final cols = await CollectionsService.getAll();
    if (!mounted) return;
    setState(() => _collections = cols);
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _favoritesKey,
      _favoriteAppIds.map((e) => e.toString()).toList(growable: false),
    );
  }

  Future<void> _toggleFavorite(NvApp app) async {
    _feedbackAction();
    final adding = !_favoriteAppIds.contains(app.appId);

    setState(() {
      if (adding) {
        _favoriteAppIds.add(app.appId);
      } else {
        _favoriteAppIds.remove(app.appId);
      }
    });
    await _saveFavorites();

    UiSoundService.playFavorite();
    _showFavoriteFeedback(adding);

    if (adding) {
      unawaited(AchievementService.instance.unlock('first_favorite'));
      if (_favoriteAppIds.length >= 10) {
        unawaited(AchievementService.instance.unlock('favorites_10'));
      }
    }
  }

  void _toggleViewMode(List<NvApp> apps) {
    _feedbackAction();
    setState(() {
      _viewMode = _viewMode == _ViewMode.carousel
          ? _ViewMode.grid
          : _ViewMode.carousel;
    });
    if (_viewMode == _ViewMode.grid) {
      _disposeVideoController();
      return;
    }

    final visibleApps = _visibleApps(apps);
    if (visibleApps.isNotEmpty) {
      _scheduleVideoPreview(_selectedApp(visibleApps));
    }
    _restoreScrollPosition();
  }

  void _showFavoriteFeedback(bool added) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FavoriteHeartOverlay(
        added: added,
        accent: _tp.accent,
        onDone: () => entry.remove(),
      ),
    );
    Overlay.of(context).insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    return ScreensaverWrapper(
      onScreensaverChanged: (active) {
        if (active) {
          _videoController?.pause();
        } else {
          if (_videoReady && _videoController != null) {
            _videoController!.play();
          }
        }
      },
      child: Scaffold(
        backgroundColor: _tp.background,
        resizeToAvoidBottomInset: false,

        body: Consumer<AppListProvider>(
          builder: (context, provider, child) {
            final pluginsProvider = context.watch<PluginsProvider>();
            if (_activeFilter == _AppFilter.macroGenre &&
                !pluginsProvider.canUseSmartGenreFilters) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted &&
                    _activeFilter == _AppFilter.macroGenre &&
                    !context.read<PluginsProvider>().canUseSmartGenreFilters) {
                  _applyFilter(_AppFilter.all);
                }
              });
            }

            if ((_activeFilter == _AppFilter.achievements100 ||
                    _activeFilter == _AppFilter.achievementsPending ||
                    _activeFilter == _AppFilter.achievementsNever) &&
                !pluginsProvider.canUseAchievementsOverlay) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _applyFilter(_AppFilter.all);
              });
            }

            if (pluginsProvider.canUseAchievementsOverlay &&
                !_achievementsInitiated &&
                provider.apps.isNotEmpty) {
              _achievementsInitiated = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _loadAllAchievements(provider.apps.toList());
              });
            }

            if (_videoPluginWasEnabled != true && provider.apps.isNotEmpty) {
              _videoPluginWasEnabled = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final visibleApps = _visibleApps(provider.apps.toList());
                if (visibleApps.isNotEmpty) {
                  _scheduleVideoPreview(_selectedApp(visibleApps));
                }
              });
            }

            if (provider.apps.isNotEmpty && !_profilesPrimed) {
              _profilesPrimed = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _primeProfilesForCurrentApps();
              });
            }

            if (provider.apps.isNotEmpty && !_focusRequested) {
              _focusRequested = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _screenFocusNode.requestFocus();
              });
            }

            // Show skeleton when:
            //  1. Actively loading with no apps yet, OR
            //  2. Pre-load state: loadApps() hasn't been called yet for this
            //     screen (isLoading=false, apps empty, no error). This happens
            //     on the very first build frame before addPostFrameCallback
            //     fires loadApps(). Without this, the user briefly sees the
            //     "No apps found" empty state before the skeleton appears.
            final isPreLoadState =
                !provider.isLoading &&
                provider.apps.isEmpty &&
                provider.error == null;
            if ((provider.isLoading && provider.apps.isEmpty) ||
                isPreLoadState) {
              return Scaffold(
                backgroundColor: _tp.background,
                body: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back,
                          color: _tp.isLight ? Colors.black87 : Colors.white,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: List.generate(
                            4,
                            (_) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Container(
                                width: 64,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              children: List.generate(
                                5,
                                (i) => Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: _SkeletonCard(
                                    delay: Duration(milliseconds: i * 120),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (provider.error != null && provider.apps.isEmpty) {
              return Focus(
                autofocus: true,
                onKeyEvent: (_, ev) {
                  if (ev is! KeyDownEvent) return KeyEventResult.ignored;
                  final k = ev.logicalKey;
                  if (k == LogicalKeyboardKey.gameButtonB ||
                      k == LogicalKeyboardKey.goBack ||
                      k == LogicalKeyboardKey.escape) {
                    Navigator.maybePop(context);
                    return KeyEventResult.handled;
                  }
                  if (k == LogicalKeyboardKey.gameButtonA ||
                      k == LogicalKeyboardKey.select ||
                      k == LogicalKeyboardKey.enter) {
                    provider.loadApps(widget.computer);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Scaffold(
                  backgroundColor: _tp.background,
                  appBar: AppBar(
                    title: Text(widget.computer.name),
                    backgroundColor: _tp.surface,
                    foregroundColor: _tp.isLight
                        ? Colors.black87
                        : Colors.white,
                    elevation: 0,
                    leading: IconButton(
                      autofocus: false,
                      icon: Icon(
                        Icons.arrow_back,
                        color: _tp.isLight ? Colors.black87 : Colors.white,
                      ),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                  ),
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            provider.error!,
                            style: const TextStyle(color: Colors.white70),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          autofocus: true,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(AppLocalizations.of(context).retry),
                          onPressed: () => provider.loadApps(widget.computer),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            if (provider.apps.isEmpty) {
              return Focus(
                autofocus: true,
                onKeyEvent: (_, ev) {
                  if (ev is! KeyDownEvent) return KeyEventResult.ignored;
                  final k = ev.logicalKey;
                  if (k == LogicalKeyboardKey.gameButtonB ||
                      k == LogicalKeyboardKey.goBack ||
                      k == LogicalKeyboardKey.escape) {
                    Navigator.maybePop(context);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Scaffold(
                  backgroundColor: _tp.background,
                  appBar: AppBar(
                    title: Text(widget.computer.name),
                    backgroundColor: _tp.surface,
                    foregroundColor: _tp.isLight
                        ? Colors.black87
                        : Colors.white,
                    elevation: 0,
                    leading: IconButton(
                      autofocus: false,
                      icon: Icon(
                        Icons.arrow_back,
                        color: _tp.isLight ? Colors.black87 : Colors.white,
                      ),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                  ),
                  body: Center(
                    child: Text(
                      AppLocalizations.of(context).noAppsFound,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              );
            }

            final launcherTheme = context.read<ThemeProvider>().launcherTheme;
            if (launcherTheme.id != LauncherThemeId.classic &&
                _viewMode != _ViewMode.grid) {
              final visibleApps = _visibleApps(provider.apps.toList());
              _ensureValidSelection(visibleApps);
              final selected = _selectedApp(visibleApps);

              Widget? videoWidget;
              int? videoAppId;
              if (_videoReady &&
                  _videoController != null &&
                  _videoController!.value.isInitialized &&
                  _videoForAppId != null) {
                videoAppId = _videoForAppId;
                videoWidget = FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _videoController!.value.size.width,
                    height: _videoController!.value.size.height,
                    child: VideoPlayer(_videoController!),
                  ),
                );
              }
              return launcherTheme.buildBody(
                context: context,
                apps: visibleApps,
                allApps: provider.apps.toList(),
                selectedIndex: visibleApps
                    .indexOf(selected)
                    .clamp(0, visibleApps.length - 1),
                onAppSelected: _handleAppTap,
                onAppDetails: _openDetailsScreen,
                onIndexChanged: (i) {
                  if (i >= 0 && i < visibleApps.length) {
                    setState(() {
                      _selectedAppId = visibleApps[i].appId;
                      _focusedAppId = visibleApps[i].appId;
                    });
                    _queueAccentColorExtraction(visibleApps[i]);
                    _scheduleVideoPreview(visibleApps[i]);
                  }
                },
                activeSessionAppId: provider.apps
                    .cast<NvApp?>()
                    .firstWhere((a) => a?.isRunning == true, orElse: () => null)
                    ?.appId
                    .toString(),
                isGridView: _viewMode == _ViewMode.grid,
                favoriteIds: _favoriteAppIds.map((id) => id.toString()).toSet(),
                onToggleFavorite: _toggleFavorite,
                onToggleView: () => _toggleViewMode(provider.apps.toList()),
                videoWidget: videoWidget,
                videoForAppId: videoAppId,
                onSearch: _openSearch,
                onFilter: _openFilterPicker,
                onSmartFilters: _openSmartGenreFilters,
                onResumeRunning: () {
                  final running = provider.apps.cast<NvApp?>().firstWhere(
                    (a) => a?.isRunning == true,
                    orElse: () => null,
                  );
                  if (running != null) _showRunningSheet(running);
                },
                onDetailViewChanged: (inDetail) {
                  _isDetailView = inDetail;
                  if (inDetail) {
                    final sel = _selectedApp(visibleApps);
                    _scheduleVideoPreview(sel);
                  } else {
                    _disposeVideoController();
                  }
                },
                activeFilterLabel: _filterLabel(_activeFilter),
              );
            }
            return _buildCarouselScreen(provider.apps);
          },
        ),
      ),
    );
  }

  Widget _buildCarouselScreen(List<NvApp> apps) {
    final visibleApps = _visibleApps(apps);
    _syncFocusNodes(visibleApps);
    _ensureValidSelection(visibleApps);
    final selected = _selectedApp(visibleApps);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    if (_previewUrlFor(selected) != null &&
        _videoForAppId != selected.appId &&
        _videoDelayTimer == null) {
      debugPrint(
        '[JUJO][video] re-trigger: URL arrived for ${selected.appName} → scheduling',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_selectedAppId == selected.appId &&
            _videoForAppId != selected.appId &&
            _videoDelayTimer == null) {
          debugPrint(
            '[JUJO][video] re-trigger callback → calling _scheduleVideoPreview',
          );
          _scheduleVideoPreview(selected);
        } else {
          debugPrint(
            '[JUJO][video] re-trigger callback SKIPPED: '
            'selMatch=${_selectedAppId == selected.appId} '
            'videoForApp=$_videoForAppId timer=${_videoDelayTimer != null}',
          );
        }
      });
    }

    final reduce = context.watch<ThemeProvider>().reduceEffects;
    final shouldAnimate = !TvDetector.instance.isTV && !reduce;

    if (shouldAnimate && !_backgroundMotionController.isAnimating) {
      _backgroundMotionController.repeat(reverse: true);
    } else if (!shouldAnimate && _backgroundMotionController.isAnimating) {
      _backgroundMotionController.stop();
      _backgroundMotionController.reset();
    }

    return Focus(
      focusNode: _screenFocusNode,
      autofocus: true,
      onKeyEvent: (_, event) => _onKeyEvent(event, visibleApps, selected),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragEnd: (details) {
          if (_viewMode != _ViewMode.carousel) return;
          final v = details.primaryVelocity ?? 0;
          if (v < -300) {
            if (!_postersHidden) {
              _feedbackNavigate();
              setState(() => _postersHidden = true);
            }
          } else if (v > 300) {
            if (_postersHidden) {
              _feedbackNavigate();
              setState(() => _postersHidden = false);
            } else if (!_showBottomFilterBar) {
              setState(() => _showBottomFilterBar = true);
            }
          }
        },
        onHorizontalDragEnd: (details) {
          if (_viewMode != _ViewMode.carousel || !_postersHidden) return;
          final v = details.primaryVelocity ?? 0;
          if (v < -300) {
            _feedbackNavigate();
            setState(() => _postersHidden = false);
            _moveSelection(visibleApps, 1);
          } else if (v > 300) {
            _feedbackNavigate();
            setState(() => _postersHidden = false);
            _moveSelection(visibleApps, -1);
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildDynamicBackground(selected),

            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x55000000), Color(0xBB000000)],
                ),
              ),
            ),
            SafeArea(
              child: _viewMode == _ViewMode.grid
                  ? _buildGridLayout(apps, visibleApps, selected)
                  : isLandscape
                  ? _buildLandscapeLayout(apps, visibleApps, selected)
                  : _buildPortraitLayout(apps, visibleApps, selected),
            ),

            _buildFloatingNavRow(apps, selected),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(
    List<NvApp> apps,
    List<NvApp> visibleApps,
    NvApp selected,
  ) {
    NvApp? runningApp;
    for (final app in apps) {
      if (app.isRunning) {
        runningApp = app;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTransparentAppBar(apps),

        if (runningApp != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: _buildContinueBanner(runningApp, true),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: _buildPortraitHeader(selected),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildCategoryBar(apps),
        ),
        const Spacer(),

        _buildCarouselHintsRow(),

        _buildCollapsibleCarousel(visibleApps, selected),

        _buildDiscoveryBoostSection(selected, apps),

        _buildInlineFilterBar(apps),

        const SizedBox(height: 72),
      ],
    );
  }

  Widget _buildContinueBanner(NvApp app, bool isNowPlaying) {
    final accent = _accentColor ?? _tp.accent;
    final color = isNowPlaying ? Colors.greenAccent : accent;
    final l = AppLocalizations.of(context);
    final label = isNowPlaying ? l.nowPlaying : l.continueLabel;
    final icon = isNowPlaying
        ? Icons.radio_button_checked
        : Icons.play_circle_outline;

    return GestureDetector(
      onTap: () => _handleAppTap(app),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 8),
            if (app.posterUrl != null && app.posterUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: PosterImage(
                  url: app.posterUrl!,
                  width: 26,
                  height: 34,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                app.appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout(
    List<NvApp> apps,
    List<NvApp> visibleApps,
    NvApp selected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTransparentAppBar(apps),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            selected.appName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              shadows: [Shadow(color: Colors.black87, blurRadius: 10)],
            ),
          ),
        ),

        const Spacer(),

        _buildCarouselHintsRow(),

        _buildCollapsibleCarousel(visibleApps, selected),
        _buildDiscoveryBoostSection(selected, apps),

        _buildInlineFilterBar(apps),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTransparentAppBar(List<NvApp> apps) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: Text(
              widget.computer.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          _appBarBtn(
            _viewMode == _ViewMode.carousel
                ? Icons.grid_view_rounded
                : Icons.view_carousel,
            _viewMode == _ViewMode.carousel ? 'Grid' : 'List',
            () => _toggleViewMode(apps),
            gamepadHint: 'X',
          ),
          const SizedBox(width: 6),
          _appBarBtn(Icons.search, 'Search', () {
            _feedbackAction();
            _openSearch();
          }, gamepadHint: 'R3'),
          const SizedBox(width: 4),
          if (apps.any((a) => a.isRunning))
            GestureDetector(
              onTap: () => _confirmQuitApp(context.read<AppListProvider>()),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.stop_circle_outlined,
                      color: Colors.redAccent,
                      size: 17,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      AppLocalizations.of(context).quitSession,
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPortraitHeader(NvApp selected) {
    final isFav = _favoriteAppIds.contains(selected.appId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          selected.appName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            shadows: [Shadow(color: Colors.black87, blurRadius: 12)],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            if (selected.isRunning) ...[
              _statusBadge(
                AppLocalizations.of(context).runningStatus,
                Colors.greenAccent,
              ),
              const SizedBox(width: 6),
            ],
            if (isFav) _statusBadge('★', Colors.amberAccent),
            if (selected.isHdrSupported) ...[
              const SizedBox(width: 6),
              _statusBadge('HDR', Colors.cyanAccent),
            ],
          ],
        ),
      ],
    );
  }

  Widget _statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _appBarBtn(
    IconData icon,
    String label,
    VoidCallback onTap, {
    String? gamepadHint,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
            if (gamepadHint != null) ...[
              const SizedBox(width: 4),
              GamepadHintIcon(gamepadHint, size: 17, forceVisible: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badgedIconButton(IconData icon, String badge, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          children: [
            Center(
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: Colors.white, size: 20),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hintChip(String button, String label, {VoidCallback? onTap}) {
    final child = Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GamepadHintIcon(button, size: 18, forceVisible: true),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 9),
          ),
        ],
      ),
    );
    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: child,
      );
    }
    return child;
  }

  Widget _buildCollapsibleCarousel(List<NvApp> visibleApps, NvApp selected) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: _postersHidden
          ? const SizedBox(width: double.infinity)
          : visibleApps.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              child: Text(
                _searchQuery.isEmpty
                    ? AppLocalizations.of(context).noResults
                    : AppLocalizations.of(context).noResultsQuery(_searchQuery),
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            )
          : _buildHorizontalCarousel(visibleApps, selected),
    );
  }

  Widget _buildFloatingNavRow(List<NvApp> apps, NvApp selected) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (isLandscape) return const SizedBox.shrink();

    final accentBtn = _accentColor ?? _tp.accent;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xDD000000)],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _handleAppTap(selected),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 48,
                    decoration: BoxDecoration(
                      color: accentBtn,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: accentBtn.withValues(alpha: 0.40),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 26,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          selected.isRunning
                              ? AppLocalizations.of(context).resume
                              : AppLocalizations.of(context).play,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              _floatingIconBtn(
                _viewMode == _ViewMode.carousel
                    ? Icons.grid_view_rounded
                    : Icons.view_carousel,
                () => _toggleViewMode(apps),
              ),
              const SizedBox(width: 8),

              _floatingIconBtn(Icons.info_outline, () {
                _feedbackAction();
                _openDetailsScreen(selected);
              }),
              const SizedBox(width: 8),

              _floatingIconBtn(Icons.search, () {
                _feedbackAction();
                _openSearch();
              }),
              const SizedBox(width: 8),

              _floatingIconBtn(Icons.more_horiz, () {
                _feedbackAction();
                _showActionsSheet(apps, selected);
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _floatingIconBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      focusColor: _tp.accent.withValues(alpha: 0.4),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  void _showActionsSheet(List<NvApp> apps, NvApp selected) {
    final isFav = _favoriteAppIds.contains(selected.appId);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _tp.surface,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
        child: FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Text(
                    selected.appName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.07)),
                const SizedBox(height: 4),
                _sheetOption(
                  Icons.tune,
                  AppLocalizations.of(ctx).gameOptions,
                  Colors.white70,
                  () {
                    Navigator.pop(ctx);
                    _showRunningSheet(selected);
                  },
                  autofocus: true,
                ),
                _sheetOption(
                  isFav ? Icons.star : Icons.star_outline,
                  isFav
                      ? AppLocalizations.of(ctx).removeFromFavorites
                      : AppLocalizations.of(ctx).addToFavorites,
                  Colors.amberAccent,
                  () {
                    Navigator.pop(ctx);
                    _toggleFavorite(selected);
                  },
                ),
                _sheetOption(
                  Icons.search,
                  AppLocalizations.of(ctx).searchGame,
                  Colors.white70,
                  () {
                    Navigator.pop(ctx);
                    _openSearch();
                  },
                ),
                _sheetOption(
                  Icons.palette_outlined,
                  AppLocalizations.of(ctx).launcherAppearance,
                  Colors.white60,
                  () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AppViewPresentationSettingsScreen(
                          preferences: context.read<LauncherPreferences>(),
                        ),
                      ),
                    );
                  },
                ),
                _sheetOption(
                  Icons.auto_awesome_outlined,
                  AppLocalizations.of(ctx).smartFilters,
                  Colors.cyanAccent,
                  () {
                    Navigator.pop(ctx);
                    _openSmartGenreFilters();
                  },
                ),
                _sheetOption(
                  Icons.refresh,
                  AppLocalizations.of(ctx).updateMetadata,
                  Colors.tealAccent,
                  () {
                    Navigator.pop(ctx);
                    final provider = context.read<AppListProvider>();
                    provider.triggerMetadataEnrichment();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocalizations.of(context).updatingMetadata,
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                if (apps.any((a) => a.isRunning))
                  _sheetOption(
                    Icons.stop_circle_outlined,
                    AppLocalizations.of(ctx).closeActiveSession,
                    Colors.redAccent,
                    () {
                      Navigator.pop(ctx);
                      _confirmQuitApp(context.read<AppListProvider>());
                    },
                  ),
                _sheetOption(
                  Icons.playlist_add,
                  'Agregar a colección',
                  Colors.purpleAccent,
                  () {
                    Navigator.pop(ctx);
                    _showAddToCollectionSheet(selected);
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAddToCollectionSheet(NvApp app) async {
    if (_collections.isEmpty) {
      final name = await _promptCollectionName();
      if (name == null || name.trim().isEmpty) return;
      final id = await CollectionsService.create(name.trim());
      if (id > 0) {
        await CollectionsService.addApp(id, app.appId);
        await _loadCollections();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${app.appName}" agregado a "$name"')),
          );
        }
      }
      return;
    }

    final inCollections = await CollectionsService.collectionsForApp(app.appId);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _tp.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return Focus(
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
          child: StatefulBuilder(
            builder: (ctx, setSheet) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: FocusTraversalGroup(
                  policy: WidgetOrderTraversalPolicy(),
                  child: SingleChildScrollView(
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
                          app.appName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Selecciona una colección',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        ...(_collections.asMap().entries.map((entry) {
                          final i = entry.key;
                          final col = entry.value;
                          final inCol = inCollections.contains(col.id);
                          return _CollectionFocusableTile(
                            autofocus: i == 0,
                            inCollection: inCol,
                            colorValue: col.colorValue,
                            name: col.name,
                            count: col.appIds.length,
                            onTap: () async {
                              if (inCol) {
                                await CollectionsService.removeApp(
                                  col.id!,
                                  app.appId,
                                );
                                setSheet(() => inCollections.remove(col.id));
                              } else {
                                await CollectionsService.addApp(
                                  col.id!,
                                  app.appId,
                                );
                                setSheet(() => inCollections.add(col.id!));
                              }
                              await _loadCollections();
                            },
                          );
                        })),
                        const Divider(color: Colors.white12, height: 24),
                        Focus(
                          onKeyEvent: (_, event) {
                            if (event is! KeyDownEvent) {
                              return KeyEventResult.ignored;
                            }
                            final key = event.logicalKey;
                            if (key == LogicalKeyboardKey.gameButtonA ||
                                key == LogicalKeyboardKey.enter ||
                                key == LogicalKeyboardKey.select) {
                              Navigator.pop(ctx);
                              _promptCollectionName().then((name) async {
                                if (name == null || name.trim().isEmpty) return;
                                final id = await CollectionsService.create(
                                  name.trim(),
                                );
                                if (id > 0) {
                                  await CollectionsService.addApp(
                                    id,
                                    app.appId,
                                  );
                                  await _loadCollections();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '"${app.appName}" agregado a "$name"',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              });
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: Builder(
                            builder: (focusCtx) {
                              final hasFocus = Focus.of(focusCtx).hasFocus;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                decoration: BoxDecoration(
                                  color: hasFocus
                                      ? Colors.white.withValues(alpha: 0.10)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: TextButton.icon(
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    final name = await _promptCollectionName();
                                    if (name == null || name.trim().isEmpty) {
                                      return;
                                    }
                                    final id = await CollectionsService.create(
                                      name.trim(),
                                    );
                                    if (id > 0) {
                                      await CollectionsService.addApp(
                                        id,
                                        app.appId,
                                      );
                                      await _loadCollections();
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '"${app.appName}" agregado a "$name"',
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.add,
                                    color: Colors.purpleAccent,
                                  ),
                                  label: const Text(
                                    'Nueva colección',
                                    style: TextStyle(
                                      color: Colors.purpleAccent,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<String?> _promptCollectionName() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
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
        child: AlertDialog(
          backgroundColor: ctx.read<ThemeProvider>().surface,
          title: Text(
            AppLocalizations.of(context).newCollection,
            style: const TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context).collectionNameHint,
              hintStyle: const TextStyle(color: Colors.white38),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: ctx.read<ThemeProvider>().accent),
              ),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(AppLocalizations.of(context).create),
            ),
          ],
        ),
      ),
    );
  }

  void _syncFocusNodes(List<NvApp> apps) {
    final appIds = apps.map((a) => a.appId).toSet();
    final staleIds = _cardFocusNodes.keys
        .where((id) => !appIds.contains(id))
        .toList();
    for (final id in staleIds) {
      _cardFocusNodes.remove(id)?.dispose();
    }
    for (final app in apps) {
      _cardFocusNodes.putIfAbsent(
        app.appId,
        () => FocusNode(debugLabel: 'app-${app.appId}'),
      );
    }
  }

  Future<void> _primeProfiles(List<NvApp> apps) async {
    if (_profilesLoading) return;
    final missingIds = apps
        .map((a) => a.appId)
        .where((id) => !_profilesByAppId.containsKey(id))
        .toList(growable: false);
    if (missingIds.isEmpty) return;
    _profilesLoading = true;
    final profiles = await _gamePreferencesStore.loadProfiles(
      _hostId,
      missingIds,
    );
    if (!mounted) {
      _profilesLoading = false;
      return;
    }
    setState(() {
      _profilesByAppId.addAll(profiles);
      for (final id in missingIds) {
        _profilesByAppId.putIfAbsent(
          id,
          () => GamePreferencesProfile(appId: id),
        );
      }
    });
    _profilesLoading = false;
  }

  void _ensureValidSelection(List<NvApp> apps) {
    if (apps.isEmpty) return;
    if (_selectedAppId == null || !apps.any((a) => a.appId == _selectedAppId)) {
      _selectedAppId = apps.first.appId;
      _focusedAppId = apps.first.appId;

      _queueAccentColorExtraction(apps.first);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _requestCardFocus(apps.first.appId);
        _centerOnIndex(0, apps.length, animate: false);
      });
    }
  }

  void _requestCardFocus(int appId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cardFocusNodes[appId]?.requestFocus();
    });
  }

  NvApp _selectedApp(List<NvApp> apps) {
    if (apps.isEmpty) {
      return NvApp(appId: 0, appName: 'No App');
    }
    final id = _selectedAppId;
    if (id != null) {
      for (final app in apps) {
        if (app.appId == id) return app;
      }
    }

    return apps.first;
  }

  void _restoreScrollPosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<AppListProvider>();
      final visibleApps = _visibleApps(provider.apps.toList());
      if (visibleApps.isEmpty) return;
      final idx = visibleApps.indexWhere((a) => a.appId == _selectedAppId);
      if (idx < 0) return;
      if (_viewMode == _ViewMode.carousel) {
        _centerOnIndex(idx, visibleApps.length, animate: false);
      }
    });
  }

  int? _debouncedBgAppId;
  Timer? _bgDebounce;

  Widget _buildDynamicBackground(NvApp selected) {
    if (_debouncedBgAppId != selected.appId) {
      _bgDebounce?.cancel();
      _bgDebounce = Timer(const Duration(milliseconds: 200), () {
        if (mounted && _selectedAppId == selected.appId) {
          setState(() => _debouncedBgAppId = selected.appId);
        }
      });
    }

    final bgAppId = _debouncedBgAppId ?? selected.appId;
    final bgApp = bgAppId == selected.appId
        ? selected
        : _findAppById(bgAppId) ?? selected;
    final key = ValueKey<int>(bgApp.appId);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _buildBackgroundChild(bgApp, key),
    );
  }

  NvApp? _findAppById(int appId) {
    final provider = context.read<AppListProvider>();
    for (final app in provider.apps) {
      if (app.appId == appId) return app;
    }
    return null;
  }

  Widget _buildBackgroundChild(NvApp selected, Key key) {
    final lp = context.read<LauncherPreferences>();
    if (selected.posterUrl == null || selected.posterUrl!.isEmpty) {
      return Container(
        key: key,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_tp.secondary, _tp.background, _tp.surface],
          ),
        ),
      );
    }

    final showVideo =
        _videoReady &&
        _videoForAppId == selected.appId &&
        _videoController != null &&
        _videoController!.value.isInitialized;

    return Stack(
      key: key,
      fit: StackFit.expand,
      children: [
        if (showVideo)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _videoController!.value.size.width,
              height: _videoController!.value.size.height,
              child: VideoPlayer(_videoController!),
            ),
          )
        else if (lp.enableParallaxDrift)
          AnimatedBuilder(
            animation: _backgroundMotionController,
            builder: (context, child) {
              return Transform.translate(
                offset: _backgroundDrift.value,
                child: Transform.scale(scale: _burnScale.value, child: child),
              );
            },
            child: PosterImage(
              url: selected.posterUrl!,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 200),
              memCacheWidth: 480,
              errorWidget: (_, _, _) => Container(color: _tp.background),
            ),
          )
        else
          PosterImage(
            url: selected.posterUrl!,
            fit: BoxFit.cover,
            key: const ValueKey('static-bg'),
            memCacheWidth: 480,
            errorWidget: (_, _, _) => Container(color: _tp.background),
          ),
        if (!(showVideo || context.read<ThemeProvider>().performanceMode))
          BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: lp.backgroundBlur,
              sigmaY: lp.backgroundBlur,
            ),
            child: Container(
              color: Colors.black.withValues(
                alpha: showVideo ? 0.0 : lp.backgroundDim,
              ),
            ),
          )
        else
          Container(
            color: Colors.black.withValues(
              alpha: showVideo ? 0.0 : lp.backgroundDim,
            ),
          ),
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.45, -0.35),
              radius: 1.2,
              colors: [Color(0x2200E5FF), Colors.transparent],
            ),
          ),
        ),
      ],
    );
  }

  void _handleAppTap(NvApp app) {
    _feedbackAction();
    final provider = context.read<AppListProvider>();
    final runningApp = provider.apps.cast<NvApp?>().firstWhere(
      (a) => a?.isRunning == true,
      orElse: () => null,
    );

    if (runningApp != null && !app.isRunning && runningApp.appId != app.appId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ya hay una sesión activa (${runningApp.appName}). Debes cerrarla antes de abrir otra app.',
          ),
          backgroundColor: Colors.orangeAccent.shade700,
        ),
      );
      return;
    }

    if (app.isRunning) {
      _showRunningSheet(app);
    } else {
      _showTvLaunchModal(app);
    }
  }

  void _showTvLaunchModal(NvApp app) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _tp.surface,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
          if (key == LogicalKeyboardKey.gameButtonX) {
            Navigator.pop(ctx);
            _launchApp(app);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.gameButtonY) {
            Navigator.pop(ctx);
            _openDetailsScreen(app);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: Text(
                  app.appName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.07)),
              const SizedBox(height: 4),
              _sheetOption(
                Icons.play_arrow_rounded,
                AppLocalizations.of(ctx).play,
                _tp.accent,
                () {
                  Navigator.pop(ctx);
                  _launchApp(app);
                },
                autofocus: true,
                trailing: _hintChip('X', ''),
              ),
              _sheetOption(
                Icons.info_outline_rounded,
                AppLocalizations.of(ctx).information,
                _tp.accentLight,
                () {
                  Navigator.pop(ctx);
                  _openDetailsScreen(app);
                },
                trailing: _hintChip('Y', ''),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showRunningSheet(NvApp app) {
    final isRunning = app.isRunning;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _tp.surface,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
          if (key == LogicalKeyboardKey.gameButtonX) {
            Navigator.pop(ctx);
            _launchApp(app);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.gameButtonY) {
            Navigator.pop(ctx);
            _openDetailsScreen(app);
            return KeyEventResult.handled;
          }
          if (isRunning && key == LogicalKeyboardKey.gameButtonRight1) {
            Navigator.pop(ctx);
            _confirmQuitApp(context.read<AppListProvider>());
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.appName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isRunning) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.greenAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              AppLocalizations.of(ctx).currentlyRunning,
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.07)),
                const SizedBox(height: 4),
                if (isRunning) ...[
                  _sheetOption(
                    Icons.play_arrow_rounded,
                    AppLocalizations.of(ctx).resumeSession,
                    _tp.accent,
                    () {
                      Navigator.pop(ctx);
                      _launchApp(app);
                    },
                    autofocus: true,
                    trailing: _hintChip('X', ''),
                  ),
                  _sheetOption(
                    Icons.stop_rounded,
                    AppLocalizations.of(ctx).quitSession,
                    Colors.redAccent,
                    () {
                      Navigator.pop(ctx);
                      _confirmQuitApp(context.read<AppListProvider>());
                    },
                    trailing: _hintChip('R1', ''),
                  ),
                ] else ...[
                  _sheetOption(
                    Icons.play_circle_filled,
                    AppLocalizations.of(ctx).launchGame,
                    _tp.accent,
                    () {
                      Navigator.pop(ctx);
                      _launchApp(app);
                    },
                    autofocus: true,
                    trailing: _hintChip('X', ''),
                  ),
                ],
                _sheetOption(
                  Icons.info_outline,
                  AppLocalizations.of(ctx).details,
                  Colors.white38,
                  () {
                    Navigator.pop(ctx);
                    _openDetailsScreen(app);
                  },
                  trailing: _hintChip('Y', ''),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetOption(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap, {
    bool autofocus = false,
    Widget? trailing,
  }) {
    return Focus(
      autofocus: autofocus,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.select) {
          _feedbackNavigate();
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final hasFocus = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: () {
              _feedbackNavigate();
              onTap();
            },
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              color: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 36,
                    height: 36,
                    decoration: hasFocus
                        ? BoxDecoration(
                            color: color.withValues(alpha: 0.22),
                            shape: BoxShape.circle,
                          )
                        : null,
                    alignment: Alignment.center,
                    child: Icon(
                      icon,
                      color: hasFocus ? color : color.withValues(alpha: 0.7),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openDetailsScreen(NvApp app) async {
    UiSoundService.playClick();

    _disposeVideoController();
    final baseConfig = context.read<SettingsProvider>().config;
    final profile =
        _profilesByAppId[app.appId] ??
        await _gamePreferencesStore.loadProfile(_hostId, app.appId);
    _profilesByAppId[app.appId] = profile;

    if (!mounted) return;
    final result = await Navigator.push<AppDetailsAction>(
      context,
      MaterialPageRoute(
        builder: (_) => AppDetailsScreen(
          app: app,
          heroTag: _heroTag(app),
          isFavorite: _favoriteAppIds.contains(app.appId),
          profile: profile,
          baseConfig: baseConfig,
          onToggleFavorite: () => _toggleFavorite(app),
          achievementProgress: _achievementCache[app.appId],
          onSaveProfile: (updated) async {
            await _gamePreferencesStore.saveProfile(_hostId, updated);
            if (!mounted) return;
            setState(() {
              _profilesByAppId[app.appId] = updated;
            });
          },
          onResetOverrides: () async {
            final updated = await _gamePreferencesStore.clearOverrides(
              _hostId,
              app.appId,
            );
            if (!mounted) return;
            setState(() {
              _profilesByAppId[app.appId] = updated;
            });
          },
          onAddToCollection: () => _showAddToCollectionSheet(app),
        ),
      ),
    );

    if (!mounted) return;
    _restoreScrollPosition();

    _scheduleVideoPreview(app);
    if (result == null) return;
    if (result == AppDetailsAction.play) {
      _launchApp(app);
    } else if (result == AppDetailsAction.options) {
      _showRunningSheet(app);
    }
  }

  String _heroTag(NvApp app) => 'app-poster-$_hostId-${app.appId}';

  void _launchApp(NvApp app) async {
    // before navigation to stream screen. This prevents poster downloads
    // from saturating the network during the RTSP handshake.
    ImageLoadThrottle.pauseForStream();

    unawaited(AchievementService.instance.unlock('first_launch'));

    final hour = DateTime.now().hour;
    if (hour >= 0 && hour < 5) {
      unawaited(AchievementService.instance.unlock('night_player'));
    }

    _isLaunching = true;
    _accentDebounce?.cancel();
    _bgDebounce?.cancel();
    _videoDelayTimer?.cancel();
    _disposeVideoController();
    final provider = context.read<AppListProvider>();
    final baseConfig = context.read<SettingsProvider>().config;
    final profile =
        _profilesByAppId[app.appId] ??
        await _gamePreferencesStore.loadProfile(_hostId, app.appId);
    if (!mounted) return;
    var effectiveConfig = profile.resolve(baseConfig);
    var startingOverlayVisible = false;

    if (effectiveConfig.smartBitrateEnabled) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: _tp.surface,
          content: Row(
            children: [
              CircularProgressIndicator(color: _tp.accent),
              const SizedBox(width: 20),
              Text(
                AppLocalizations.of(context).smartBitrateMeasuring,
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );

      final address = widget.computer.activeAddress.isNotEmpty
          ? widget.computer.activeAddress
          : widget.computer.localAddress;

      String? probeUrl = app.posterUrl;
      if (probeUrl == null || probeUrl.isEmpty) {
        for (final a in provider.apps) {
          if (a.posterUrl != null && a.posterUrl!.isNotEmpty) {
            probeUrl = a.posterUrl;
            break;
          }
        }
      }

      // codec-appropriate bits-per-pixel (AV1=0.065, H265=0.080, H264=0.115).
      final codecName = switch (effectiveConfig.videoCodec) {
        VideoCodec.av1 => 'AV1',
        VideoCodec.h265 => 'H265',
        VideoCodec.auto => 'H265',
        _ => 'H264',
      };
      final smartBitrate = await SmartBitrateService.instance
          .measureAndRecommend(
            host: address,
            httpsPort: widget.computer.httpsPort,
            minKbps: effectiveConfig.smartBitrateMin,
            maxKbps: effectiveConfig.smartBitrateMax,
            posterProbeUrl: probeUrl,
            width: effectiveConfig.width,
            height: effectiveConfig.height,
            fps: effectiveConfig.fps,
            enableHdr: effectiveConfig.enableHdr,
            videoCodec: codecName,
          );

      if (!mounted) return;
      Navigator.pop(context);

      effectiveConfig = effectiveConfig.copyWith(bitrate: smartBitrate);
      debugPrint('[SmartBitrate] Applied: ${smartBitrate ~/ 1000} Mbps');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).smartBitrateResult(smartBitrate ~/ 1000),
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF1A3D2F),
        ),
      );
    }

    startingOverlayVisible = true;
    unawaited(
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'launching',
        barrierColor: Colors.black.withValues(alpha: 0.72),
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, _, _) => _LaunchStartingOverlay(
          app: app,
          computerName: widget.computer.name,
          accent: _tp.accent,
          message: AppLocalizations.of(context).starting,
        ),
      ),
    );

    final launch = await provider.launchApp(app, streamConfig: effectiveConfig);

    if (!mounted) return;
    if (startingOverlayVisible) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (!launch.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppLocalizations.of(context).launchFailed}: ${launch.error}',
          ),
        ),
      );
      return;
    }

    final recordedProfile = await _gamePreferencesStore.recordLaunch(
      _hostId,
      app.appId,
    );
    _profilesByAppId[app.appId] = recordedProfile;

    // NOTE: provider.refresh() intentionally moved to AFTER the stream session ends.
    // Calling it before navigation caused 10-15s blocking delays (HTTPS + HTTP timeouts)
    // that expired the short-lived RTSP session URL before GameStreamScreen could use it.
    _disposeVideoController();
    _stopAutoRefreshTimer();

    await Navigator.push(
      context,

      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 1000),
        reverseTransitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, _, _) => GameStreamScreen(
          computer: widget.computer,
          app: app,
          riKey: launch.riKey,
          riKeyId: launch.riKeyId,
          rtspSessionUrl: launch.sessionUrl,
          overrideConfig: effectiveConfig,
        ),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
      ),
    );

    if (mounted) {
      _isLaunching = false;
      _startAutoRefreshTimer();
      // Restore focus so the gamepad can navigate the launcher immediately
      // after returning from the stream screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _screenFocusNode.requestFocus();
      });
      // Give Sunshine 2 seconds to cleanly close the RTSP session ports
      // before polling the HTTP API to prevent 'Connection refused' errors.
      await Future.delayed(const Duration(milliseconds: 2000));
      if (!mounted) return;
      // Refresh app list now that we've returned from the stream screen.
      context.read<AppListProvider>().loadApps(widget.computer);
      _restoreScrollPosition();
    }
  }

  void _showVibepolloCfgDialog() {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final provider = context.read<AppListProvider>();
    showDialog<void>(
      context: context,
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
        child: AlertDialog(
          backgroundColor: _tp.surface,
          title: Text(
            AppLocalizations.of(ctx).vibepolloConfigApi,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(ctx).vibepolloInstructions,
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: userCtrl,
                focusNode: FocusNode(skipTraversal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(ctx).username,
                  labelStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: _tp.accentLight),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passCtrl,
                obscureText: true,
                focusNode: FocusNode(skipTraversal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(ctx).password,
                  labelStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: _tp.accentLight),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(ctx).cancel),
            ),
            TextButton(
              onPressed: () async {
                final user = userCtrl.text.trim();
                final pass = passCtrl.text;
                Navigator.pop(ctx);
                if (user.isEmpty) return;
                await provider.saveCfgCredentials(
                  widget.computer.uuid,
                  user,
                  pass,
                );
                if (!mounted) return;
                await provider.refresh();
              },
              child: Text(
                AppLocalizations.of(ctx).save,
                style: TextStyle(color: _tp.accentLight),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmQuitApp(AppListProvider provider) {
    final l = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var selectedIndex = 0;

        Widget actionButton({
          required String label,
          required bool selected,
          required VoidCallback onTap,
          Color? selectedBorder,
          Color? selectedBackground,
          Color? textColor,
        }) {
          final borderColor = selectedBorder ?? _tp.accentLight;
          final bgColor =
              selectedBackground ?? Colors.white.withValues(alpha: 0.08);
          final fg = textColor ?? Colors.white;
          return Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? bgColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }

        return StatefulBuilder(
          builder: (ctx, setState) {
            void confirmSelection() async {
              if (selectedIndex == 0) {
                Navigator.pop(ctx);
                return;
              }
              Navigator.pop(ctx);
              await provider.quitApp();
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l.sessionClosed)));
              }
            }

            return Focus(
              autofocus: true,
              onKeyEvent: (_, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;

                if (key == LogicalKeyboardKey.arrowLeft ||
                    key == LogicalKeyboardKey.arrowUp) {
                  setState(() => selectedIndex = 0);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowRight ||
                    key == LogicalKeyboardKey.arrowDown) {
                  setState(() => selectedIndex = 1);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.enter ||
                    key == LogicalKeyboardKey.select ||
                    key == LogicalKeyboardKey.gameButtonA) {
                  confirmSelection();
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.gameButtonB ||
                    key == LogicalKeyboardKey.escape ||
                    key == LogicalKeyboardKey.goBack) {
                  Navigator.pop(ctx);
                  return KeyEventResult.handled;
                }

                return KeyEventResult.ignored;
              },
              child: AlertDialog(
                backgroundColor: _tp.surface,
                title: Text(
                  l.quitApp,
                  style: const TextStyle(color: Colors.white),
                ),
                content: Text(
                  l.quitAppConfirm,
                  style: const TextStyle(color: Colors.white70),
                ),
                actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                actions: [
                  Row(
                    children: [
                      actionButton(
                        label: l.cancel,
                        selected: selectedIndex == 0,
                        onTap: () {
                          setState(() => selectedIndex = 0);
                          Navigator.pop(ctx);
                        },
                      ),
                      const SizedBox(width: 10),
                      actionButton(
                        label: l.quit,
                        selected: selectedIndex == 1,
                        onTap: () {
                          setState(() => selectedIndex = 1);
                          confirmSelection();
                        },
                        selectedBorder: Colors.redAccent,
                        selectedBackground: Colors.redAccent.withValues(
                          alpha: 0.15,
                        ),
                        textColor: Colors.redAccent,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _AppViewScreenState extends _AppViewScreenBase
    with
        _AppViewCarouselMixin,
        _AppViewGridMixin,
        _AppViewFiltersMixin,
        _AppViewVideoPreviewMixin,
        _AppViewGamepadMixin,
        _AppViewDiscoveryMixin {}

class _LaunchStartingOverlay extends StatelessWidget {
  final NvApp app;
  final String computerName;
  final Color accent;
  final String message;

  const _LaunchStartingOverlay({
    required this.app,
    required this.computerName,
    required this.accent,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (app.posterUrl != null && app.posterUrl!.isNotEmpty)
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.68),
                BlendMode.darken,
              ),
              child: Image.network(
                app.posterUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: Color(0xFF0D0818)),
              ),
            )
          else
            const ColoredBox(color: Color(0xFF0D0818)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.appName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  computerName,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 24),
                Text(
                  message,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionFocusableTile extends StatelessWidget {
  final bool autofocus;
  final bool inCollection;
  final int colorValue;
  final String name;
  final int count;
  final VoidCallback onTap;

  const _CollectionFocusableTile({
    this.autofocus = false,
    required this.inCollection,
    required this.colorValue,
    required this.name,
    required this.count,
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
      child: Builder(
        builder: (ctx) {
          final hasFocus = Focus.of(ctx).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: hasFocus
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              dense: true,
              leading: Icon(
                inCollection
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: inCollection ? Color(colorValue) : Colors.white38,
              ),
              title: Text(
                name,
                style: TextStyle(
                  color: hasFocus ? Colors.white : Colors.white,
                  fontWeight: hasFocus ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              subtitle: Text(
                '$count juego${count == 1 ? '' : 's'}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              onTap: onTap,
            ),
          );
        },
      ),
    );
  }
}

class _FavoriteHeartOverlay extends StatefulWidget {
  final bool added;
  final Color accent;
  final VoidCallback onDone;

  const _FavoriteHeartOverlay({
    required this.added,
    required this.accent,
    required this.onDone,
  });

  @override
  State<_FavoriteHeartOverlay> createState() => _FavoriteHeartOverlayState();
}

class _FavoriteHeartOverlayState extends State<_FavoriteHeartOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.3), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 40),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _opacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
      ),
    );
    _ctrl.forward().then((_) {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) => Center(
            child: Opacity(
              opacity: _opacity.value,
              child: Transform.scale(
                scale: _scale.value,
                child: Icon(
                  widget.added ? Icons.favorite : Icons.favorite_border,
                  size: 80,
                  color: widget.added ? Colors.redAccent : Colors.white38,
                  shadows: const [
                    Shadow(blurRadius: 24, color: Colors.black54),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
