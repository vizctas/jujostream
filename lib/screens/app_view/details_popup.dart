import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/metadata/steam_video_client.dart';

/// Muted, looping trailer shown at the top of the game-detail popup.
///
/// Sound stays off on purpose: the popup opens over the launcher, and audio
/// that starts by itself on a browse action is an intrusion. The full trailer
/// (with sound) is still one press away through the trailer button.
class DetailsPopupTrailer extends StatefulWidget {
  final List<SteamMovie> movies;

  const DetailsPopupTrailer({super.key, required this.movies});

  @override
  State<DetailsPopupTrailer> createState() => _DetailsPopupTrailerState();
}

class _DetailsPopupTrailerState extends State<DetailsPopupTrailer> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant DetailsPopupTrailer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller == null && widget.movies.isNotEmpty) _start();
  }

  void _start() {
    if (widget.movies.isEmpty) return;
    final url = widget.movies.first.bestUrl;
    if (url == null) {
      setState(() => _failed = true);
      return;
    }
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
        .catchError((_) {
          if (mounted) setState(() => _failed = true);
        });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || widget.movies.isEmpty) return const SizedBox.shrink();
    final thumb = widget.movies.first.thumbnail;
    final c = _controller;
    // Half the viewport at most: on a landscape phone a full-width 16:9
    // trailer would fill the whole popup and push the game info off screen.
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.5,
        ),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xFF0B1624)),
                if (thumb != null)
                  Image.network(
                    thumb,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                AnimatedOpacity(
                  opacity: _ready ? 1 : 0,
                  duration: const Duration(milliseconds: 280),
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
                ),
                const Positioned(
                  right: 10,
                  bottom: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0x99000000),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.volume_off_rounded,
                        size: 16,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Frames a route's page as a centred card so the launcher stays visible,
/// dimmed, around it. Sized to the viewport so it also fits a 891x411 phone
/// held in landscape.
class DetailsPopupFrame extends StatelessWidget {
  final Widget child;

  const DetailsPopupFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final maxW = (size.width - pad.horizontal - 32).clamp(280.0, 980.0);
    final maxH = (size.height - pad.vertical - 24).clamp(240.0, 900.0);
    return Padding(
      padding: pad,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x1FFFFFFF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 40,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                removeBottom: true,
                removeLeft: true,
                removeRight: true,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Transparent route that opens [page] as a popup over the current screen.
Route<T> detailsPopupRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    opaque: false,
    barrierDismissible: true,
    barrierLabel: 'details',
    barrierColor: const Color(0xA6000000),
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => DetailsPopupFrame(child: page),
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
