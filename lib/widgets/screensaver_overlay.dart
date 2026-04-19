import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_list_provider.dart';
import '../providers/computer_provider.dart';
import '../providers/plugins_provider.dart';

class ScreensaverWrapper extends StatefulWidget {
  final Widget child;

  final ValueChanged<bool>? onScreensaverChanged;

  const ScreensaverWrapper({
    super.key,
    required this.child,
    this.onScreensaverChanged,
  });

  @override
  State<ScreensaverWrapper> createState() => _ScreensaverWrapperState();
}

class _ScreensaverWrapperState extends State<ScreensaverWrapper>
    with WidgetsBindingObserver {
  Timer? _idleTimer;
  bool _screensaverActive = false;
  bool _dismissCooldown = false;
  int _timeoutSec = 120;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTimeout();
  }

  Future<void> _loadTimeout() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(
      PluginsProvider.settingPref('screensaver', 'timeout_sec'),
    );
    if (saved != null) {
      _timeoutSec = int.tryParse(saved) ?? 120;
    }
    _resetTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _idleTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      if (!_screensaverActive) _resetTimer();
    }
  }

  bool get _isEnabled {
    try {
      return context.read<PluginsProvider>().isEnabled('screensaver');
    } catch (_) {
      return true;
    }
  }

  bool get _isStreaming {
    try {
      return context.read<ComputerProvider>().activeSessionApp != null;
    } catch (_) {
      return false;
    }
  }

  void _resetTimer() {
    _idleTimer?.cancel();
    if (!_isEnabled || _isStreaming) return;
    _idleTimer = Timer(Duration(seconds: _timeoutSec), _showScreensaver);
  }

  void _onUserActivity() {
    if (_screensaverActive) {
      setState(() {
        _screensaverActive = false;
        _dismissCooldown = true;
      });
      widget.onScreensaverChanged?.call(false);

      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _dismissCooldown = false);
      });
    }
    _resetTimer();
  }

  void _showScreensaver() {
    if (!mounted || !_isEnabled || _isStreaming) return;
    setState(() => _screensaverActive = true);
    widget.onScreensaverChanged?.call(true);
  }

  @override
  Widget build(BuildContext context) {
    final plugins = context.watch<PluginsProvider>();
    final enabled = plugins.isEnabled('screensaver');

    final computerProvider = context.watch<ComputerProvider>();
    final streaming = computerProvider.activeSessionApp != null;

    if (streaming && _screensaverActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _screensaverActive = false);
          _idleTimer?.cancel();
        }
      });
    }

    if (!enabled && _screensaverActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _screensaverActive = false);
      });
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (!_screensaverActive && enabled && !streaming) _resetTimer();
      },
      child: Focus(
        onKeyEvent: (_, event) {
          if (_screensaverActive || _dismissCooldown) {
            if (event is KeyDownEvent) {
              _onUserActivity();
            }
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent && enabled && !streaming) {
            _resetTimer();
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            widget.child,
            if (_screensaverActive)
              Positioned.fill(
                child: _ScreensaverBarrier(onDismiss: _onUserActivity),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScreensaverBarrier extends StatefulWidget {
  final VoidCallback onDismiss;
  const _ScreensaverBarrier({required this.onDismiss});

  @override
  State<_ScreensaverBarrier> createState() => _ScreensaverBarrierState();
}

class _ScreensaverBarrierState extends State<_ScreensaverBarrier> {
  bool _dismissing = false;

  void _dismiss() {
    if (_dismissing) return;
    _dismissing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _dismiss(),
      onPanStart: (_) => _dismiss(),
      child: AbsorbPointer(
        absorbing: true,
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (!_dismissing && event is KeyDownEvent) {
              _dismiss();
            }
            return KeyEventResult.handled;
          },
          child: _ScreensaverOverlay(onDismiss: widget.onDismiss),
        ),
      ),
    );
  }
}

class _ScreensaverOverlay extends StatefulWidget {
  final VoidCallback onDismiss;

  const _ScreensaverOverlay({required this.onDismiss});

  @override
  State<_ScreensaverOverlay> createState() => _ScreensaverOverlayState();
}

class _ScreensaverOverlayState extends State<_ScreensaverOverlay>
    with TickerProviderStateMixin {
  final _rng = Random();
  int _currentIndex = 0;
  List<String> _posterUrls = const [];
  Timer? _slideTimer;

  late AnimationController _fadeController;
  late AnimationController _kenBurnsController;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _fadeController.forward();

    _kenBurnsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadImages());
  }

  void _loadImages() {
    final apps = context.read<AppListProvider>().apps;
    final urls = apps
        .where((a) => a.posterUrl?.isNotEmpty ?? false)
        .map((a) => a.posterUrl!)
        .toList();
    urls.shuffle(_rng);
    if (!mounted) return;
    setState(() => _posterUrls = urls);

    _slideTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % _posterUrls.length.clamp(1, 9999);
      });
    });
  }

  @override
  void dispose() {
    _slideTimer?.cancel();
    _fadeController.dispose();
    _kenBurnsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_posterUrls.isNotEmpty)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 1200),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: _KenBurnsImage(
                  key: ValueKey(_currentIndex),
                  url: _posterUrls[_currentIndex % _posterUrls.length],
                  controller: _kenBurnsController,
                ),
              )
            else
              AnimatedBuilder(
                animation: _kenBurnsController,
                builder: (_, _) {
                  final t = _kenBurnsController.value;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-1 + t * 2, -1),
                        end: Alignment(1 - t * 2, 1),
                        colors: const [
                          Color(0xFF0D0D2B),
                          Color(0xFF1A0A2E),
                          Color(0xFF0A1A2E),
                          Color(0xFF0D1B2A),
                        ],
                      ),
                    ),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.3),
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Pulsa botón para continuar',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KenBurnsImage extends StatelessWidget {
  final String url;
  final AnimationController controller;

  const _KenBurnsImage({
    super.key,
    required this.url,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final scale = 1.0 + controller.value * 0.15;
        final dx = (controller.value - 0.5) * 0.04;
        final dy = (1 - controller.value - 0.5) * 0.03;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(scale, scale, scale)
            ..multiply(Matrix4.translationValues(dx * 400, dy * 400, 0.0)),
          child: child,
        );
      },
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorWidget: (_, _, _) => const SizedBox(),
      ),
    );
  }
}
