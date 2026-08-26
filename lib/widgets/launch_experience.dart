import 'package:flutter/material.dart';

import '../models/nv_app.dart';
import 'game_backdrop_art.dart';

/// Shared opaque launch composition used before and during transport startup.
/// It deliberately routes every artwork load through GameBackdropArt/PosterImage.
class LaunchExperience extends StatelessWidget {
  const LaunchExperience({
    super.key,
    required this.app,
    required this.computerName,
    required this.message,
    required this.accent,
    this.progress,
  });

  final NvApp app;
  final String computerName;
  final String message;
  final Color accent;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF070510),
      child: Stack(
        fit: StackFit.expand,
        children: [
          GameBackdropArt(
            key: const Key('launch-experience-art'),
            app: app,
            heroCacheWidth: 1920,
          ),
          const ColoredBox(color: Color(0x94000000)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.5, 1],
                colors: [
                  Color(0x22000000),
                  Color(0x44000000),
                  Color(0xF0000000),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 54),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.appName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  computerName,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 22),
                Text(
                  message,
                  key: const Key('launch-experience-message'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 11),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                  ),
                ),
                const SizedBox(height: 34),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
