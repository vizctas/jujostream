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
  final Widget Function(BuildContext context, Widget hero)? heroBuilder;

  @override
  State<GameBackdropArt> createState() => _GameBackdropArtState();
}

class _GameBackdropArtState extends State<GameBackdropArt>
    with SingleTickerProviderStateMixin {
  bool? _heroEligible;
  int _validationGeneration = 0;
  late final AnimationController _kenBurnsController;
  late final Animation<double> _kenBurnsScale;
  late final Animation<Offset> _kenBurnsDrift;

  @override
  void initState() {
    super.initState();
    _kenBurnsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
    final curve = CurvedAnimation(
      parent: _kenBurnsController,
      curve: Curves.easeInOut,
    );
    _kenBurnsScale = Tween<double>(begin: 1.02, end: 1.08).animate(curve);
    _kenBurnsDrift = Tween<Offset>(
      begin: const Offset(-8, -3),
      end: const Offset(8, 5),
    ).animate(curve);
    _syncKenBurns();
    _validateHero();
  }

  @override
  void didUpdateWidget(covariant GameBackdropArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.heroImageUrl != widget.app.heroImageUrl ||
        oldWidget.app.steamBackgroundUrl != widget.app.steamBackgroundUrl ||
        oldWidget.app.rawgBackgroundUrl != widget.app.rawgBackgroundUrl ||
        oldWidget.validateHeroDimensions != widget.validateHeroDimensions) {
      _validateHero();
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
    if (widget.enableKenBurns) {
      _kenBurnsController.repeat(reverse: true);
    } else {
      _kenBurnsController
        ..stop()
        ..reset();
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
    if (!widget.enableKenBurns) return backdrop;
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
    final background = PosterImage(
      key: key,
      url: url,
      cacheKey: cacheKey,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: widget.heroCacheWidth,
      errorWidget: (_, _, _) => ColoredBox(color: widget.fallbackColor),
    );
    return widget.heroBuilder?.call(context, background) ?? background;
  }
}
