import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/computer_provider.dart';
import '../providers/theme_provider.dart';
import '../ui/motion_scope.dart';
import '../ui/adaptive_motion.dart';

class NowPlayingBanner extends StatefulWidget {
  final VoidCallback? onTap;

  const NowPlayingBanner({super.key, this.onTap});

  @override
  State<NowPlayingBanner> createState() => _NowPlayingBannerState();
}

class _NowPlayingBannerState extends State<NowPlayingBanner> {
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final start = context.read<ComputerProvider>().activeSessionStart;
      if (start != null && mounted) {
        setState(() => _elapsed = DateTime.now().difference(start));
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ComputerProvider>();
    final app = provider.activeSessionApp;
    if (app == null) return const SizedBox.shrink();

    final start = provider.activeSessionStart;
    if (start != null) {
      _elapsed = DateTime.now().difference(start);
    }

    final tp = context.read<ThemeProvider>().colors;

    // Tap-only left this unreachable by D-pad, on a screen that is the default
    // home on TV — the remote skipped straight past the resume affordance.
    return _FocusableBanner(
      onActivate: widget.onTap,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: tp.surface,
            border: Border(
              top: BorderSide(
                color: tp.accent.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              _PulsingDot(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      app.appName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Playing · ${_formatElapsed(_elapsed)}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MotionScope.of(context).allowContinuousEffects) {
      if (!_ctrl.isAnimating) _ctrl.repeat(reverse: true);
    } else {
      _ctrl
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFF4CAF50),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Wraps the banner so a D-pad or keyboard can reach and activate it, and
/// shows a visible focus ring — a tap target with no focus node is invisible
/// to a TV remote.
class _FocusableBanner extends StatefulWidget {
  const _FocusableBanner({required this.child, this.onActivate});

  final Widget child;
  final VoidCallback? onActivate;

  @override
  State<_FocusableBanner> createState() => _FocusableBannerState();
}

class _FocusableBannerState extends State<_FocusableBanner> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = context.read<ThemeProvider>().colors.accent;
    return FocusableActionDetector(
      onShowFocusHighlight: (v) {
        if (v != _focused) setState(() => _focused = v);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onActivate?.call();
            return null;
          },
        ),
      },
      child: AdaptiveFocusSurface(
        focused: _focused,
        child: GestureDetector(
          onTap: widget.onActivate,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: _focused ? accent : Colors.transparent,
                width: 2,
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
