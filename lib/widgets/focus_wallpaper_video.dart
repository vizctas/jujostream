import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Plays bundled or user-selected MP4 wallpaper silently and loops it.
class FocusWallpaperVideo extends StatefulWidget {
  final String? filePath;
  final String? assetPath;
  final Color fallbackColor;

  const FocusWallpaperVideo({
    super.key,
    this.filePath,
    this.assetPath,
    required this.fallbackColor,
  });

  @override
  State<FocusWallpaperVideo> createState() => _FocusWallpaperVideoState();
}

class _FocusWallpaperVideoState extends State<FocusWallpaperVideo> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant FocusWallpaperVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.assetPath != widget.assetPath) {
      _controller?.dispose();
      _controller = null;
      _start();
    }
  }

  Future<void> _start() async {
    final path = widget.filePath ?? widget.assetPath;
    if (path == null || !path.toLowerCase().endsWith('.mp4')) return;
    final c = widget.filePath != null
        ? VideoPlayerController.file(io.File(widget.filePath!))
        : VideoPlayerController.asset(path);
    _controller = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (mounted && identical(_controller, c)) setState(() {});
    } catch (e) {
      debugPrint('[FocusWallpaperVideo] $e');
      await c.dispose();
      if (mounted && identical(_controller, c)) {
        setState(() => _controller = null);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return ColoredBox(color: widget.fallbackColor);
    }
    return ColoredBox(
      color: widget.fallbackColor,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: c.value.size.width,
            height: c.value.size.height,
            child: VideoPlayer(c),
          ),
        ),
      ),
    );
  }
}
