import 'dart:io';

import '../../widgets/poster_image.dart';
import '../../widgets/game_backdrop_art.dart';
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
import 'details_hero.dart';

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

  String get _displayName => _overrideName ?? widget.app.appName;

  AchievementProgress? _liveAchievements;
  String? _steamPersona;

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

  bool _descExpanded = false;

  bool get _trailersEnabled =>
      context.watch<PluginsProvider>().isEnabled('game_video');

  String _t(String es, String en) =>
      AppLocalizations.of(context).locale.languageCode == 'es' ? es : en;

  @override
  Widget build(BuildContext context) {
    final isTV = TvDetector.instance.isTV;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 700;
    final side = wide ? 40.0 : 20.0;
    final heroWidth = wide
        ? (size.width * 0.5).clamp(320.0, 620.0)
        : size.width - side * 2;
    return Focus(
      skipTraversal: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildBackdrop(),
            // The art stays bright behind the hero and dims as the page
            // scrolls into the sections, like a streaming app's title page.
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _scrollController,
                builder: (_, _) {
                  final offset = _scrollController.hasClients
                      ? _scrollController.offset
                      : 0.0;
                  final a = (offset / (size.height * 0.8)).clamp(0.0, 0.85);
                  return ColoredBox(color: Colors.black.withValues(alpha: a));
                },
              ),
            ),
            SafeArea(
              bottom: false,
              child: FocusTraversalGroup(
                policy: WidgetOrderTraversalPolicy(),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(side, 4, side, isTV ? 72 : 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopBar(),
                      SizedBox(height: wide ? size.height * 0.08 : 4),
                      SizedBox(width: heroWidth, child: _buildHero(wide)),
                      ..._buildSections(),
                    ],
                  ),
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
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildBackdrop() {
    return Stack(
      fit: StackFit.expand,
      children: [
        GameBackdropArt(
          app: widget.app,
          heroCacheWidth: context.read<ThemeProvider>().backgroundArtCacheWidth,
          fallbackColor: const Color(0xFF0B1624),
        ),
        if (_trailersEnabled && _steamMovies.isNotEmpty)
          DetailsBackdropTrailer(movies: _steamMovies),
        // Left scrim carries the text; the right side keeps the art.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [0, 0.42, 0.85],
              colors: [Color(0xF0000000), Color(0x99000000), Color(0x00000000)],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.3, 1],
              colors: [Color(0x80000000), Color(0x00000000), Color(0xF2000000)],
            ),
          ),
        ),
        // Narrow screens stack the text over the whole art, so the lower part
        // (where the sections start) needs its own dark ground.
        if (MediaQuery.sizeOf(context).width < 700)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.25, 0.55, 1],
                colors: [
                  Color(0x00000000),
                  Color(0xD9000000),
                  Color(0xF7000000),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          tooltip: AppLocalizations.of(context).back,
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: _saving ? null : _saveOverrides,
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          icon: const Icon(Icons.save_outlined, size: 18),
          label: Text(AppLocalizations.of(context).save),
        ),
      ],
    );
  }

  /// Store logo when Steam knows the game (streaming apps lead with the title
  /// treatment); the name as type otherwise, in the same box so nothing jumps.
  Widget _buildTitleArt(bool wide) {
    final height = wide ? 110.0 : 72.0;
    final title = Align(
      alignment: Alignment.bottomLeft,
      child: Text(
        _displayName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: wide ? 42 : 30,
          fontWeight: FontWeight.w900,
          height: 1.02,
          letterSpacing: -0.6,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 18)],
        ),
      ),
    );
    final id = _resolvedSteamAppId;
    // A renamed game keeps the user's name; the store logo would undo it.
    return SizedBox(
      height: height,
      child: id == null || _overrideName != null
          ? title
          : Image.network(
              'https://cdn.cloudflare.steamstatic.com/steam/apps/$id/logo.png',
              alignment: Alignment.bottomLeft,
              fit: BoxFit.contain,
              frameBuilder: (_, child, frame, sync) =>
                  frame == null && !sync ? title : child,
              errorBuilder: (_, _, _) => title,
            ),
    );
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  Widget _buildHero(bool wide) {
    final l = AppLocalizations.of(context);
    final app = widget.app;
    final store = _storeInfo;
    final genres = (store?.genres.isNotEmpty ?? false)
        ? store!.genres
        : app.metadataGenres.isNotEmpty
        ? app.metadataGenres
        : app.tags;
    final desc = (app.description?.trim().isNotEmpty ?? false)
        ? app.description!.trim()
        : store?.shortDescription;
    final year = RegExp(
      r'\d{4}',
    ).firstMatch(store?.releaseDate ?? app.releaseDate ?? '')?[0];
    final playtime = _ownedGameInfo?.playtimeMinutes ?? app.playtimeMinutes;
    final pct = store?.positivePercent;
    const metaStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w700,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitleArt(wide),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (app.isRunning)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.circle, size: 8, color: Colors.greenAccent),
                  const SizedBox(width: 6),
                  Text(
                    l.running,
                    style: metaStyle.copyWith(color: Colors.greenAccent),
                  ),
                ],
              ),
            if (year != null) Text(year, style: metaStyle),
            if (playtime > 0) Text(_formatMinutes(playtime), style: metaStyle),
            if (app.isHdrSupported)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white70),
                ),
                child: Text(
                  l.hdrLabel,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (store?.metacriticScore != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5C518),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      'MC',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${store!.metacriticScore}',
                    style: metaStyle.copyWith(color: const Color(0xFFF5C518)),
                  ),
                ],
              ),
            if (pct != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.thumb_up_alt_rounded,
                    size: 14,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 5),
                  Text('${(pct * 100).round()}%', style: metaStyle),
                ],
              ),
            if (_favorite)
              const Icon(Icons.star_rounded, size: 18, color: Colors.amber),
          ],
        ),
        if (genres.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            genres.take(3).join('  •  '),
            style: const TextStyle(
              color: Color(0xB3FFFFFF),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        if (desc != null && desc.isNotEmpty) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() => _descExpanded = !_descExpanded),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topLeft,
              child: Text(
                desc,
                maxLines: _descExpanded ? null : (wide ? 4 : 3),
                overflow: _descExpanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xE6FFFFFF),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Flexible(
              child: SizedBox(
                width: 400,
                child: DetailsPlayPill(
                  label: app.isRunning ? l.resume : l.play,
                  onTap: () => Navigator.pop(context, AppDetailsAction.play),
                ),
              ),
            ),
            const SizedBox(width: 12),
            DetailsCircleButton(
              icon: _favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              label: _favorite ? l.unfav : l.fav,
              activeColor: _favorite ? Colors.amber : null,
              onTap: _toggleFavorite,
            ),
            if (_trailersEnabled) ...[
              const SizedBox(width: 10),
              DetailsCircleButton(
                icon: Icons.movie_outlined,
                label: l.watchTrailer,
                onTap: _openTrailerModal,
              ),
            ],
            const SizedBox(width: 10),
            DetailsCircleButton(
              icon: Icons.more_horiz_rounded,
              label: l.options,
              onTap: _showMoreActions,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _toggleFavorite() async {
    await widget.onToggleFavorite();
    if (mounted) setState(() => _favorite = !_favorite);
  }

  void _showMoreActions() {
    final l = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12161F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        var first = true;
        Widget item(
          IconData icon,
          String label,
          VoidCallback onTap, {
          Color? color,
        }) {
          final autofocus = first;
          first = false;
          return ListTile(
            autofocus: autofocus,
            leading: Icon(icon, color: color ?? Colors.white70),
            title: Text(label, style: TextStyle(color: color ?? Colors.white)),
            onTap: () {
              Navigator.pop(ctx);
              onTap();
            },
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.app.isRunning)
                  item(
                    Icons.power_settings_new,
                    l.closeSession,
                    _closeSession,
                    color: Colors.redAccent,
                  ),
                if (widget.onAddToCollection != null)
                  item(
                    Icons.playlist_add_rounded,
                    l.addToCollection,
                    widget.onAddToCollection!,
                  ),
                item(Icons.edit_outlined, l.editName, _showEditNameDialog),
                item(Icons.image_outlined, l.editPoster, _showEditPosterDialog),
                item(Icons.restart_alt, l.resetLabel, _resetOverrides),
              ],
            ),
          ),
        );
      },
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

  List<Widget> _buildSections() {
    final l = AppLocalizations.of(context);
    final app = widget.app;
    final store = _storeInfo;
    final prog = _achievements;
    final trailers = _trailersEnabled
        ? _steamMovies.take(6).toList()
        : const [];
    final shots = app.screenshotUrls;

    final steamPlay = _ownedGameInfo?.playtimeMinutes ?? app.playtimeMinutes;
    final recent = _ownedGameInfo?.playtimeRecentMinutes ?? 0;
    final activity = <Widget>[
      if (steamPlay > 0)
        DetailsFact(label: l.timePlayed, value: _formatMinutes(steamPlay)),
      if (recent > 0)
        DetailsFact(label: l.last2Weeks, value: _formatMinutes(recent)),
      DetailsFact(
        label: l.lastSessionLabel,
        value: _formatLastSession(widget.profile.lastSessionAt),
      ),
      DetailsFact(
        label: l.launchCountLabel,
        value: '${widget.profile.launchCount}',
      ),
      if (_localPlaytimeSec > 0)
        DetailsFact(
          label: _t('Tiempo en JUJO', 'Time in JUJO'),
          value: SessionHistoryService.formatDuration(_localPlaytimeSec),
        ),
      if (prog != null)
        DetailsFact(
          label: _t('Logros', 'Achievements'),
          value: '${prog.unlocked}/${prog.total} · ${prog.percent.round()}%',
          valueColor: prog.isComplete ? Colors.amber : null,
        ),
      DetailsFact(
        label: l.overridesLabelMeta,
        value: widget.profile.hasOverrides ? l.customProfile : l.globalOnly,
      ),
    ];

    final pct = store?.positivePercent;
    String? pick(String? storeValue, String? hostValue) =>
        (storeValue?.isNotEmpty ?? false)
        ? storeValue
        : (hostValue?.isNotEmpty ?? false)
        ? hostValue
        : null;
    final releaseDate = pick(store?.releaseDate, widget.app.releaseDate);
    final developer = pick(store?.developers.join(', '), widget.app.developer);
    final publisher = pick(store?.publishers.join(', '), widget.app.publisher);
    final about = <Widget>[
      if (releaseDate != null)
        DetailsFact(label: l.releaseDate, value: releaseDate),
      if (developer != null)
        DetailsFact(label: l.developerLabel, value: developer),
      if (publisher != null)
        DetailsFact(label: _t('Distribuidora', 'Publisher'), value: publisher),
      if (store?.reviewDescription?.isNotEmpty ?? false)
        DetailsFact(
          label: _t('Reseñas', 'Reviews'),
          value: pct == null
              ? store!.reviewDescription!
              : '${store!.reviewDescription} · ${(pct * 100).round()}%',
          valueColor: pct == null
              ? null
              : pct >= 0.8
              ? Colors.greenAccent
              : pct >= 0.5
              ? Colors.amberAccent
              : Colors.redAccent,
        ),
      if (store?.metacriticScore != null)
        DetailsFact(
          label: l.metacriticLabel,
          value: '${store!.metacriticScore}',
        ),
      if (app.pluginName?.isNotEmpty ?? false)
        DetailsFact(label: _t('Origen', 'Source'), value: app.pluginName!),
      if (_steamPersona?.isNotEmpty ?? false)
        DetailsFact(label: l.accountLabel, value: _steamPersona!),
    ];

    Widget facts(List<Widget> children) =>
        Wrap(spacing: 36, runSpacing: 18, children: children);

    return [
      if (trailers.isNotEmpty || shots.isNotEmpty)
        DetailsSection(
          title: _t('Multimedia', 'Media'),
          child: SizedBox(
            height: 135,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final m in trailers)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: DetailsMediaCard(
                      isVideo: true,
                      caption: m.name,
                      onTap: _openTrailerModal,
                      image: m.thumbnail == null
                          ? const SizedBox.shrink()
                          : Image.network(
                              m.thumbnail!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox.shrink(),
                            ),
                    ),
                  ),
                for (var i = 0; i < shots.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: DetailsMediaCard(
                      onTap: () => _openScreenshot(i),
                      image: PosterImage(
                        url: shots[i],
                        cacheKey: app.artCacheKey('shot', i),
                        fit: BoxFit.cover,
                        memCacheWidth: 480,
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      DetailsSection(
        title: _t('Tu actividad', 'Your activity'),
        child: facts(activity),
      ),
      if (about.isNotEmpty || _storeInfoLoading || _anySteamPluginEnabled)
        DetailsSection(
          title: l.gameInformation,
          child: _storeInfoLoading && about.isEmpty
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white24,
                  ),
                )
              : about.isEmpty
              ? Text(
                  l.steamApiKeyHint,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    height: 1.4,
                  ),
                )
              : facts(about),
        ),
      DetailsSection(
        title: _t('Ajustes de stream', 'Stream settings'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPresetDeck(),
            const SizedBox(height: 18),
            _buildOverridesEditor(),
          ],
        ),
      ),
    ];
  }

  void _openScreenshot(int index) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(
          child: Center(
            child: PosterImage(
              url: widget.app.screenshotUrls[index],
              cacheKey: widget.app.artCacheKey('shot', index),
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
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

  Widget _subLabel(String text) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: Color(0x8CFFFFFF),
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    ),
  );

  Widget _buildPresetDeck() {
    final l = AppLocalizations.of(context);
    final presets = [
      (_GamePreset.balanced, l.balanced, l.balancedSub),
      (_GamePreset.competitive, l.competitive, l.competitiveSub),
      (_GamePreset.visualQuality, l.visualQuality, l.visualQualitySub),
      (_GamePreset.handheld, l.handheld, l.handheldSub),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subLabel(l.quickPresets),
        const SizedBox(height: 4),
        Text(
          l.presetExplain,
          style: const TextStyle(
            color: Color(0x99FFFFFF),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        // Four even columns (two on narrow screens), never a lone tile on its
        // own row; capped so a TV doesn't stretch them into bars.
        LayoutBuilder(
          builder: (context, box) {
            final cols = box.maxWidth >= 640 ? 4 : 2;
            final width = ((box.maxWidth - 12 * (cols - 1)) / cols).clamp(
              0.0,
              240.0,
            );
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (preset, title, subtitle) in presets)
                  _presetTile(preset, title, subtitle, width),
              ],
            );
          },
        ),
      ],
    );
  }

  /// Compact preset chip: same translucent surface and white focus ring as
  /// the Media cards, so the settings read as part of the page.
  Widget _presetTile(
    _GamePreset preset,
    String title,
    String subtitle,
    double width,
  ) {
    final specs = _presetBadges(preset).join(' · ');
    return Tooltip(
      message: subtitle,
      child: DetailsTappable(
        onTap: () => _applyPreset(preset),
        semanticLabel: '$title. $subtitle. $specs',
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: width,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: focused ? const Color(0x29FFFFFF) : const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused ? Colors.white : const Color(0x1FFFFFFF),
              width: focused ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(_presetIcon(preset), size: 18, color: Colors.white70),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                specs,
                style: const TextStyle(
                  color: Color(0x99FFFFFF),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
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

  Widget _buildOverridesEditor() {
    final l = AppLocalizations.of(context);
    final rows = <Widget>[
      _FocusableSliderRow(
        title: l.bitrate,
        valueLabel: '${_bitrate ~/ 1000} Mbps',
        value: _bitrate.toDouble(),
        min: 1000,
        max: 80000,
        divisions: 79,
        onChanged: (v) => setState(() => _bitrate = v.round()),
      ),
      _FocusableChoiceRow(
        title: l.fpsLabel,
        value: '$_fps FPS',
        onTap: () => _pickFps(),
      ),
      _FocusableChoiceRow(
        title: l.videoCodec,
        value: _codecLabel(_codec),
        onTap: () => _pickCodec(),
      ),
      _FocusableSwitchRow(
        title: l.forceHdr,
        value: _hdr,
        onChanged: (v) => setState(() => _hdr = v),
      ),
      _FocusableSwitchRow(
        title: l.showOnScreenControls,
        value: _showGamepad,
        onChanged: (v) => setState(() => _showGamepad = v),
      ),
      _FocusableSwitchRow(
        title: l.ultraLowLatency,
        value: _ultraLowLatency,
        onChanged: (v) => setState(() => _ultraLowLatency = v),
      ),
      _FocusableSwitchRow(
        title: l.performanceOverlayLabel,
        value: _perfOverlay,
        onChanged: (v) => setState(() => _perfOverlay = v),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subLabel(l.perGameStreamProfile),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              for (final (i, row) in rows.indexed) ...[
                if (i > 0) const Divider(height: 1, color: Color(0x14FFFFFF)),
                row,
              ],
            ],
          ),
        ),
      ],
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
        final scale = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
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

  const _FocusableSliderRow({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
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
        padding: const EdgeInsets.symmetric(vertical: 8),
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
