import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../models/nv_app.dart';
import '../services/metadata/game_art_policy.dart';
import '../services/metadata/game_art_validator.dart';
import '../services/tv/tv_detector.dart';
import 'poster_image.dart';

class GameBackdropArt extends StatefulWidget {
  const GameBackdropArt({
    super.key,
    required this.app,
    this.heroCacheWidth = 1920,
    this.fallbackColor = const Color(0xFF07111C),
    this.validateHeroDimensions = true,
    this.enableKenBurns = false,
    this.heroBuilder,
  });

  final NvApp app;
  final int heroCacheWidth;
  final Color fallbackColor;
  final bool validateHeroDimensions;
  final bool enableKenBurns;

  /// Ken Burns pans and scales the full-screen backdrop forever. The four
  /// launcher themes that enable it only check the opt-in reduceEffects /
  /// performanceMode flags, which default to false — so on a TV box it ran
  /// permanently unless the user found the setting. The default Classic view
  /// already gates its own background motion on `!isTV`; this applies the same
  /// rule for every theme at once, instead of at each of the four call sites.
  bool get _kenBurnsAllowed => enableKenBurns && !TvDetector.instance.isTV;
  final Widget Function(BuildContext context, Widget hero)? heroBuilder;

  @override
  State<GameBackdropArt> createState() => _GameBackdropArtState();
}

