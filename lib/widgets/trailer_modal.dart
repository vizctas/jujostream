import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n/app_localizations.dart';
import '../providers/theme_provider.dart';
import '../services/input/gamepad_button_helper.dart';
import '../services/metadata/steam_video_client.dart';

enum TrailerSource { steam, youtube }

class TrailerModal extends StatefulWidget {
  final String gameName;
  final List<SteamMovie> steamMovies;
  final TrailerSource? preferredSource;

  const TrailerModal({
    super.key,
    required this.gameName,
    this.steamMovies = const [],
    this.preferredSource,
  });

  @override
  State<TrailerModal> createState() => _TrailerModalState();
}

class _TrailerModalState extends State<TrailerModal> {
  late TrailerSource _source;
  VideoPlayerController? _videoController;
  bool _videoError = false;
  WebViewController? _webViewController;

  bool get _hasSteam => widget.steamMovies.isNotEmpty;

  bool get _canFullscreen =>
      _source == TrailerSource.steam &&
      _videoController != null &&
      _videoController!.value.isInitialized &&
      !_videoError;

  @override
  void initState() {
    super.initState();
    _source =
        widget.preferredSource ??
        (_hasSteam ? TrailerSource.steam : TrailerSource.youtube);
    _initSource();
  }

  void _initSource() {
    if (_source == TrailerSource.steam && _hasSteam) {
      _initSteamPlayer();
    } else {
      _initYouTubeWebView();
    }
  }

  void _initSteamPlayer() {
    final movie = widget.steamMovies.first;
    final url = movie.bestUrl;
    if (url == null) {
      setState(() => _videoError = true);
      return;
    }
    _videoController?.dispose();
    _videoController = VideoPlayerController.networkUrl(Uri.parse(url))
      ..initialize()
          .then((_) {
            if (mounted) {
              setState(() {});
              _videoController!.play();
            }
          })
          .catchError((_) {
            if (mounted) setState(() => _videoError = true);
          });
  }

  void _initYouTubeWebView() {
    final query = Uri.encodeComponent('${widget.gameName} official trailer');
    final searchUrl = 'https://m.youtube.com/results?search_query=$query';
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = request.url;
            if (url.contains('youtube.com') ||
                url.contains('googlevideo.com') ||
                url.contains('google.com') ||
                url.contains('accounts.google')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(searchUrl));
    if (mounted) setState(() {});
  }

  void _switchSource(TrailerSource source) {
    if (_source == source) return;
    _videoController?.pause();
    setState(() {
      _source = source;
      _videoError = false;
    });
    _initSource();
  }

  void _enterFullscreen() {
    if (!_canFullscreen) return;
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, _, _) =>
            _FullscreenTrailerPage(controller: _videoController!),
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.gameButtonY) {
          if (_canFullscreen) {
            _enterFullscreen();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        if (key == LogicalKeyboardKey.gameButtonB ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: const Color(0xFF0D1624),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildSourceTabs(),
            const Divider(height: 1, color: Colors.white12),
            Expanded(child: _buildPlayer()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.movie_outlined, color: Colors.white70, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l.trailerTitle(widget.gameName),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          if (_canFullscreen)
            GestureDetector(
              onTap: _enterFullscreen,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.fullscreen,
                      color: Colors.white54,
                      size: 16,
                    ),
                    const SizedBox(width: 5),
                    GamepadHintIcon('Y', size: 16, forceVisible: true),
                  ],
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          if (_hasSteam)
            _sourceTab(
              label: 'Steam',
              icon: Icons.videogame_asset,
              active: _source == TrailerSource.steam,
              onTap: () => _switchSource(TrailerSource.steam),
            ),
          if (_hasSteam) const SizedBox(width: 10),
          _sourceTab(
            label: 'YouTube',
            icon: Icons.play_circle_outline,
            active: _source == TrailerSource.youtube,
            onTap: () => _switchSource(TrailerSource.youtube),
          ),
        ],
      ),
    );
  }

  Widget _sourceTab({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? context.read<ThemeProvider>().colors.accent.withValues(
                      alpha: 0.5,
                    )
                  : Colors.white12,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: active
                    ? context.read<ThemeProvider>().colors.accent
                    : Colors.white38,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: active
                      ? context.read<ThemeProvider>().colors.accent
                      : Colors.white54,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayer() {
    if (_source == TrailerSource.steam) return _buildSteamPlayer();
    return _buildYouTubePlayer();
  }

  Widget _buildSteamPlayer() {
    final l = AppLocalizations.of(context);
    if (_videoError) {
      return _placeholder(icon: Icons.error_outline, text: l.trailerSteamError);
    }
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return Center(
        child: CircularProgressIndicator(
          color: context.read<ThemeProvider>().colors.accent,
        ),
      );
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          ),
        ),
        Positioned(
          bottom: 16,
          left: 20,
          right: 20,
          child: _SteamControls(
            controller: _videoController!,
            showFullscreen: true,
            onFullscreen: _enterFullscreen,
          ),
        ),
      ],
    );
  }

  Widget _buildYouTubePlayer() {
    if (_webViewController == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.redAccent),
      );
    }
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      child: WebViewWidget(controller: _webViewController!),
    );
  }

  Widget _placeholder({required IconData icon, required String text}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white24, size: 48),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _FullscreenTrailerPage extends StatefulWidget {
  final VideoPlayerController controller;

  const _FullscreenTrailerPage({required this.controller});

  @override
  State<_FullscreenTrailerPage> createState() => _FullscreenTrailerPageState();
}

