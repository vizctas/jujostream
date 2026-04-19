part of 'app_view_screen.dart';

mixin _AppViewVideoPreviewMixin on _AppViewScreenBase {

  @override
  void _queueAccentColorExtraction(NvApp app) {
    _accentDebounce?.cancel();

    _precacheAdjacentBackgrounds(app);

    final reduce = context.read<ThemeProvider>().reduceEffects;
    if (TvDetector.instance.isTV || reduce) {

      _accentDebounce = Timer(const Duration(milliseconds: 150), () {
        _scheduleVideoPreview(app);
      });
      return;
    }

    _accentDebounce = Timer(const Duration(milliseconds: 250), () {
      _extractAccentColor(app);
    });
    _scheduleVideoPreview(app);
  }

  void _precacheAdjacentBackgrounds(NvApp app) {
    final provider = context.read<AppListProvider>();
    final visibleApps = _visibleApps(provider.apps.toList());
    final idx = visibleApps.indexWhere((a) => a.appId == app.appId);
    if (idx < 0) return;

    for (final offset in const [-1, 1]) {
      final neighbor = idx + offset;
      if (neighbor < 0 || neighbor >= visibleApps.length) continue;
      final url = visibleApps[neighbor].posterUrl;
      if (url == null || url.isEmpty) continue;

      precacheImage(
        CachedNetworkImageProvider(url, maxWidth: 480),
        context,
      );
    }
  }

  @override
  void _scheduleVideoPreview(NvApp app) {
    _videoDelayTimer?.cancel();

    if (_isLaunching) {
      debugPrint('[JUJO][video] schedule BLOCKED: game launch in progress');
      return;
    }

    if (_viewMode == _ViewMode.grid) {
      debugPrint('[JUJO][video] schedule BLOCKED: grid mode');
      _disposeVideoController();
      return;
    }

    final themeId = context.read<ThemeProvider>().launcherTheme.id;
    if (themeId == LauncherThemeId.backbone && !_isDetailView) {
      debugPrint('[JUJO][video] schedule BLOCKED: backbone carousel (not detail)');
      _disposeVideoController();
      return;
    }

    if (_videoForAppId != null && _videoForAppId != app.appId) {
      _disposeVideoController();
    }

    if (_videoForAppId == app.appId && _videoReady) {
      debugPrint('[JUJO][video] schedule BLOCKED: already showing for ${app.appName}');
      return;
    }

    final pluginsProvider = context.read<PluginsProvider>();
    if (!pluginsProvider.isEnabled('game_video')) {
      debugPrint('[JUJO][video] schedule BLOCKED: game_video plugin disabled');
      _disposeVideoController();
      return;
    }

    final previewUrl = _previewUrlFor(app);
    if (previewUrl == null) {
      debugPrint('[JUJO][video] skipped — no URL yet for ${app.appName} '
          '(steamVideoUrl=${app.steamVideoUrl}, rawgClipUrl=${app.rawgClipUrl})');
      return;
    }
    debugPrint('[JUJO][video] scheduling for ${app.appName} url=$previewUrl');
    _videoDelayTimer = Timer(Duration(seconds: pluginsProvider.videoDelaySeconds), () {
      if (!mounted) return;

      if (_selectedAppId != app.appId) return;
      _initVideoController(app, preferredUrl: previewUrl);
    });
  }

  @override
  String? _previewUrlFor(NvApp app) {
    final steam = app.steamVideoUrl;
    if (steam != null && steam.isNotEmpty) return steam;
    final rawg = app.rawgClipUrl;
    if (rawg != null && rawg.isNotEmpty) return rawg;
    return null;
  }

  static String? _deriveCodecFallback(String url) {
    if (url.contains('.webm')) {
      final mp4 = url
          .replaceAll('_vp9.webm', '.mp4')
          .replaceAll('.webm', '.mp4');
      if (mp4 != url) return mp4;
    }
    if (url.contains('cdn.akamai.steamstatic.com')) {
      return url.replaceFirst(
        'cdn.akamai.steamstatic.com',
        'video.fastly.steamstatic.com',
      );
    }
    return null;
  }

  Future<VideoPlayerController?> _tryVideoUrl(String url) async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      return c;
    } catch (e) {
      debugPrint('[JUJO][video] _tryVideoUrl FAILED url=$url error=$e');
      return null;
    }
  }

  Future<void> _initVideoController(NvApp app, {String? preferredUrl}) async {
    final url = preferredUrl ?? _previewUrlFor(app);
    if (url == null || url.isEmpty) return;

    VideoPlayerController? controller;

    controller = await _tryVideoUrl(url);

    if (controller == null) {
      debugPrint('[JUJO][video] primary failed for ${app.appName} url=$url');

      final alt = _deriveCodecFallback(url);
      if (alt != null) {
        debugPrint('[JUJO][video] Option C trying $alt');
        controller = await _tryVideoUrl(alt);
        if (controller == null) {
          debugPrint('[JUJO][video] Option C also failed');
        }
      }
    }

    if (controller == null) {
      final steamUrl = app.steamVideoUrl;
      final rawgUrl = app.rawgClipUrl;
      if (steamUrl != null && steamUrl.isNotEmpty &&
          rawgUrl != null && rawgUrl.isNotEmpty &&
          url == steamUrl) {
        debugPrint('[JUJO][video] trying RAWG fallback $rawgUrl');
        controller = await _tryVideoUrl(rawgUrl);
        if (controller == null) {

          final rawgAlt = _deriveCodecFallback(rawgUrl);
          if (rawgAlt != null) controller = await _tryVideoUrl(rawgAlt);
        }
      }
    }

    if (controller == null) {
      debugPrint('[JUJO][video] all fallbacks exhausted for ${app.appName}');
      return;
    }

    if (!mounted || _selectedAppId != app.appId) {
      controller.dispose();
      return;
    }

    final muted = context.read<PluginsProvider>().microtrailerMuted;
    await controller.setVolume(muted ? 0.0 : 1.0);
    await controller.setLooping(true);
    await controller.play();

    _videoController?.dispose();
    setState(() {
      _videoController = controller;
      _videoForAppId = app.appId;
      _videoReady = true;
    });
  }

  @override
  void _disposeVideoController() {
    _videoDelayTimer?.cancel();
    _videoController?.dispose();
    _videoController = null;
    _videoForAppId = null;
    if (_videoReady) {
      _videoReady = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Future<void> _extractAccentColor(NvApp app) async {
    if (app.appId == _accentAppId) return;
    final reqId = ++_accentRequestId;
    if (app.posterUrl == null || app.posterUrl!.isEmpty) {
      if (mounted) setState(() { _accentColor = null; _accentAppId = app.appId; });
      return;
    }
    try {

      final imageProvider = CachedNetworkImageProvider(
        app.posterUrl!,
        maxWidth: 100,
      );
      final palette = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 8,
        timeout: const Duration(seconds: 3),
      );
      if (!mounted || reqId != _accentRequestId) return;
      final color = palette.vibrantColor?.color ??
          palette.dominantColor?.color ??
          palette.mutedColor?.color;
      setState(() {
        _accentColor = color;
        _accentAppId = app.appId;
      });
    } catch (_) {

      if (mounted) setState(() { _accentColor = null; _accentAppId = app.appId; });
    }
  }
}

class _BeforeServerVideo extends StatefulWidget {
  final String videoPath;
  const _BeforeServerVideo({required this.videoPath});

  @override
  State<_BeforeServerVideo> createState() => _BeforeServerVideoState();
}

class _BeforeServerVideoState extends State<_BeforeServerVideo> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final c = VideoPlayerController.file(io.File(widget.videoPath));
    try {
      await c.initialize();
      if (!mounted) { c.dispose(); return; }
      await c.setLooping(false);
      await c.play();
      c.addListener(() {
        if (!mounted) return;
        final v = c.value;
        if (v.isInitialized &&
            v.duration > Duration.zero &&
            v.position >= v.duration) {
          _dismiss();
        }
      });
      setState(() => _controller = c);
    } catch (_) {
      c.dispose();
      _dismiss();
    }
  }

  void _dismiss() {
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _dismiss,
        child: c != null && c.value.isInitialized
            ? Stack(
                fit: StackFit.expand,
                children: [
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: c.value.size.width,
                      height: c.value.size.height,
                      child: VideoPlayer(c),
                    ),
                  ),
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _dismiss,
                      icon: const Icon(Icons.skip_next),
                      label: Text(AppLocalizations.of(context).skip),
                    ),
                  ),
                ],
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
