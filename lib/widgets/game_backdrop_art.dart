import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/nv_app.dart';
import '../services/metadata/game_art_policy.dart';
import '../services/metadata/game_art_validator.dart';
import 'poster_image.dart';

class GameBackdropArt extends StatefulWidget {
  const GameBackdropArt({
    super.key,
    required this.app,
    this.heroCacheWidth = 1920,
    this.posterCacheWidth = 720,
    this.posterAlignment = Alignment.centerRight,
    this.posterWidthFactor = 0.38,
    this.posterHeightFactor = 0.82,
    this.fallbackColor = const Color(0xFF07111C),
    this.validateHeroDimensions = true,
    this.heroBuilder,
  });

  final NvApp app;
  final int heroCacheWidth;
  final int posterCacheWidth;
  final Alignment posterAlignment;
  final double posterWidthFactor;
  final double posterHeightFactor;
  final Color fallbackColor;
  final bool validateHeroDimensions;
  final Widget Function(BuildContext context, Widget hero)? heroBuilder;

  @override
  State<GameBackdropArt> createState() => _GameBackdropArtState();
}

class _GameBackdropArtState extends State<GameBackdropArt> {
  bool? _heroEligible;
  int _validationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _validateHero();
  }

  @override
  void didUpdateWidget(covariant GameBackdropArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.heroImageUrl != widget.app.heroImageUrl ||
        oldWidget.app.rawgBackgroundUrl != widget.app.rawgBackgroundUrl ||
        oldWidget.validateHeroDimensions != widget.validateHeroDimensions) {
      _validateHero();
    }
  }

  void _validateHero() {
    final generation = ++_validationGeneration;
    final selection = GameArtPolicy.selectBackdrop(widget.app);
    if (selection.role != GameBackdropRole.hero) {
      _heroEligible = null;
      return;
    }
    if (!widget.validateHeroDimensions) {
      _heroEligible = true;
      return;
    }
    _heroEligible = null;
    GameArtValidator.isEligibleHero(
      selection.url!,
      cacheKey: selection.cacheKey,
    ).then((eligible) {
      if (mounted && generation == _validationGeneration) {
        setState(() => _heroEligible = eligible);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selection = GameArtPolicy.selectBackdrop(widget.app);
    final child = switch (selection.role) {
      GameBackdropRole.hero when _heroEligible == true => _buildHero(selection),
      GameBackdropRole.hero => _posterOrEmpty(),
      GameBackdropRole.poster => _posterComposition(
        selection.url!,
        selection.cacheKey,
      ),
      GameBackdropRole.none => ColoredBox(
        key: const Key('game-backdrop-empty'),
        color: widget.fallbackColor,
      ),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: child,
    );
  }

  Widget _buildHero(GameBackdropSelection selection) {
    final hero = PosterImage(
      key: const Key('game-backdrop-hero'),
      url: selection.url!,
      cacheKey: selection.cacheKey,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: widget.heroCacheWidth,
      errorWidget: (_, _, _) => _posterOrEmpty(),
    );
    return widget.heroBuilder?.call(context, hero) ?? hero;
  }

  Widget _posterOrEmpty() {
    final poster = widget.app.posterUrl?.trim();
    if (poster == null || poster.isEmpty) {
      return ColoredBox(
        key: const Key('game-backdrop-empty'),
        color: widget.fallbackColor,
      );
    }
    return _posterComposition(poster, widget.app.artCacheKey('poster'));
  }

  Widget _posterComposition(String url, String? cacheKey) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          key: const Key('game-backdrop-poster-blur'),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Transform.scale(
              scale: 1.12,
              child: PosterImage(
                url: url,
                cacheKey: cacheKey,
                fit: BoxFit.cover,
                memCacheWidth: widget.posterCacheWidth,
                errorWidget: (_, _, _) =>
                    ColoredBox(color: widget.fallbackColor),
              ),
            ),
          ),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: 0.42)),
        Align(
          alignment: widget.posterAlignment,
          child: FractionallySizedBox(
            widthFactor: widget.posterWidthFactor,
            heightFactor: widget.posterHeightFactor,
            child: Center(
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x99000000),
                        blurRadius: 32,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: PosterImage(
                      key: const Key('game-backdrop-poster'),
                      url: url,
                      cacheKey: cacheKey,
                      fit: BoxFit.contain,
                      memCacheWidth: widget.posterCacheWidth,
                      errorWidget: (_, _, _) =>
                          ColoredBox(color: widget.fallbackColor),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