class _GameBackdropArtState extends State<GameBackdropArt>
    with SingleTickerProviderStateMixin {
  GameBackdropSelection? _resolvedHero;
  GameHeroProbe? _heroProbe;
  Size _requestedViewport = Size.zero;
  bool _validationScheduled = false;
  int _validationGeneration = 0;
  late final AnimationController _kenBurnsController;
  late final Animation<double> _kenBurnsScale;
  late final Animation<Offset> _kenBurnsDrift;

  @override
  void initState() {
    super.initState();
    _kenBurnsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    );
    final curve = CurvedAnimation(
      parent: _kenBurnsController,
      curve: Curves.easeInOut,
    );
    _kenBurnsScale = Tween<double>(begin: 1.0, end: 1.025).animate(curve);
    _kenBurnsDrift = Tween<Offset>(
      begin: const Offset(-3, -1),
      end: const Offset(3, 2),
    ).animate(curve);
    _primeUnvalidatedHero();
    _syncKenBurns();
  }

  @override
  void didUpdateWidget(covariant GameBackdropArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.heroImageUrl != widget.app.heroImageUrl ||
        oldWidget.app.steamBackgroundUrl != widget.app.steamBackgroundUrl ||
        oldWidget.app.rawgBackgroundUrl != widget.app.rawgBackgroundUrl ||
        oldWidget.validateHeroDimensions != widget.validateHeroDimensions) {
      _requestedViewport = Size.zero;
      _resolvedHero = null;
      _heroProbe = null;
      _primeUnvalidatedHero();
      _scheduleValidationForViewport(
        MediaQuery.maybeSizeOf(context) ?? Size.zero,
      );
    }
    if (oldWidget.enableKenBurns != widget.enableKenBurns) {
      _syncKenBurns();
    }
  }

  @override
  void dispose() {
    _kenBurnsController.dispose();
    super.dispose();
  }

  void _syncKenBurns() {
    if (widget._kenBurnsAllowed) {
      _kenBurnsController.repeat(reverse: true);
    } else {
      _kenBurnsController
        ..stop()
        ..reset();
    }
  }

  void _primeUnvalidatedHero() {
    if (widget.validateHeroDimensions) return;
    final candidates = GameArtPolicy.heroCandidates(widget.app);
    if (candidates.isEmpty) return;
    _resolvedHero = candidates.first;
    _heroProbe = const GameHeroProbe(width: 1920, height: 1080);
  }

  void _scheduleValidationForViewport(Size viewport) {
    if (viewport.isEmpty ||
        ((_requestedViewport.width - viewport.width).abs() < 1 &&
            (_requestedViewport.height - viewport.height).abs() < 1) ||
        _validationScheduled) {
      return;
    }
    _requestedViewport = viewport;
    _validationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _validationScheduled = false;
      if (mounted) _validateHero(viewport);
    });
  }

  void _validateHero(Size viewport) {
    final generation = ++_validationGeneration;
    final candidates = GameArtPolicy.heroCandidates(widget.app);
    _resolvedHero = null;
    if (candidates.isEmpty) {
      _heroProbe = null;
      return;
    }
    if (!widget.validateHeroDimensions) {
      _resolvedHero = candidates.first;
      _heroProbe = const GameHeroProbe(width: 1920, height: 1080);
      return;
    }
    _heroProbe = null;
    () async {
      GameBackdropSelection? bestCandidate;
      GameHeroProbe? bestProbe;
      var bestRetainedFraction = 0.0;
      for (final candidate in candidates) {
        final probe = await GameArtValidator.probeHero(
          candidate.url!,
          cacheKey: candidate.cacheKey,
        );
        if (!mounted || generation != _validationGeneration) return;
        if (!probe.isEligibleFor(
          viewportWidth: viewport.width,
          viewportHeight: viewport.height,
        )) {
          continue;
        }
        final retained = probe.retainedFractionFor(
          viewportWidth: viewport.width,
          viewportHeight: viewport.height,
        );
        // Candidate order is the quality preference. A later source replaces
        // it only when it preserves materially more of its composition.
        if (bestCandidate == null || retained > bestRetainedFraction + 0.02) {
          bestCandidate = candidate;
          bestProbe = probe;
          bestRetainedFraction = retained;
        }
      }
      if (mounted && generation == _validationGeneration) {
        setState(() {
          _resolvedHero = bestCandidate;
          _heroProbe = bestProbe;
        });
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport =
            constraints.hasBoundedWidth && constraints.hasBoundedHeight
            ? constraints.biggest
            : MediaQuery.sizeOf(context);
        _scheduleValidationForViewport(viewport);
        return _buildBackdrop();
      },
    );
  }

  Widget _buildBackdrop() {
    final selection = _resolvedHero ?? GameArtPolicy.posterFallback(widget.app);
    final child = switch (selection.role) {
      GameBackdropRole.hero when _heroProbe?.isEligible == true => _buildHero(
        selection,
      ),
      GameBackdropRole.hero => _posterOrEmpty(),
      GameBackdropRole.poster => _buildFullBleed(
        selection.url!,
        selection.cacheKey,
        key: const Key('game-backdrop-poster'),
      ),
      GameBackdropRole.none => ColoredBox(
        key: const Key('game-backdrop-empty'),
        color: widget.fallbackColor,
      ),
    };
    final backdrop = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: child,
    );
    final animateHero =
        widget._kenBurnsAllowed &&
        (selection.hasArt ||
            (widget.app.posterUrl?.trim().isNotEmpty ?? false));
    if (!animateHero) return backdrop;
    return AnimatedBuilder(
      key: const Key('game-backdrop-ken-burns'),
      animation: _kenBurnsController,
      child: backdrop,
      builder: (_, child) => Transform.translate(
        offset: _kenBurnsDrift.value,
        child: Transform.scale(scale: _kenBurnsScale.value, child: child),
      ),
    );
  }

  Widget _buildHero(GameBackdropSelection selection) {
    final hero = PosterImage(
      key: const Key('game-backdrop-hero'),
      url: selection.url!,
      cacheKey: selection.cacheKey,
      fit: BoxFit.cover,
      alignment: Alignment.center,
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
    return _buildFullBleed(
      poster,
      widget.app.artCacheKey('poster'),
      key: const Key('game-backdrop-poster'),
    );
  }

  Widget _buildFullBleed(String url, String? cacheKey, {required Key key}) {
    final composition = ColoredBox(
      color: widget.fallbackColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Transform.scale(
                scale: 1.08,
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.58),
                    BlendMode.darken,
                  ),
                  child: PosterImage(
                    key: const Key('game-backdrop-poster-blur'),
                    url: url,
                    cacheKey: cacheKey,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    memCacheWidth: widget.heroCacheWidth,
                    errorWidget: (_, _, _) =>
                        ColoredBox(color: widget.fallbackColor),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 72, vertical: 48),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: PosterImage(
                  key: key,
                  url: url,
                  cacheKey: cacheKey,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  width: double.infinity,
                  height: double.infinity,
                  memCacheWidth: widget.heroCacheWidth,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return widget.heroBuilder?.call(context, composition) ?? composition;
  }
}
