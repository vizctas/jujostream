import 'package:flutter/material.dart';

import '../providers/theme_provider.dart';
import '../services/tv/tv_detector.dart';
import '../themes/launcher_theme.dart';

enum MotionTier { reduced, constrained, standard, premium }

enum MotionPersonality { classic, backbone, ps5, hero, bigScreen }

@immutable
class MotionTokens {
  const MotionTokens({
    required this.focus,
    required this.state,
    required this.overlay,
    required this.route,
    required this.background,
    required this.focusCurve,
    required this.stateCurve,
    required this.enterCurve,
    required this.exitCurve,
  });
  final Duration focus;
  final Duration state;
  final Duration overlay;
  final Duration route;
  final Duration background;
  final Curve focusCurve;
  final Curve stateCurve;
  final Curve enterCurve;
  final Curve exitCurve;

  static const reduced = MotionTokens(
    focus: Duration.zero,
    state: Duration(milliseconds: 80),
    overlay: Duration(milliseconds: 100),
    route: Duration(milliseconds: 120),
    background: Duration(milliseconds: 100),
    focusCurve: Curves.linear,
    stateCurve: Curves.linear,
    enterCurve: Curves.linear,
    exitCurve: Curves.linear,
  );
  static const constrained = MotionTokens(
    focus: Duration(milliseconds: 100),
    state: Duration(milliseconds: 120),
    overlay: Duration(milliseconds: 180),
    route: Duration(milliseconds: 220),
    background: Duration(milliseconds: 180),
    focusCurve: Curves.easeOutCubic,
    stateCurve: Curves.easeInOutCubic,
    enterCurve: Curves.easeOutCubic,
    exitCurve: Curves.easeInCubic,
  );
  static const standard = MotionTokens(
    focus: Duration(milliseconds: 130),
    state: Duration(milliseconds: 150),
    overlay: Duration(milliseconds: 220),
    route: Duration(milliseconds: 280),
    background: Duration(milliseconds: 260),
    focusCurve: Curves.easeOutCubic,
    stateCurve: Curves.easeInOutCubic,
    enterCurve: Curves.easeOutCubic,
    exitCurve: Curves.easeInCubic,
  );
  static const premium = MotionTokens(
    focus: Duration(milliseconds: 160),
    state: Duration(milliseconds: 180),
    overlay: Duration(milliseconds: 260),
    route: Duration(milliseconds: 320),
    background: Duration(milliseconds: 300),
    focusCurve: Curves.easeOutCubic,
    stateCurve: Curves.easeInOutCubic,
    enterCurve: Curves.easeOutCubic,
    exitCurve: Curves.easeInCubic,
  );

  static MotionTokens forTier(MotionTier tier) => switch (tier) {
    MotionTier.reduced => reduced,
    MotionTier.constrained => constrained,
    MotionTier.standard => standard,
    MotionTier.premium => premium,
  };
}

@immutable
class LauncherMotionProfile {
  const LauncherMotionProfile({
    required this.personality,
    required this.focusScale,
    required this.focusTravel,
    required this.directionalTravel,
    required this.artworkDepth,
  });
  final MotionPersonality personality;
  final double focusScale;
  final double focusTravel;
  final double directionalTravel;
  final bool artworkDepth;

  static LauncherMotionProfile forTheme(LauncherThemeId id) => switch (id) {
    LauncherThemeId.classic => const LauncherMotionProfile(
      personality: MotionPersonality.classic,
      focusScale: 1.015,
      focusTravel: 0,
      directionalTravel: 0,
      artworkDepth: false,
    ),
    LauncherThemeId.backbone => const LauncherMotionProfile(
      personality: MotionPersonality.backbone,
      focusScale: 1.018,
      focusTravel: 3,
      directionalTravel: 4,
      artworkDepth: false,
    ),
    LauncherThemeId.ps5 => const LauncherMotionProfile(
      personality: MotionPersonality.ps5,
      focusScale: 1.02,
      focusTravel: 2,
      directionalTravel: 10,
      artworkDepth: true,
    ),
    LauncherThemeId.hero => const LauncherMotionProfile(
      personality: MotionPersonality.hero,
      focusScale: 1.02,
      focusTravel: 2,
      directionalTravel: 6,
      artworkDepth: true,
    ),
    LauncherThemeId.bigScreen => const LauncherMotionProfile(
      personality: MotionPersonality.bigScreen,
      focusScale: 1.025,
      focusTravel: 2,
      directionalTravel: 2,
      artworkDepth: false,
    ),
  };
}

@immutable
class MotionPolicy {
  const MotionPolicy({
    required this.reduceMotion,
    required this.performanceMode,
    this.resolvedTier,
    this.profile = const LauncherMotionProfile(
      personality: MotionPersonality.classic,
      focusScale: 1.015,
      focusTravel: 0,
      directionalTravel: 0,
      artworkDepth: false,
    ),
  });

  factory MotionPolicy.fromContext(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    final media = MediaQuery.maybeOf(context);
    final systemReduced =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    final reduce = themeProvider.reduceEffects || systemReduced;
    return MotionPolicy(
      reduceMotion: reduce,
      performanceMode: themeProvider.performanceMode,
      resolvedTier: resolveTier(
        reduceMotion: reduce,
        performanceMode: themeProvider.performanceMode,
        lowRamDevice: TvDetector.instance.isLowRam,
        tvDevice: TvDetector.instance.isTV,
      ),
      profile: LauncherMotionProfile.forTheme(themeProvider.launcherThemeId),
    );
  }

  static MotionTier resolveTier({
    required bool reduceMotion,
    required bool performanceMode,
    required bool lowRamDevice,
    required bool tvDevice,
  }) {
    if (reduceMotion) return MotionTier.reduced;
    if (performanceMode || lowRamDevice) return MotionTier.constrained;
    if (tvDevice) return MotionTier.standard;
    return MotionTier.premium;
  }

  final bool reduceMotion;
  final bool performanceMode;
  final MotionTier? resolvedTier;
  final LauncherMotionProfile profile;

  MotionTier get tier =>
      resolvedTier ??
      (reduceMotion
          ? MotionTier.reduced
          : performanceMode
          ? MotionTier.constrained
          : MotionTier.premium);
  MotionTokens get tokens => MotionTokens.forTier(tier);
  bool get allowContinuousEffects => tier == MotionTier.premium;
  bool get allowBackdropMotion =>
      tier == MotionTier.standard || tier == MotionTier.premium;
  bool get allowFunctionalMarquee => tier != MotionTier.reduced;
  Duration get focusDuration => tokens.focus;
  Duration get microDuration => tokens.state;
  Duration get dialogDuration => tokens.overlay;
  Duration get routeDuration => tokens.route;
  Duration get backgroundDuration => tokens.background;
  Curve get standardCurve => tokens.focusCurve;
  Curve get routeCurve => tokens.stateCurve;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MotionPolicy &&
          other.reduceMotion == reduceMotion &&
          other.performanceMode == performanceMode &&
          other.tier == tier &&
          other.profile.personality == profile.personality;
  @override
  int get hashCode =>
      Object.hash(reduceMotion, performanceMode, tier, profile.personality);
}
