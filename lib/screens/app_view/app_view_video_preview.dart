part of 'app_view_screen.dart';

mixin _AppViewVideoPreviewMixin on _AppViewScreenBase {
  @override
  void _queueAccentColorExtraction(NvApp app) {
    _accentDebounce?.cancel();
    _bgDebounce?.cancel();
    _bgDebounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted && _selectedAppId == app.appId) {
        setState(() => _debouncedBgAppId = app.appId);
      }
    });

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
      final nApp = visibleApps[neighbor];
      final url = nApp.posterUrl;
      if (url == null || url.isEmpty) continue;

      // Same cache manager + stable key as PosterImage so the prefetch and
      // the widgets share one disk entry.
      precacheImage(
        CachedNetworkImageProvider(
          url,
          maxWidth: 480,
          cacheKey: nApp.artCacheKey('poster'),
          cacheManager: PosterImage.artCacheManager,
        ),
        context,
      );
    }
  }

  @override
  void _scheduleVideoPreview(NvApp app) {
    _lastLibraryInteraction = DateTime.now();
    _videoDelayTimer?.cancel();
    _videoDelayTimer = null;
    final requestId = ++_videoRequestId;

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
      debugPrint(
        '[JUJO][video] schedule BLOCKED: backbone carousel (not detail)',
      );
      _disposeVideoController();
      return;
    }

    if (_videoForAppId != null && _videoForAppId != app.appId) {
      _disposeVideoController();
    }

    if (_videoForAppId == app.appId && _videoReady) {
      debugPrint(
        '[JUJO][video] schedule BLOCKED: already showing for ${app.appName}',
      );
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
      debugPrint(
        '[JUJO][video] skipped — no URL yet for ${app.appName} '
        '(steamVideoUrl=${app.steamVideoUrl}, rawgClipUrl=${app.rawgClipUrl})',
      );
      return;
    }
    debugPrint('[JUJO][video] scheduling for ${app.appName}');
    _videoDelayTimer = Timer(
      Duration(seconds: pluginsProvider.videoDelaySeconds),
      () {
        _videoDelayTimer = null;
        if (!mounted) return;

        if (_selectedAppId != app.appId || requestId != _videoRequestId) return;
        _initVideoController(
          app,
          preferredUrl: previewUrl,
          requestId: requestId,
        );
      },
    );
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
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      return controller;
    } catch (e) {
      await controller?.dispose();
      debugPrint('[JUJO][video] preview initialization failed: $e');
      return null;
    }
  }

  Future<void> _initVideoController(
    NvApp app, {
    String? preferredUrl,
    required int requestId,
  }) async {
    final url = preferredUrl ?? _previewUrlFor(app);
    if (url == null || url.isEmpty) return;

    VideoPlayerController? controller;

    controller = await _tryVideoUrl(url);

    if (controller == null) {
      debugPrint('[JUJO][video] primary failed for ${app.appName}');

      final alt = _deriveCodecFallback(url);
      if (alt != null) {
        debugPrint('[JUJO][video] trying codec fallback');
        controller = await _tryVideoUrl(alt);
        if (controller == null) {
          debugPrint('[JUJO][video] Option C also failed');
        }
      }
    }

    if (controller == null) {
      final steamUrl = app.steamVideoUrl;
      final rawgUrl = app.rawgClipUrl;
      if (steamUrl != null &&
          steamUrl.isNotEmpty &&
          rawgUrl != null &&
          rawgUrl.isNotEmpty &&
          url == steamUrl) {
        debugPrint('[JUJO][video] trying metadata fallback');
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

    bool requestIsCurrent() =>
        mounted &&
        requestId == _videoRequestId &&
        _selectedAppId == app.appId &&
        !_isLaunching;

    if (!mounted || !requestIsCurrent()) {
      await controller.dispose();
      return;
    }

    try {
      final muted = context.read<PluginsProvider>().microtrailerMuted;
      await controller.setVolume(muted ? 0.0 : 1.0);
      if (!requestIsCurrent()) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      await controller.play();
    } catch (e) {
      await controller.dispose();
      debugPrint('[JUJO][video] preview configuration failed: $e');
      return;
    }

    if (!requestIsCurrent()) {
      await controller.dispose();
      return;
    }

    await _videoController?.dispose();
    setState(() {
      _videoController = controller;
      _videoForAppId = app.appId;
      _videoReady = true;
    });
  }

  @override
  void _disposeVideoController() {
    _videoRequestId++;
    _videoDelayTimer?.cancel();
    _videoDelayTimer = null;
    unawaited(_videoController?.dispose());
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
      if (mounted) {
        setState(() {
          _accentColor = null;
          _accentAppId = app.appId;
        });
      }
      return;
    }
    try {
      final imageProvider = CachedNetworkImageProvider(
        app.posterUrl!,
        maxWidth: 100,
      );
      final color = await _extractPosterAccent(
        imageProvider,
        timeout: const Duration(seconds: 3),
      );
      if (!mounted || reqId != _accentRequestId) return;
      setState(() {
        _accentColor = color;
        _accentAppId = app.appId;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _accentColor = null;
          _accentAppId = app.appId;
        });
      }
    }
  }

  Future<Color?> _extractPosterAccent(
    ImageProvider imageProvider, {
    required Duration timeout,
  }) async {
    final stream = imageProvider.resolve(ImageConfiguration.empty);
    final completer = Completer<ImageInfo>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info);
      },
      onError: (error, stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
    );

    stream.addListener(listener);
    try {
      final info = await completer.future.timeout(timeout);
      final image = info.image;
      final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
      if (bytes == null) return null;

      double totalWeight = 0;
      double red = 0;
      double green = 0;
      double blue = 0;
      final width = image.width;
      final height = image.height;
      final pixelCount = width * height;
      final sampleStep = (pixelCount / 2400).ceil().clamp(1, 24);

      for (var pixel = 0; pixel < pixelCount; pixel += sampleStep) {
        final offset = pixel * 4;
        final alpha = bytes.getUint8(offset + 3);
        if (alpha < 180) continue;

        final r = bytes.getUint8(offset);
        final g = bytes.getUint8(offset + 1);
        final b = bytes.getUint8(offset + 2);
        final hsv = HSVColor.fromColor(Color.fromARGB(alpha, r, g, b));
        if (hsv.value < 0.18 || hsv.value > 0.96 || hsv.saturation < 0.22) {
          continue;
        }

        final weight = (0.35 + hsv.saturation) * (0.35 + hsv.value);
        red += r * weight;
        green += g * weight;
        blue += b * weight;
        totalWeight += weight;
      }

      if (totalWeight == 0) return null;
      return Color.fromARGB(
        255,
        (red / totalWeight).round().clamp(0, 255),
        (green / totalWeight).round().clamp(0, 255),
        (blue / totalWeight).round().clamp(0, 255),
      );
    } finally {
      stream.removeListener(listener);
    }
  }
}
