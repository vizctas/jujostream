import 'dart:io';
import 'dart:ui';

import '../../widgets/poster_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/nv_app.dart';
import '../../models/stream_configuration.dart';
import '../../providers/app_list_provider.dart';
import '../../providers/plugins_provider.dart';
import '../../providers/theme_provider.dart';
import '../../models/theme_config.dart';
import '../../services/metadata/steam_achievement_service.dart';
import '../../services/metadata/steam_library_service.dart';
import '../../services/metadata/steam_video_client.dart';
import '../../services/preferences/game_preferences_store.dart';
import '../../services/database/session_history_service.dart';
import '../../services/database/app_override_service.dart';
import '../../services/tv/tv_detector.dart';
import '../../services/input/gamepad_button_helper.dart';
import '../../widgets/trailer_modal.dart';

enum AppDetailsAction { play, options }

class AppDetailsScreen extends StatefulWidget {
  final NvApp app;
  final String heroTag;
  final bool isFavorite;
  final Future<void> Function() onToggleFavorite;
  final GamePreferencesProfile profile;
  final StreamConfiguration baseConfig;
  final Future<void> Function(GamePreferencesProfile profile) onSaveProfile;
  final Future<void> Function() onResetOverrides;
  final AchievementProgress? achievementProgress;
  final VoidCallback? onAddToCollection;

  const AppDetailsScreen({
    super.key,
    required this.app,
    required this.heroTag,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.profile,
    required this.baseConfig,
    required this.onSaveProfile,
    required this.onResetOverrides,
    this.achievementProgress,
    this.onAddToCollection,
  });

  @override
  State<AppDetailsScreen> createState() => _AppDetailsScreenState();
}

class _AppDetailsScreenState extends State<AppDetailsScreen> {
  AppThemeColors get _tp => context.read<ThemeProvider>().colors;

  late int _bitrate;
  late int _fps;
  late VideoCodec _codec;
  late bool _hdr;
  late bool _showGamepad;
  late bool _ultraLowLatency;
  late bool _perfOverlay;
  bool _saving = false;
  late bool _favorite;

  String? _overrideName;
  String? _overridePoster;

  String get _displayName => _overrideName ?? widget.app.appName;
  String? get _displayPoster => _overridePoster ?? widget.app.posterUrl;

  AchievementProgress? _liveAchievements;
  String? _steamPersona;
  bool _hasSteamApiKey = false;

  SteamGameStoreInfo? _storeInfo;
  SteamOwnedGame? _ownedGameInfo;
  bool _storeInfoLoading = false;

  List<SteamMovie> _steamMovies = const [];
  int? _resolvedSteamAppId;
  int _localPlaytimeSec = 0;

  AchievementProgress? get _achievements =>
      _liveAchievements ?? widget.achievementProgress;

  bool get _anySteamPluginEnabled {
    final p = context.read<PluginsProvider>();
    return p.isEnabled('steam_connect') ||
        p.isEnabled('steam_library_info') ||
        p.isEnabled('metadata');
  }

