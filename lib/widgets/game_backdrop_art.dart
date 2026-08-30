import 'package:flutter/material.dart';

import '../models/nv_app.dart';
import '../services/metadata/game_art_policy.dart';
import '../services/metadata/game_art_validator.dart';
import '../ui/motion_scope.dart';
import 'poster_image.dart';
import 'premium_game_backdrop.dart';

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
  final Widget Function(
    BuildContext context,
    GameBackdropSelection selection,
    Widget hero,
  )?
  heroBuilder;

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncKenBurns();
  }

  @override
  void didUpdateWidget(covariant GameBackdropArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.appId != widget.app.appId ||
        oldWidget.app.appName != widget.app.appName ||
        oldWidget.app.heroImageUrl != widget.app.heroImageUrl ||
        oldWidget.app.steamBackgroundUrl != widget.app.steamBackgroundUrl ||
        oldWidget.app.rawgBackgroundUrl != widget.app.rawgBackgroundUrl ||
        oldWidget.validateHeroDimensions != widget.validateHeroDimensions) {
      _requestedViewport = Size.zero;
      // Keep the last accepted layer visible while the replacement is probed.
      // This avoids the empty/poster flash seen during fast D-pad navigation.
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
    final allowed =
        widget.enableKenBurns && MotionScope.read(context).allowBackdropMotion;
    if (allowed) {
      if (_kenBurnsController.isAnimating) return;
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
    if (candidates.isEmpty) {
      _resolvedHero = null;
      _heroProbe = null;
      return;
    }
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
    if (candidates.isEmpty) {
      if (mounted) {
        setState(() {
          _resolvedHero = null;
          _heroProbe = null;
        });
      }
      return;
    }
    if (!widget.validateHeroDimensions) {
      _resolvedHero = candidates.first;
      _heroProbe = const GameHeroProbe(width: 1920, height: 1080);
      return;
    }
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
    final selection =
        _resolvedHero ??
        const GameBackdropSelection(role: GameBackdropRole.none);
    final child = switch (selection.role) {
      GameBackdropRole.hero when _heroProbe?.isEligible == true => _buildHero(
        selection,
      ),
      GameBackdropRole.hero => _premiumFallback(),
      GameBackdropRole.poster => _premiumFallback(),
      GameBackdropRole.none => _premiumFallback(),
    };
    final backdrop = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: child,
    );
    final animateHero =
        widget.enableKenBurns &&
        MotionScope.of(context).allowBackdropMotion &&
        selection.hasArt;
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
      errorWidget: (_, _, _) => _premiumFallback(),
    );
    final decorated =
        widget.heroBuilder?.call(context, selection, hero) ?? hero;
    return KeyedSubtree(
      key: ValueKey('hero-layer-${selection.cacheKey ?? selection.url}'),
      child: decorated,
    );
  }

  Widget _premiumFallback() {
    return PremiumGameBackdrop(
      key: ValueKey(
        'premium-backdrop-${widget.app.appId}-${widget.app.appName}',
      ),
      title: widget.app.appName,
      baseColor: widget.fallbackColor,
    );
  }
}
