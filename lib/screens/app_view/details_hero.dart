import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../services/metadata/steam_video_client.dart';

/// Full page with a quick fade (no slide), so the art reads as the same title
/// expanding rather than a new screen arriving.
Route<T> detailsPageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: child,
    ),
  );
}

/// Muted, looping trailer that takes over the detail page backdrop once it
/// can play, the way streaming apps do. Until then (or if it fails) the
/// artwork underneath stays visible, so nothing pops.
///
/// Sound stays off on purpose: audio that starts by itself on a browse action
/// is an intrusion. The full trailer, with sound, is one press away.
class DetailsBackdropTrailer extends StatefulWidget {
  final List<SteamMovie> movies;

  const DetailsBackdropTrailer({super.key, required this.movies});

  @override
  State<DetailsBackdropTrailer> createState() => _DetailsBackdropTrailerState();
}

class _DetailsBackdropTrailerState extends State<DetailsBackdropTrailer> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant DetailsBackdropTrailer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller == null) _start();
  }

  void _start() {
    final url = widget.movies.isEmpty ? null : widget.movies.first.bestUrl;
    if (url == null) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = c;
    c
        .initialize()
        .then((_) async {
          if (!mounted || _controller != c) return;
          await c.setVolume(0);
          await c.setLooping(true);
          await c.play();
          if (mounted) setState(() => _ready = true);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return AnimatedOpacity(
      opacity: _ready ? 1 : 0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      child: (c != null && c.value.isInitialized)
          ? FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: c.value.size.width,
                height: c.value.size.height,
                child: VideoPlayer(c),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// Focus + tap + Enter/A handling shared by the detail page controls. The
/// builder gets the focus state so each control draws its own focus look.
class DetailsTappable extends StatefulWidget {
  final VoidCallback? onTap;
  final bool autofocus;
  final String? semanticLabel;
  final Widget Function(BuildContext context, bool focused) builder;

  const DetailsTappable({
    super.key,
    required this.onTap,
    required this.builder,
    this.autofocus = false,
    this.semanticLabel,
  });

  @override
  State<DetailsTappable> createState() => _DetailsTappableState();
}

class _DetailsTappableState extends State<DetailsTappable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: widget.semanticLabel,
      child: Focus(
        autofocus: widget.autofocus,
        canRequestFocus: widget.onTap != null,
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
          if (widget.onTap == null || event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          final k = event.logicalKey;
          if (k == LogicalKeyboardKey.enter ||
              k == LogicalKeyboardKey.select ||
              k == LogicalKeyboardKey.gameButtonA) {
            widget.onTap!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: widget.builder(context, _focused),
        ),
      ),
    );
  }
}

/// The white pill that leads the page: Play / Resume.
class DetailsPlayPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const DetailsPlayPill({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DetailsTappable(
      onTap: onTap,
      autofocus: true,
      semanticLabel: label,
      builder: (context, focused) => AnimatedScale(
        scale: focused ? 1.03 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 50,
          decoration: BoxDecoration(
            color: focused ? Colors.white : const Color(0xF2FFFFFF),
            borderRadius: BorderRadius.circular(25),
            boxShadow: focused
                ? const [
                    BoxShadow(
                      color: Color(0x66FFFFFF),
                      blurRadius: 22,
                      spreadRadius: -4,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.play_arrow_rounded,
                color: Colors.black,
                size: 26,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round secondary action next to the play pill (favourite, trailer, more).
class DetailsCircleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? activeColor;

  const DetailsCircleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: DetailsTappable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: focused ? Colors.white : const Color(0x2EFFFFFF),
            border: Border.all(color: const Color(0x1FFFFFFF)),
          ),
          child: Icon(
            icon,
            size: 22,
            color: focused ? Colors.black : (activeColor ?? Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Section heading + content, left-aligned with the hero column.
class DetailsSection extends StatelessWidget {
  final String title;
  final Widget child;

  const DetailsSection({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// 16:9 media tile for the Media row (trailer or screenshot).
class DetailsMediaCard extends StatelessWidget {
  final Widget image;
  final String? caption;
  final bool isVideo;
  final VoidCallback onTap;

  const DetailsMediaCard({
    super.key,
    required this.image,
    required this.onTap,
    this.caption,
    this.isVideo = false,
  });

  @override
  Widget build(BuildContext context) {
    return DetailsTappable(
      onTap: onTap,
      semanticLabel: caption,
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 240,
        height: 135,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: focused ? Colors.white : const Color(0x24FFFFFF),
            width: focused ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xFF141B26)),
              image,
              if (isVideo || caption != null)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(0, 0.1),
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                    ),
                  ),
                ),
              if (isVideo)
                const Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    size: 40,
                    color: Color(0xE6FFFFFF),
                  ),
                ),
              if (caption != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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

/// Label-over-value fact, laid out inline (no card around it).
class DetailsFact extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const DetailsFact({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 260),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0x8CFFFFFF),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
