part of 'app_view_screen.dart';

class _AppCard extends StatefulWidget {
  final NvApp app;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _AppCard({
    required this.app,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<_AppCard>
    with SingleTickerProviderStateMixin {
  AppThemeColors get _tp => context.read<ThemeProvider>().colors;

  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(
      begin: 0.35,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.app.isRunning;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: _GlowContainer(
        animation: _glowAnim,
        running: running,
        child: _cardContent(running),
      ),
    );
  }

  Widget _cardContent(bool running) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.app.posterUrl != null
                  ? Hero(
                      tag: 'game-poster-${widget.app.appId}',
                      child: PosterImage(
                        url: widget.app.posterUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 400,
                        placeholder: (_, _) => _placeholder(),
                        errorWidget: (_, _, _) => _placeholder(),
                      ),
                    )
                  : _placeholder(),

              if (AppOverrideService.instance.hasOverrides(
                widget.app.serverUuid ?? 'default',
                widget.app.appId,
              ))
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.70),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.edit_note,
                      color: Colors.amberAccent,
                      size: 12,
                    ),
                  ),
                ),

              if (running)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.greenAccent.withValues(alpha: 0.7),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_arrow,
                          color: Colors.greenAccent,
                          size: 14,
                        ),
                        SizedBox(width: 3),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            widget.app.appName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _placeholder() => Container(
    color: _tp.secondary,
    child: const Center(
      child: Icon(Icons.gamepad, size: 40, color: Colors.white24),
    ),
  );
}

class _GlowContainer extends StatelessWidget {
  final Animation<double> animation;
  final bool running;
  final Widget child;

  const _GlowContainer({
    required this.animation,
    required this.running,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>().colors;
    if (!running) {
      return Container(
        decoration: BoxDecoration(
          color: tp.surface,
          borderRadius: BorderRadius.circular(6),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (_, _) {
        final glow = animation.value;
        return Container(
          decoration: BoxDecoration(
            color: tp.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.greenAccent.withValues(alpha: glow * 0.8),
              width: 2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
      },
    );
  }
}

class _SkeletonCard extends StatefulWidget {
  final Duration delay;
  const _SkeletonCard({this.delay = Duration.zero});

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulse = Tween<double>(
      begin: 0.04,
      end: 0.10,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        return Container(
          width: 120,
          height: 170,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _pulse.value),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                height: 12,
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Container(
                height: 8,
                margin: const EdgeInsets.fromLTRB(10, 0, 30, 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