  @override
  void initState() {
    super.initState();
    final resolved = widget.profile.resolve(widget.baseConfig);
    _bitrate = resolved.bitrate;
    _fps = resolved.fps;
    _codec = resolved.videoCodec;
    _hdr = resolved.enableHdr;
    _showGamepad = resolved.showOnscreenControls;
    _ultraLowLatency = resolved.ultraLowLatency;
    _perfOverlay = resolved.enablePerfOverlay;
    _favorite = widget.isFavorite;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadSteamState();
      if (mounted) _loadPublicSteamData();
      if (mounted) _loadLocalPlaytime();
    });
  }

  Future<void> _loadSteamState() async {
    if (!mounted) return;
    final plugins = context.read<PluginsProvider>();
    if (!plugins.isEnabled('steam_connect')) return;
    final persona = await plugins.getSetting('steam_connect', 'steam_persona');
    final apiKey = await plugins.getApiKey('steam_connect');
    if (!mounted) return;
    setState(() {
      _steamPersona = persona;
      _hasSteamApiKey = apiKey != null && apiKey.isNotEmpty;
    });
    final steamAppId = await _resolveSteamAppId();
    if (steamAppId != null && apiKey != null && apiKey.isNotEmpty) {
      _fetchLiveAchievements(steamAppId);
      _fetchOwnedGameInfo(apiKey, steamAppId);
    }
  }

  Future<void> _loadPublicSteamData() async {
    if (!mounted) return;
    final plugins = context.read<PluginsProvider>();
    final wantStoreInfo =
        plugins.isEnabled('metadata') ||
        plugins.isEnabled('steam_library_info') ||
        plugins.isEnabled('steam_connect');
    final wantTrailers = plugins.isEnabled('game_video');
    if (!wantStoreInfo && !wantTrailers) return;
    final steamAppId = await _resolveSteamAppId();
    if (steamAppId == null) return;
    if (wantStoreInfo) _fetchSteamStoreInfo(steamAppId);
    if (wantTrailers) _fetchSteamTrailers(steamAppId);
  }

  Future<int?> _resolveSteamAppId() async {
    if (_resolvedSteamAppId != null) return _resolvedSteamAppId;
    final direct = widget.app.steamAppId;
    if (direct != null) {
      _resolvedSteamAppId = direct;
      return direct;
    }
    final lookedUp = await SteamVideoClient().searchAppId(widget.app.appName);
    if (mounted) {
      setState(() => _resolvedSteamAppId = lookedUp);
    } else {
      _resolvedSteamAppId = lookedUp;
    }
    return lookedUp;
  }

  Future<void> _fetchSteamStoreInfo(int appId) async {
    if (!mounted) return;
    setState(() => _storeInfoLoading = true);
    final info = await const SteamLibraryService().getStoreInfo(appId);
    if (mounted) {
      setState(() {
        _storeInfo = info;
        _storeInfoLoading = false;
      });
    }
  }

  Future<void> _fetchOwnedGameInfo(String apiKey, int appId) async {
    if (!mounted) return;
    final plugins = context.read<PluginsProvider>();
    final steamId = await plugins.getSetting('steam_connect', 'steam_id');
    if (steamId == null || steamId.isEmpty) return;
    final owned = await const SteamLibraryService().getOwnedGame(
      apiKey: apiKey,
      steamId: steamId,
      appId: appId,
    );
    if (mounted && owned != null) setState(() => _ownedGameInfo = owned);
  }

  Future<void> _fetchSteamTrailers(int appId) async {
    if (!mounted) return;
    final movies = await SteamVideoClient().getMovies(appId);
    if (mounted) setState(() => _steamMovies = movies);
  }

  Future<void> _loadLocalPlaytime() async {
    final sec = await SessionHistoryService.totalPlaytimeSec(widget.app.appId);
    if (mounted) setState(() => _localPlaytimeSec = sec);
  }

  Future<void> _fetchLiveAchievements(int steamAppId) async {
    if (!mounted) return;
    final plugins = context.read<PluginsProvider>();
    if (!plugins.canUseAchievementsOverlay) return;
    final apiKey = await plugins.getApiKey('steam_connect');
    final steamId = await plugins.getSetting('steam_connect', 'steam_id');
    if (apiKey == null ||
        apiKey.isEmpty ||
        steamId == null ||
        steamId.isEmpty) {
      return;
    }
    final progress = await const SteamAchievementService().fetchGameProgress(
      apiKey: apiKey,
      steamId: steamId,
      steamAppId: steamAppId,
    );
    if (mounted && progress != null) {
      setState(() => _liveAchievements = progress);
    }
  }

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.gameButtonB ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      Navigator.maybePop(context);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.gameButtonX) {
      HapticFeedback.mediumImpact();
      Navigator.pop(context, AppDetailsAction.play);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.gameButtonY) {
      if (widget.app.isRunning) {
        HapticFeedback.heavyImpact();
        _closeSession();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.gameButtonRight1) {
      HapticFeedback.mediumImpact();
      widget.onToggleFavorite().then((_) {
        if (mounted) setState(() => _favorite = !_favorite);
      });
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.gameButtonLeft1) {
      HapticFeedback.mediumImpact();
      _resetOverrides();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.gameButtonRight2) {
      HapticFeedback.heavyImpact();
      _saveOverrides();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.gameButtonLeft2) {
      HapticFeedback.mediumImpact();
      widget.onAddToCollection?.call();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (_scrollController.hasClients && _scrollController.offset < 100) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isTV = TvDetector.instance.isTV;
    return Focus(
      skipTraversal: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: const Color(0xFF09111C),
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildBackdrop(),
            SafeArea(
              child: FocusTraversalGroup(
                policy: WidgetOrderTraversalPolicy(),
                child: Column(
                  children: [
                    _buildTopBar(),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHero(),
                            const SizedBox(height: 18),
                            _buildQuickActions(),
                            if (context.watch<PluginsProvider>().isEnabled(
                              'game_video',
                            )) ...[
                              const SizedBox(height: 10),
                              _buildTrailerButton(),
                            ],
                            const SizedBox(height: 18),
                            _focusableCard(_buildSessionMeta()),
                            if (_anySteamPluginEnabled) ...[
                              const SizedBox(height: 18),
                              _focusableCard(_buildSteamCard()),
                            ],
                            const SizedBox(height: 18),
                            _buildPresetDeck(),
                            const SizedBox(height: 18),
                            _buildOverridesEditor(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (isTV)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(top: false, child: _buildDetailsHintsBar()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsHintsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _detailHint(
            'X',
            widget.app.isRunning
                ? AppLocalizations.of(context).resume
                : AppLocalizations.of(context).play,
          ),
          _detailHint('Y', AppLocalizations.of(context).closeSession),
          _detailHint('RB', AppLocalizations.of(context).favorite),
          _detailHint('LB', AppLocalizations.of(context).resetLabel),
          _detailHint('RT', AppLocalizations.of(context).save),
          _detailHint('LT', AppLocalizations.of(context).addToCollection),
          _detailHint('B', AppLocalizations.of(context).back),
        ],
      ),
    );
  }

  Widget _detailHint(String button, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GamepadHintIcon(button, size: 14),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _buildBackdrop() {
    if (widget.app.posterUrl == null || widget.app.posterUrl!.isEmpty) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B1624), Color(0xFF111827), Color(0xFF230B0B)],
          ),
        ),
      );
    }

    final perfMode = context.read<ThemeProvider>().performanceMode;
    return Stack(
      fit: StackFit.expand,
      children: [
        PosterImage(
          url: widget.app.posterUrl!,
          fit: BoxFit.cover,
          memCacheWidth: perfMode ? 720 : null,
        ),
        if (!perfMode)
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
            child: Container(color: Colors.black.withValues(alpha: 0.58)),
          ),
        if (perfMode) Container(color: Colors.black.withValues(alpha: 0.65)),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x88000000), Color(0xF009111C)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _saving ? null : _saveOverrides,
            icon: const Icon(Icons.save_outlined),
            label: Text(AppLocalizations.of(context).save),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Hero(
            tag: widget.heroTag,
            child: SizedBox(
              width: 140,
              height: 188,
              child:
                  widget.app.posterUrl == null || widget.app.posterUrl!.isEmpty
                  ? Container(
                      color: _tp.secondary,
                      child: const Icon(
                        Icons.gamepad,
                        color: Colors.white24,
                        size: 48,
                      ),
                    )
                  : PosterImage(
                      url: _displayPoster ?? widget.app.posterUrl!,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),

              Row(
                children: [
                  _miniEditBtn(
                    Icons.edit_outlined,
                    AppLocalizations.of(context).editName,
                    () => _showEditNameDialog(),
                  ),
                  const SizedBox(width: 6),
                  _miniEditBtn(
                    Icons.image_outlined,
                    AppLocalizations.of(context).editPoster,
                    () => _showEditPosterDialog(),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              _chip(
                widget.app.isRunning
                    ? AppLocalizations.of(context).running.toUpperCase()
                    : AppLocalizations.of(context).readyStatus.toUpperCase(),
                widget.app.isRunning ? Colors.greenAccent : Colors.white70,
                tier: 1,
              ),
              const SizedBox(height: 10),

              if (widget.app.tags.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: widget.app.tags
                      .take(5)
                      .map(
                        (t) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            t,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 10),
              ],

              if (widget.app.description != null &&
                  widget.app.description!.isNotEmpty)
                Text(
                  widget.app.description!,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    height: 1.5,
                    fontSize: 13,
                  ),
                )
              else
                Text(
                  AppLocalizations.of(context).noDescription,
                  style: const TextStyle(
                    color: Colors.white38,
                    height: 1.4,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),

              if (_favorite ||
                  widget.app.isHdrSupported ||
                  (widget.app.pluginName != null &&
                      widget.app.pluginName!.isNotEmpty)) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (_favorite)
                      _chip(
                        AppLocalizations.of(context).favorite.toUpperCase(),
                        Colors.amberAccent,
                        tier: 2,
                      ),
                    if (widget.app.isHdrSupported)
                      _chip(
                        AppLocalizations.of(context).hdrLabel,
                        Colors.cyanAccent,
                        tier: 3,
                      ),
                    if (widget.app.pluginName != null &&
                        widget.app.pluginName!.isNotEmpty)
                      _chip(widget.app.pluginName!, Colors.white38, tier: 3),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniEditBtn(IconData icon, String label, VoidCallback onTap) {
    return Focus(
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
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: hasFocus
                    ? _tp.accent.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: hasFocus
                    ? Border.all(color: _tp.accent.withValues(alpha: 0.6))
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 11,
                    color: hasFocus ? _tp.accentLight : Colors.white38,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: hasFocus ? Colors.white70 : Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      decoration: hasFocus ? null : TextDecoration.underline,
                      decorationColor: Colors.white24,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEditNameDialog() {
    final controller = TextEditingController(text: widget.app.appName);
    final l = AppLocalizations.of(context);
    showDialog(
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
          title: Text(l.editName, style: const TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: l.customNameHint,
              hintStyle: const TextStyle(color: Colors.white38),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _tp.accent),
              ),
            ),
            onSubmitted: (v) {
              Navigator.pop(ctx, v.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(l.save, style: TextStyle(color: _tp.accentLight)),
            ),
          ],
        ),
      ),
    ).then((value) async {
      if (value == null || !mounted) return;
      final name = value as String;
      if (name.isEmpty || name == widget.app.appName) return;
      final serverId = widget.app.serverUuid ?? 'default';
      await AppOverrideService.instance.setCustomName(
        serverId,
        widget.app.appId,
        name,
      );
      if (mounted) {
        setState(() => _overrideName = name);
        context.read<AppListProvider>().reapplyUserOverrides();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.overrideApplied)));
      }
    });
  }

  void _showEditPosterDialog() {
    final controller = TextEditingController(text: widget.app.posterUrl ?? '');
    final l = AppLocalizations.of(context);
    showDialog(
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
            l.editPoster,
            style: const TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: l.posterUrlHint,
                  hintStyle: const TextStyle(color: Colors.white38),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: _tp.accent),
                  ),
                ),
                onSubmitted: (v) {
                  Navigator.pop(ctx, v.trim());
                },
              ),
              const SizedBox(height: 16),

              Focus(
                onKeyEvent: (_, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (key == LogicalKeyboardKey.gameButtonA ||
                      key == LogicalKeyboardKey.enter ||
                      key == LogicalKeyboardKey.select) {
                    Navigator.pop(ctx, '__pick_local__');
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (focusCtx) {
                    final hasFocus = Focus.of(focusCtx).hasFocus;
                    return GestureDetector(
                      onTap: () => Navigator.pop(ctx, '__pick_local__'),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: hasFocus
                              ? _tp.accent.withValues(alpha: 0.20)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: hasFocus ? _tp.accent : Colors.white24,
                            width: hasFocus ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.photo_library_outlined,
                              color: hasFocus
                                  ? _tp.accentLight
                                  : Colors.white54,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppLocalizations.of(context).pickLocalImage,
                              style: TextStyle(
                                color: hasFocus ? Colors.white : Colors.white70,
                                fontWeight: hasFocus
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(l.save, style: TextStyle(color: _tp.accentLight)),
            ),
          ],
        ),
      ),
    ).then((value) async {
      if (value == null || !mounted) return;
      final result = value as String;

      if (result == '__pick_local__') {
        await _pickLocalPosterImage();
        return;
      }

      if (result.isEmpty) return;
      final serverId = widget.app.serverUuid ?? 'default';
      await AppOverrideService.instance.setCustomPosterUrl(
        serverId,
        widget.app.appId,
        result,
      );
      if (mounted) {
        setState(() => _overridePoster = result);
        context.read<AppListProvider>().reapplyUserOverrides();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.overrideApplied)));
      }
    });
  }

  Future<void> _pickLocalPosterImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      final appDir = await getApplicationDocumentsDirectory();
      final posterDir = Directory(p.join(appDir.path, 'custom_posters'));
      if (!posterDir.existsSync()) posterDir.createSync(recursive: true);

      final ext = p.extension(picked.path).isNotEmpty
          ? p.extension(picked.path)
          : '.jpg';
      final destPath = p.join(posterDir.path, '${widget.app.appId}$ext');
      await File(picked.path).copy(destPath);

      final fileUri = 'file://$destPath';
      final serverId = widget.app.serverUuid ?? 'default';
      await AppOverrideService.instance.setCustomPosterUrl(
        serverId,
        widget.app.appId,
        fileUri,
      );

      if (mounted) {
        setState(() => _overridePoster = fileUri);
        context.read<AppListProvider>().reapplyUserOverrides();
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.overrideApplied)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Widget _chip(String label, Color color, {int tier = 1}) {
    switch (tier) {
      case 2:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
              fontSize: 10,
              letterSpacing: 0.2,
            ),
          ),
        );
      case 3:
        return Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.55),
            fontWeight: FontWeight.w500,
            fontSize: 10,
            letterSpacing: 0.1,
          ),
        );
      default:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 0.2,
            ),
          ),
        );
    }
  }

  Widget _buildQuickActions() {
    final l = AppLocalizations.of(context);
    final isTV = TvDetector.instance.isTV;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FocusableActionBtn(
          icon: Icons.play_arrow_rounded,
          label: widget.app.isRunning ? l.resume : l.play,
          gamepadHint: 'X',
          backgroundColor: _tp.accent.withValues(alpha: 0.85),
          borderColor: _tp.accent,
          isPrimary: true,
          isTV: isTV,
          autofocus: true,
          onTap: () => Navigator.pop(context, AppDetailsAction.play),
        ),
        const SizedBox(height: 8),

        Row(
          children: [
            _compactBtn(
              Icons.power_settings_new,
              AppLocalizations.of(context).closeSession,
              widget.app.isRunning ? Colors.redAccent : null,
              widget.app.isRunning ? () async {
                final provider = context.read<AppListProvider>();
                await provider.quitApp();
                if (mounted) Navigator.pop(context);
              } : null, // If false, onTap is null (disabled)
              gamepadHint: 'Y',
            ),
            _compactBtn(
              _favorite ? Icons.star : Icons.star_outline,
              _favorite ? l.unfav : l.fav,
              _tp.accentLight,
              () async {
                await widget.onToggleFavorite();
                if (!mounted) return;
                setState(() => _favorite = !_favorite);
              },
              gamepadHint: 'RB',
            ),
            _compactBtn(
              Icons.restart_alt,
              l.resetLabel,
              _tp.accentLight,
              _resetOverrides,
              gamepadHint: 'LB',
            ),
          ],
        ),
      ],
    );
  }

  Widget _compactBtn(
    IconData icon,
    String label,
    Color? accent,
    VoidCallback? onTap, {
    String? gamepadHint,
    bool autofocus = false,
  }) {
    final surfaceBase = _tp.surfaceVariant.withValues(alpha: 0.92);
    final bg = accent != null
        ? Color.alphaBlend(accent.withValues(alpha: 0.16), surfaceBase)
        : surfaceBase;
    final border = Colors.transparent;
    final isTV = TvDetector.instance.isTV;
    return Expanded(
      child: _FocusableActionBtn(
        icon: icon,
        label: label,
        gamepadHint: gamepadHint,
        backgroundColor: bg,
        borderColor: border,
        isPrimary: false,
        isTV: isTV,
        autofocus: autofocus,
        onTap: onTap,
      ),
    );
  }

  Widget _buildSessionMeta() {
    final lastSession = _formatLastSession(widget.profile.lastSessionAt);
    final launchCount = '${widget.profile.launchCount}';
    final l = AppLocalizations.of(context);
    final overridesLabel = widget.profile.hasOverrides
        ? l.customProfile
        : l.globalOnly;

    final tiles = <Widget>[];
    void addTile(String lbl, String val) {
      if (tiles.isNotEmpty) {
        tiles.add(const Divider(height: 1, color: Colors.white10));
      }
      tiles.add(_metaTile(lbl, val));
    }

    addTile(l.lastSessionLabel, lastSession);
    addTile(l.launchCountLabel, launchCount);
    addTile(l.overridesLabelMeta, overridesLabel);
    if (_localPlaytimeSec > 0) {
      addTile(
        'Tiempo en JUJO',
        SessionHistoryService.formatDuration(_localPlaytimeSec),
      );
    }

    return _card(
      title: l.sessionMetadata,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: tiles,
      ),
    );
  }

  Widget _buildSteamCard() {
    final app = widget.app;
    final prog = _achievements;

    final playtime = _ownedGameInfo?.playtimeMinutes ?? app.playtimeMinutes;
    final store = _storeInfo;

    const hasTrailer = true;

    String formatPlaytime(int minutes) {
      if (minutes < 60) return '$minutes min';
      final h = minutes ~/ 60;
      final m = minutes % 60;
      return m == 0 ? '${h}h' : '${h}h ${m}min';
    }

    String formatLastPlayed(String? dt) {
      final sl = AppLocalizations.of(context);
      if (dt == null || dt.isEmpty) return sl.never;
      final parsed = DateTime.tryParse(dt);
      if (parsed == null) return dt;
      final diff = DateTime.now().difference(parsed);
      if (diff.inDays == 0) return sl.todayLabel;
      if (diff.inDays == 1) return sl.yesterdayLabel;
      if (diff.inDays < 30) return sl.daysAgo(diff.inDays);
      if (diff.inDays < 365) return sl.monthsAgo(diff.inDays ~/ 30);
      return sl.yearsAgo(diff.inDays ~/ 365);
    }

    return _card(
      title: AppLocalizations.of(context).gameInformation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_steamPersona != null && _steamPersona!.isNotEmpty) ...[
            Row(
              children: [
                Image.asset(
                  'assets/images/UI/steam/steam_icon.png',
                  width: 16,
                  height: 16,
                  color: Colors.white38,
                ),
                const SizedBox(width: 8),
                Text(
                  '${AppLocalizations.of(context).accountLabel}: $_steamPersona',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          if (playtime > 0)
            _metaTile(
              AppLocalizations.of(context).timePlayed,
              formatPlaytime(playtime),
            ),
          if (playtime > 0 &&
              _ownedGameInfo?.playtimeRecentMinutes != null &&
              _ownedGameInfo!.playtimeRecentMinutes > 0) ...[
            const Divider(height: 1, color: Colors.white10),
            _metaTile(
              AppLocalizations.of(context).last2Weeks,
              formatPlaytime(_ownedGameInfo!.playtimeRecentMinutes),
            ),
          ],
          if (playtime > 0 && app.lastPlayed != null)
            const Divider(height: 1, color: Colors.white10),
          if (app.lastPlayed != null)
            _metaTile(
              AppLocalizations.of(context).lastSessionLabel,
              formatLastPlayed(app.lastPlayed),
            ),

          if (store != null) ...[
            if (store.reviewDescription != null &&
                store.reviewDescription!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildReviewTile(store),
            ],
            if (store.genres.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildGenreChips(store.genres),
            ],
            if (store.releaseDate != null && store.releaseDate!.isNotEmpty) ...[
              const Divider(height: 1, color: Colors.white10),
              _metaTile(
                AppLocalizations.of(context).releaseDate,
                store.releaseDate!,
              ),
            ],
            if (store.developers.isNotEmpty) ...[
              const Divider(height: 1, color: Colors.white10),
              _metaTile(
                AppLocalizations.of(context).developerLabel,
                store.developers.join(', '),
              ),
            ],
            if (store.metacriticScore != null) ...[
              const Divider(height: 1, color: Colors.white10),
              _metaTile(
                AppLocalizations.of(context).metacriticLabel,
                '${store.metacriticScore}',
              ),
            ],
          ],
          if (_storeInfoLoading) ...[
            const SizedBox(height: 12),
            const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white24,
                ),
              ),
            ),
          ],

          if (!_hasSteamApiKey &&
              playtime == 0 &&
              prog == null &&
              store == null) ...[
            if (_steamPersona != null) const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 14, color: Colors.white30),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).steamApiKeyHint,
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (prog != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppLocalizations.of(
                    context,
                  ).achievementsProgress(prog.unlocked, prog.total),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  '${prog.percent.round()}%',
                  style: TextStyle(
                    color: prog.isComplete
                        ? Colors.amber
                        : prog.inProgress
                        ? Colors.cyanAccent
                        : Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: prog.percent / 100,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(
                  prog.isComplete
                      ? Colors.amber
                      : prog.inProgress
                      ? Colors.cyanAccent
                      : Colors.white24,
                ),
                minHeight: 6,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewTile(SteamGameStoreInfo store) {
    final desc = store.reviewDescription ?? '';
    final pct = store.positivePercent;
    final total = store.totalReviews ?? 0;
    final Color color;
    if (pct != null && pct >= 0.80) {
      color = Colors.greenAccent;
    } else if (pct != null && pct >= 0.50) {
      color = Colors.amberAccent;
    } else {
      color = Colors.redAccent;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(Icons.thumb_up_outlined, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              desc,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (pct != null)
            Text(
              '${(pct * 100).round()}%',
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          if (total > 0) ...[
            const SizedBox(width: 6),
            Text(
              '(${_compactNumber(total)})',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGenreChips(List<String> genres) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: genres
          .take(6)
          .map(
            (g) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _tp.accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _tp.accent.withValues(alpha: 0.4)),
              ),
              child: Text(
                g,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildTrailerButton() {
    return _FocusableTrailerButton(
      label: AppLocalizations.of(context).watchTrailer,
      onPressed: _openTrailerModal,
    );
  }

  void _openTrailerModal() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: TrailerModal(
            gameName: widget.app.appName,
            steamMovies: _steamMovies,
            preferredSource: _steamMovies.isNotEmpty
                ? TrailerSource.steam
                : TrailerSource.youtube,
          ),
        ),
      ),
    );
  }

  String _compactNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  Widget _buildPresetDeck() {
    final l = AppLocalizations.of(context);
    return _card(
      title: l.quickPresets,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.presetExplain,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 14),
          _presetButton(
            preset: _GamePreset.balanced,
            title: l.balanced,
            subtitle: l.balancedSub,
            onTap: () => _applyPreset(_GamePreset.balanced),
            featured: true,
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final splitColumns = constraints.maxWidth >= 520;
              final competitive = _presetButton(
                preset: _GamePreset.competitive,
                title: l.competitive,
                subtitle: l.competitiveSub,
                onTap: () => _applyPreset(_GamePreset.competitive),
              );
              final visualQuality = _presetButton(
                preset: _GamePreset.visualQuality,
                title: l.visualQuality,
                subtitle: l.visualQualitySub,
                onTap: () => _applyPreset(_GamePreset.visualQuality),
              );

              if (!splitColumns) {
                return Column(
                  children: [
                    competitive,
                    const SizedBox(height: 10),
                    visualQuality,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: competitive),
                  const SizedBox(width: 10),
                  Expanded(child: visualQuality),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          _presetButton(
            preset: _GamePreset.handheld,
            title: l.handheld,
            subtitle: l.handheldSub,
            onTap: () => _applyPreset(_GamePreset.handheld),
          ),
        ],
      ),
    );
  }

  Widget _presetButton({
    required _GamePreset preset,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool featured = false,
  }) {
    return Focus(
      onFocusChange: (f) {
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final hasFocus = Focus.of(ctx).hasFocus;
          final tone = _presetTone(preset);
          final base = Color.alphaBlend(
            tone.withValues(alpha: featured ? 0.16 : 0.10),
            _tp.surfaceVariant.withValues(alpha: 0.94),
          );
          final badges = _presetBadges(preset);
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: double.infinity,
              padding: EdgeInsets.all(featured ? 16 : 14),
              transform: Matrix4.translationValues(0, hasFocus ? -2 : 0, 0),
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(featured ? 18 : 16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: hasFocus ? 0.24 : 0.12,
                    ),
                    blurRadius: hasFocus ? 20 : 10,
                    offset: Offset(0, hasFocus ? 10 : 4),
                  ),
                  BoxShadow(
                    color: tone.withValues(
                      alpha: hasFocus
                          ? (featured ? 0.18 : 0.10)
                          : (featured ? 0.10 : 0.04),
                    ),
                    blurRadius: hasFocus ? (featured ? 18 : 10) : 8,
                    offset: Offset(0, hasFocus ? 4 : 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: featured ? 40 : 34,
                        height: featured ? 40 : 34,
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: hasFocus ? 0.22 : 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          _presetIcon(preset),
                          color: Colors.white,
                          size: featured ? 20 : 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: featured ? 15 : 14,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.70),
                                height: 1.35,
                                fontSize: featured ? 12.5 : 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: hasFocus ? Colors.white : Colors.white38,
                        size: featured ? 20 : 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final badge in badges)
                        _presetBadge(
                          label: badge,
                          tone: tone,
                          focused: hasFocus,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _presetIcon(_GamePreset preset) {
    switch (preset) {
      case _GamePreset.competitive:
        return Icons.bolt_rounded;
      case _GamePreset.balanced:
        return Icons.tune_rounded;
      case _GamePreset.visualQuality:
        return Icons.movie_filter_rounded;
      case _GamePreset.handheld:
        return Icons.phone_android_rounded;
    }
  }

  Color _presetTone(_GamePreset preset) {
    switch (preset) {
      case _GamePreset.competitive:
        return _tp.secondary;
      case _GamePreset.balanced:
        return _tp.accent;
      case _GamePreset.visualQuality:
        return _tp.warm;
      case _GamePreset.handheld:
        return _tp.muted;
    }
  }

  List<String> _presetBadges(_GamePreset preset) {
    switch (preset) {
      case _GamePreset.competitive:
        return const ['18 Mbps', '120 FPS', 'H.264'];
      case _GamePreset.balanced:
        return const ['30 Mbps', '60 FPS', 'HEVC'];
      case _GamePreset.visualQuality:
        return const ['50 Mbps', '60 FPS', 'HEVC'];
      case _GamePreset.handheld:
        return const ['12 Mbps', '60 FPS', 'H.264'];
    }
  }

  Widget _presetBadge({
    required String label,
    required Color tone,
    required bool focused,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          tone.withValues(alpha: focused ? 0.16 : 0.10),
          _tp.surface.withValues(alpha: 0.84),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: focused ? 0.92 : 0.72),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  Widget _metaTile(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const Spacer(),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverridesEditor() {
    return _card(
      title: AppLocalizations.of(context).perGameStreamProfile,
      child: Theme(
        data: Theme.of(context).copyWith(
          listTileTheme: ListTileThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        child: Column(
          children: [
            _FocusableSliderRow(
              title: AppLocalizations.of(context).bitrate,
              valueLabel: '${_bitrate ~/ 1000} Mbps',
              value: _bitrate.toDouble(),
              min: 1000,
              max: 80000,
              divisions: 79,
              autofocus: true,
              onChanged: (v) => setState(() => _bitrate = v.round()),
            ),
            _FocusableChoiceRow(
              title: AppLocalizations.of(context).fpsLabel,
              value: '$_fps FPS',
              onTap: () => _pickFps(),
            ),
            _FocusableChoiceRow(
              title: AppLocalizations.of(context).videoCodec,
              value: _codecLabel(_codec),
              onTap: () => _pickCodec(),
            ),
            _FocusableSwitchRow(
              title: AppLocalizations.of(context).forceHdr,
              value: _hdr,
              onChanged: (v) => setState(() => _hdr = v),
            ),
            _FocusableSwitchRow(
              title: AppLocalizations.of(context).showOnScreenControls,
              value: _showGamepad,
              onChanged: (v) => setState(() => _showGamepad = v),
            ),
            _FocusableSwitchRow(
              title: AppLocalizations.of(context).ultraLowLatency,
              value: _ultraLowLatency,
              onChanged: (v) => setState(() => _ultraLowLatency = v),
            ),
            _FocusableSwitchRow(
              title: AppLocalizations.of(context).performanceOverlayLabel,
              value: _perfOverlay,
              onChanged: (v) => setState(() => _perfOverlay = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _focusableCard(Widget card) {
    return _FocusableCardWrapper(child: card);
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _tp.surface.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Future<T?> _showDialogPicker<T>({
    required String title,
    required List<(String label, T value)> options,
  }) {
    final size = MediaQuery.sizeOf(context);
    final dialogWidth = size.width > 600 ? 360.0 : size.width - 48;

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 230),
      transitionBuilder: (dCtx, anim, _, child) {
        final scale = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.90, end: 1).animate(scale),
          child: FadeTransition(opacity: fade, child: child),
        );
      },
      pageBuilder: (dCtx, _, _) => Focus(
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.gameButtonB ||
              key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            Navigator.pop(dCtx);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: dialogWidth,
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              constraints: BoxConstraints(maxHeight: size.height * 0.75),
              decoration: BoxDecoration(
                color: _tp.surface,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: FocusTraversalGroup(
                  policy: WidgetOrderTraversalPolicy(),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 18),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        for (final (index, option) in options.indexed)
                          _FocusablePickerRow(
                            label: option.$1,
                            autofocus: index == 0,
                            onTap: () => Navigator.pop(dCtx, option.$2),
                          ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickFps() async {
    final fps = await _showDialogPicker<int>(
      title: AppLocalizations.of(context).frameRate,
      options: [
        ('30 FPS', 30),
        ('60 FPS', 60),
        ('90 FPS', 90),
        ('120 FPS', 120),
      ],
    );
    if (fps != null) setState(() => _fps = fps);
  }

  Future<void> _pickCodec() async {
    final codec = await _showDialogPicker<VideoCodec>(
      title: AppLocalizations.of(context).videoCodec,
      options: VideoCodec.values
          .map((value) => (_codecLabel(value), value))
          .toList(),
    );
    if (codec != null) setState(() => _codec = codec);
  }

  Future<void> _saveOverrides() async {
    setState(() => _saving = true);
    final updated = widget.profile.copyWith(
      bitrate: _bitrate,
      fps: _fps,
      videoCodec: _codec,
      enableHdr: _hdr,
      showOnscreenControls: _showGamepad,
      ultraLowLatency: _ultraLowLatency,
      enablePerfOverlay: _perfOverlay,
    );
    await widget.onSaveProfile(updated);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).profileSaved)),
    );
  }

  Future<void> _closeSession() async {
    if (!widget.app.isRunning) return;
    final provider = context.read<AppListProvider>();
    await provider.quitApp();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _resetOverrides() async {
    await widget.onResetOverrides();
    if (!mounted) return;
    final base = widget.baseConfig;
    setState(() {
      _bitrate = base.bitrate;
      _fps = base.fps;
      _codec = base.videoCodec;
      _hdr = base.enableHdr;
      _showGamepad = base.showOnscreenControls;
      _ultraLowLatency = base.ultraLowLatency;
      _perfOverlay = base.enablePerfOverlay;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).overridesReset)),
    );
  }

  void _applyPreset(_GamePreset preset) {
    switch (preset) {
      case _GamePreset.competitive:
        setState(() {
          _bitrate = 18000;
          _fps = 120;
          _codec = VideoCodec.h264;
          _hdr = false;
          _showGamepad = false;
          _ultraLowLatency = true;
          _perfOverlay = true;
        });
      case _GamePreset.balanced:
        setState(() {
          _bitrate = 30000;
          _fps = 60;
          _codec = VideoCodec.h265;
          _hdr = widget.app.isHdrSupported && widget.baseConfig.enableHdr;
          _showGamepad = widget.baseConfig.showOnscreenControls;
          _ultraLowLatency = true;
          _perfOverlay = false;
        });
      case _GamePreset.visualQuality:
        setState(() {
          _bitrate = 50000;
          _fps = 60;
          _codec = VideoCodec.h265;
          _hdr = widget.app.isHdrSupported;
          _showGamepad = false;
          _ultraLowLatency = false;
          _perfOverlay = false;
        });
      case _GamePreset.handheld:
        setState(() {
          _bitrate = 12000;
          _fps = 60;
          _codec = VideoCodec.h264;
          _hdr = false;
          _showGamepad = true;
          _ultraLowLatency = true;
          _perfOverlay = false;
        });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context).presetApplied(_presetLabel(preset)),
        ),
      ),
    );
  }

  String _presetLabel(_GamePreset preset) {
    switch (preset) {
      case _GamePreset.competitive:
        return AppLocalizations.of(context).competitive;
      case _GamePreset.balanced:
        return AppLocalizations.of(context).balanced;
      case _GamePreset.visualQuality:
        return AppLocalizations.of(context).visualQuality;
      case _GamePreset.handheld:
        return AppLocalizations.of(context).handheld;
    }
  }

  String _codecLabel(VideoCodec codec) {
    switch (codec) {
      case VideoCodec.h265:
        return 'H.265 / HEVC';
      case VideoCodec.av1:
        return 'AV1';
      case VideoCodec.h264:
        return 'H.264';
      case VideoCodec.auto:
        return 'Auto';
    }
  }

  String _formatLastSession(DateTime? time) {
    final fl = AppLocalizations.of(context);
    if (time == null) return fl.never;
    final delta = DateTime.now().difference(time);
    if (delta.inMinutes < 1) return fl.justNow;
    if (delta.inHours < 1) return fl.minutesAgo(delta.inMinutes);
    if (delta.inDays < 1) return fl.hoursAgo(delta.inHours);
    return fl.daysAgoShort(delta.inDays);
  }
}

enum _GamePreset { competitive, balanced, visualQuality, handheld }

class _FocusableActionBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? gamepadHint;
  final Color backgroundColor;
  final Color borderColor;
  final bool isPrimary;
  final bool isTV;
  final bool autofocus;
  final VoidCallback? onTap;

  const _FocusableActionBtn({
    required this.icon,
    required this.label,
    this.gamepadHint,
    required this.backgroundColor,
    required this.borderColor,
    required this.isPrimary,
    required this.isTV,
    this.autofocus = false,
    required this.onTap,
  });

  @override
  State<_FocusableActionBtn> createState() => _FocusableActionBtnState();
}

class _FocusableActionBtnState extends State<_FocusableActionBtn> {
  AppThemeColors get _tp => context.read<ThemeProvider>().colors;

  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final targetScale = _pressed ? 0.97 : 1.0;
    final iconColor = _focused
        ? Colors.white
        : widget.isPrimary
        ? Colors.white70
        : Colors.white54;
    final labelColor = _focused
        ? Colors.white
        : widget.isPrimary
        ? Colors.white
        : Colors.white70;
    final shadowTint = Color.alphaBlend(
      _tp.background.withValues(alpha: widget.isPrimary ? 0.12 : 0.22),
      widget.backgroundColor,
    );
    final gradientTop = Color.alphaBlend(
      Colors.white.withValues(alpha: widget.isPrimary ? 0.10 : 0.06),
      widget.backgroundColor,
    );
    final gradientBottom = Color.alphaBlend(
      _tp.background.withValues(alpha: widget.isPrimary ? 0.12 : 0.18),
      widget.backgroundColor,
    );
    final outlineColor = Color.alphaBlend(
      widget.borderColor.withValues(alpha: _focused ? 0.68 : 0.42),
      widget.backgroundColor,
    );
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (_, event) {
        if (widget.onTap == null) return KeyEventResult.ignored;
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          widget.onTap!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: widget.onTap != null ? (_) => setState(() => _pressed = true) : null,
        onTapUp: widget.onTap != null ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: widget.onTap != null ? () => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          scale: targetScale,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: EdgeInsets.symmetric(vertical: widget.isTV ? 14 : 10),
            transform: Matrix4.translationValues(0, _focused ? -2 : 0, 0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [gradientTop, gradientBottom],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: outlineColor,
                width: _focused ? 1.4 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _focused ? 0.24 : 0.14),
                  blurRadius: _focused ? 20 : 10,
                  offset: Offset(0, _focused ? 10 : 4),
                ),
                BoxShadow(
                  color: shadowTint.withValues(
                    alpha: _focused
                        ? (widget.isPrimary ? 0.26 : 0.12)
                        : (widget.isPrimary ? 0.12 : 0.05),
                  ),
                  blurRadius: _focused
                      ? (widget.isPrimary ? 22 : 12)
                      : (widget.isPrimary ? 12 : 8),
                  offset: Offset(0, _focused ? 5 : 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    widget.icon,
                    color: iconColor,
                    size: widget.isTV ? 26 : 20,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: widget.isTV ? 13 : 10,
                    fontWeight: widget.isPrimary
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
                if (widget.gamepadHint != null) ...[
                  const SizedBox(height: 2),
                  GamepadHintIcon(widget.gamepadHint!, size: 22),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusableChoiceRow extends StatefulWidget {
  final String title;
  final String value;
  final VoidCallback onTap;

  const _FocusableChoiceRow({
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  State<_FocusableChoiceRow> createState() => _FocusableChoiceRowState();
}

class _FocusableChoiceRowState extends State<_FocusableChoiceRow> {
  AppThemeColors get _tp => context.read<ThemeProvider>().colors;

  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _focused
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            widget.title,
            style: const TextStyle(color: Colors.white),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 72, maxWidth: 140),
                child: Text(
                  widget.value,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: _focused ? Colors.white : Colors.white54,
              ),
            ],
          ),
          onTap: widget.onTap,
        ),
      ),
    );
  }
}

class _FocusableSwitchRow extends StatefulWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FocusableSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_FocusableSwitchRow> createState() => _FocusableSwitchRowState();
}

class _FocusableSwitchRowState extends State<_FocusableSwitchRow> {
  AppThemeColors get _tp => context.read<ThemeProvider>().colors;

  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          widget.onChanged(!widget.value);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _focused
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.trailing,
          title: Text(
            widget.title,
            style: const TextStyle(color: Colors.white),
          ),
          value: widget.value,
          activeThumbColor: _tp.accentLight,
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}

class _FocusableCardWrapper extends StatefulWidget {
  final Widget child;
  const _FocusableCardWrapper({required this.child});

  @override
  State<_FocusableCardWrapper> createState() => _FocusableCardWrapperState();
}

class _FocusableCardWrapperState extends State<_FocusableCardWrapper> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.4,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _focused
                ? Colors.white.withValues(alpha: 0.45)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

class _FocusableTrailerButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _FocusableTrailerButton({required this.label, required this.onPressed});

  @override
  State<_FocusableTrailerButton> createState() =>
      _FocusableTrailerButtonState();
}

class _FocusableTrailerButtonState extends State<_FocusableTrailerButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: widget.onPressed,
          icon: const Icon(Icons.movie_outlined, size: 18),
          label: Text(widget.label),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.cyanAccent,
            side: BorderSide(
              color: _focused
                  ? Colors.cyanAccent
                  : Colors.cyanAccent.withValues(alpha: 0.5),
              width: _focused ? 2.0 : 1.0,
            ),
            backgroundColor: _focused
                ? Colors.cyanAccent.withValues(alpha: 0.08)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusablePickerRow extends StatefulWidget {
  final String label;
  final bool autofocus;
  final VoidCallback onTap;

  const _FocusablePickerRow({
    required this.label,
    this.autofocus = false,
    required this.onTap,
  });

  @override
  State<_FocusablePickerRow> createState() => _FocusablePickerRowState();
}

class _FocusablePickerRowState extends State<_FocusablePickerRow> {
  AppThemeColors get _tp => context.read<ThemeProvider>().colors;

  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _focused
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.transparent,
          border: _focused ? Border.all(color: _tp.accent, width: 1.5) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          title: Text(
            widget.label,
            style: TextStyle(
              color: _focused ? Colors.white : Colors.white70,
              fontWeight: _focused ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          onTap: widget.onTap,
        ),
      ),
    );
  }
}

class _FocusableSliderRow extends StatefulWidget {
  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final bool autofocus;

  const _FocusableSliderRow({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.autofocus = false,
  });

  @override
  State<_FocusableSliderRow> createState() => _FocusableSliderRowState();
}

class _FocusableSliderRowState extends State<_FocusableSliderRow> {
  AppThemeColors get _tp => context.read<ThemeProvider>().colors;

  bool _focused = false;
  bool _editing = false;

  double get _step => (widget.max - widget.min) / widget.divisions;

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (_editing) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        final v = (widget.value - _step).clamp(widget.min, widget.max);
        widget.onChanged(v);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        final v = (widget.value + _step).clamp(widget.min, widget.max);
        widget.onChanged(v);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.gameButtonA ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.gameButtonB ||
          key == LogicalKeyboardKey.escape) {
        setState(() => _editing = false);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        return KeyEventResult.handled;
      }
    } else {
      if (key == LogicalKeyboardKey.gameButtonA ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.select) {
        setState(() => _editing = true);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _editing
        ? const Color(0xFF7CF7FF)
        : _focused
        ? _tp.accent.withValues(alpha: 0.6)
        : Colors.transparent;

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() {
          _focused = f;
          if (!f) _editing = false;
        });
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: _onKey,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _editing
              ? Colors.white.withValues(alpha: 0.08)
              : _focused
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.transparent,
          border: (_focused || _editing)
              ? Border.all(color: borderColor, width: 1.5)
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                if (_editing)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7CF7FF).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF7CF7FF),
                          width: 0.5,
                        ),
                      ),
                      child: const Text(
                        '◀ ▶',
                        style: TextStyle(color: Color(0xFF7CF7FF), fontSize: 9),
                      ),
                    ),
                  ),
                Text(
                  widget.valueLabel,
                  style: TextStyle(
                    color: _editing ? const Color(0xFF7CF7FF) : Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: _editing
                    ? const Color(0xFF7CF7FF)
                    : _tp.accent,
                inactiveTrackColor: Colors.white12,
                thumbColor: _editing ? const Color(0xFF7CF7FF) : Colors.white,
                overlayColor: Colors.transparent,
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: ExcludeFocus(
                child: Slider(
                  value: widget.value.clamp(widget.min, widget.max),
                  min: widget.min,
                  max: widget.max,
                  divisions: widget.divisions,
                  onChanged: widget.onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
