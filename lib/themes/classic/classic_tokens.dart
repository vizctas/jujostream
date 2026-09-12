import 'package:flutter/material.dart';

import '../../models/theme_config.dart';

/// Design tokens for the Classic launcher on 16:9 screens. Every value is
/// documented in MASTER.md at the project root; change it there first.
class ClassicTokens {
  const ClassicTokens._();

  // Spacing (8 px grid).
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;
  static const double s64 = 64;

  static const double tvMarginX = 64;
  static const double tvMarginY = 40;
  static const double railWidth = 64;
  static const double readingColumnMaxWidth = 640;
  static const double readingColumnFraction = 0.46;
  static const double cinematicMinWidth = 960;
  static const double compactHeight = 700;
  static const int maxChips = 4;
  static const double chipHeight = 28;

  // Radii.
  static const double radiusChip = 8;
  static const double radiusCard = 10;
  static const double radiusDialog = 16;
  static const double radiusFull = 999;

  // Focus ring.
  static const double focusRingWidth = 3;
  static const double focusRingGap = 2;
  static const double focusScale = 1.06;

  // Motion.
  static const Curve curve = Cubic(0.2, 0, 0, 1);
  static const Duration focus = Duration(milliseconds: 130);
  static const Duration backdrop = Duration(milliseconds: 220);
  static const Duration dialogIn = Duration(milliseconds: 250);
  static const Duration dialogOut = Duration(milliseconds: 180);
  static const double dialogSlide = 12;

  // Backdrop legibility bands (fractions of the screen) and their alphas.
  static const double leftBandWidth = 0.8;
  static const double leftBandMidStop = 0.56;
  static const double leftBandAlphaStart = 0.92;
  static const double leftBandAlphaMid = 0.55;
  static const double bottomBandHeight = 0.5;
  static const double bottomBandAlpha = 0.9;
  static const double dialogArtFadeStart = 0.35;
  static const double hintIconSize = 18;

  // Dialog.
  static const double dialogWidthFraction = 0.62;
  static const double dialogMaxWidth = 880;
  static const double scrimAlpha = 0.72;
  static const double dialogArtAspect = 21 / 9;
  static const double dialogArtAspectCompact = 4;
  static const int dialogArtCacheWidth = 1280;

  // Fixed whites.
  static const Color text = Colors.white;
  static const Color textMuted = Color(0xB8FFFFFF);
  static const Color textFaint = Color(0x7AFFFFFF);
  static const Color line = Color(0x29FFFFFF);
  static const Color success = Color(0xFF34D399);
  static const Color danger = Color(0xFFF87171);

  // Typography (system sans).
  static const TextStyle display = TextStyle(
    color: text,
    fontSize: 56,
    fontWeight: FontWeight.w700,
    letterSpacing: -1,
    height: 1.05,
  );

  /// Landscape screens under [compactHeight] (phone/desktop windows).
  static const TextStyle displayCompact = TextStyle(
    color: text,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.1,
  );
  static const TextStyle bodyCompact = TextStyle(
    color: textMuted,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );
  static const TextStyle metaCompact = TextStyle(
    color: textMuted,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );
  static const int descriptionLines = 3;
  static const int descriptionLinesCompact = 2;
  static const TextStyle dialogTitle = TextStyle(
    color: text,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.1,
  );
  static const TextStyle body = TextStyle(
    color: textMuted,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );
  static const TextStyle meta = TextStyle(
    color: textMuted,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );
  static const TextStyle label = TextStyle(
    color: textFaint,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
  );
  static const TextStyle chip = TextStyle(
    color: text,
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle stat = TextStyle(
    color: text,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );
  static const TextStyle button = TextStyle(
    color: text,
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

  /// Theme-dependent colors come from the active preset so other color
  /// presets keep working; only the whites above are fixed.
  static Color bg(AppThemeColors c) => c.background;
  static Color surface(AppThemeColors c) => c.surface;
  static Color surfaceVariant(AppThemeColors c) => c.surfaceVariant;
  static Color accent(AppThemeColors c) => c.accent;
  static Color accentLight(AppThemeColors c) => c.accentLight;
}