class _FullscreenTrailerPageState extends State<_FullscreenTrailerPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  void _exit() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.gameButtonY ||
            key == LogicalKeyboardKey.gameButtonB ||
            key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.goBack) {
          _exit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _exit,
          behavior: HitTestBehavior.translucent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: widget.controller.value.aspectRatio,
                  child: VideoPlayer(widget.controller),
                ),
              ),

              Positioned(
                bottom: 24,
                left: 20,
                right: 20,
                child: _SteamControls(
                  controller: widget.controller,
                  showFullscreen: false,
                  isFullscreen: true,
                  onExitFullscreen: _exit,
                ),
              ),

              Positioned(
                top: 16,
                right: 16,
                child: _GamepadHintBadge(
                  button: 'Y',
                  label: l.exitFullscreen,
                  icon: Icons.fullscreen_exit,
                ),
              ),

              Positioned(
                top: 16,
                left: 16,
                child: GestureDetector(
                  onTap: _exit,
                  child: _GamepadHintBadge(
                    button: 'B',
                    label: l.goBack,
                    icon: Icons.arrow_back,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SteamControls extends StatefulWidget {
  final VideoPlayerController controller;
  final bool showFullscreen;
  final bool isFullscreen;
  final VoidCallback? onFullscreen;
  final VoidCallback? onExitFullscreen;

  const _SteamControls({
    required this.controller,
    this.showFullscreen = false,
    this.isFullscreen = false,
    this.onFullscreen,
    this.onExitFullscreen,
  });

  @override
  State<_SteamControls> createState() => _SteamControlsState();
}

class _SteamControlsState extends State<_SteamControls> {
  bool _visible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _showControls() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _showControls,
      onPanDown: (_) => _showControls(),
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: IgnorePointer(ignoring: !_visible, child: _buildBar()),
      ),
    );
  }

  Widget _buildBar() {
    return ValueListenableBuilder(
      valueListenable: widget.controller,
      builder: (_, value, _) {
        final position = value.position;
        final duration = value.duration;
        final playing = value.isPlaying;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  playing
                      ? widget.controller.pause()
                      : widget.controller.play();
                  _showControls();
                },
                child: Icon(
                  playing ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _fmt(position),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Expanded(
                child: ExcludeFocus(
                  child: Slider(
                    value: duration.inMilliseconds > 0
                        ? position.inMilliseconds / duration.inMilliseconds
                        : 0,
                    onChanged: (v) {
                      widget.controller.seekTo(
                        Duration(
                          milliseconds: (v * duration.inMilliseconds).round(),
                        ),
                      );
                    },
                    activeColor: context
                        .read<ThemeProvider>()
                        .colors
                        .accentLight,
                    inactiveColor: Colors.white24,
                  ),
                ),
              ),
              Text(
                _fmt(duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (widget.showFullscreen && widget.onFullscreen != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onFullscreen,
                  child: const Icon(
                    Icons.fullscreen,
                    color: Colors.white70,
                    size: 24,
                  ),
                ),
              ],
              if (widget.isFullscreen && widget.onExitFullscreen != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onExitFullscreen,
                  child: const Icon(
                    Icons.fullscreen_exit,
                    color: Colors.white70,
                    size: 24,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _GamepadHintBadge extends StatelessWidget {
  final String button;
  final String label;
  final IconData icon;

  const _GamepadHintBadge({
    required this.button,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white54, size: 16),
          const SizedBox(width: 6),
          GamepadHintIcon(button, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
