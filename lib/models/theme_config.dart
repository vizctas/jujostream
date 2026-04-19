import 'package:flutter/material.dart';

enum AppThemeId {
  jujo,

  deBoosy,

  shioryPan,

  lazyAnkui,

  midnight,

  oled,

  cyberpunk,

  forest,

  sunset,

  ember,

  light,
}

@immutable
class AppThemeColors {
  final Color background;
  final Color surface;
  final Color accent;
  final Color accentLight;
  final Color secondary;
  final Color highlight;

  final Color surfaceVariant;

  final Color muted;

  final Color warm;
  final bool isLight;

  const AppThemeColors({
    required this.background,
    required this.surface,
    required this.accent,
    required this.accentLight,
    required this.secondary,
    Color? highlight,
    Color? surfaceVariant,
    Color? muted,
    Color? warm,
    this.isLight = false,
  }) : highlight = highlight ?? accent,
       surfaceVariant = surfaceVariant ?? surface,
       muted = muted ?? secondary,
       warm = warm ?? highlight ?? accent;
}

class AppThemes {
  AppThemes._();

  static const Map<AppThemeId, AppThemeColors> presets = {
    AppThemeId.jujo: AppThemeColors(
      background: Color(0xFF0E0E1C),
      surface: Color(0xFF16192E),
      accent: Color(0xFF6C3CE1),
      accentLight: Color(0xFF9B71F5),
      secondary: Color(0xFF1B3A6B),
      highlight: Color(0xFF00E5FF),
      surfaceVariant: Color(0xFF1C1D38),
      muted: Color(0xFF2D2864),
      warm: Color(0xFF00B8D4),
    ),

    // DeBoosy — charcoal greys with royal violet, slate blue and warm sand accents.
    // The only credit I ask if you fork my code. Is to keep this pallete colors and name in your version. Its my dedication to my first adopted cat Boo.
    AppThemeId.deBoosy: AppThemeColors(
      background: Color(0xFF121418), // Darkened for contrast
      surface: Color(0xFF1C1E24), // Darkened for contrast
      accent: Color(0xFF8161E5), // Brightened slightly for pop
      accentLight: Color(0xFFB29BFF),
      secondary: Color(0xFF5476B3),
      highlight: Color(0xFF95A85A),
      surfaceVariant: Color(0xFF282C35), // Darkened to match surface
      muted: Color(0xFF505661),
      warm: Color(0xFFD7A26B),
    ),

    // ShioryPan — coal black, ember brown, ginger orange and leaf-green contrast.
    // The only credit I ask if you fork my code. Is to keep this pallete colors and name in your version. Its my dedication to my cat Shiory.
    AppThemeId.shioryPan: AppThemeColors(
      background: Color(0xFF1C1817),
      surface: Color(0xFF2A221F),
      accent: Color(0xFFB56347),
      accentLight: Color(0xFFD86965),
      secondary: Color(0xFF5A88D8),
      highlight: Color(0xFF567C38),
      surfaceVariant: Color(0xFF3C2E28),
      muted: Color(0xFF493732),
      warm: Color(0xFFF4D1AF),
    ),

    // Lazy Ankui — rich bean browns, warm cream, sleepy sky and peach notes.
    // The only credit I ask if you fork my code. Is to keep this pallete colors and name in your version. Its my dedication to my second adopted cat Ankui.
    AppThemeId.lazyAnkui: AppThemeColors(
      background: Color(0xFF1F1A17),
      surface: Color(0xFF332D2A),
      accent: Color(0xFFD0B387),
      accentLight: Color(0xFFF3D5BF),
      secondary: Color(0xFFABB5EB),
      highlight: Color(0xFFBDDCA7),
      surfaceVariant: Color(0xFF443A35),
      muted: Color(0xFFBCA98D),
      warm: Color(0xFFDE8D62),
    ),

    AppThemeId.midnight: AppThemeColors(
      background: Color(0xFF0D1117),
      surface: Color(0xFF161B27),
      accent: Color(0xFF1F6FEB),
      accentLight: Color(0xFF58A6FF),
      secondary: Color(0xFF1C2C4A),
      highlight: Color(0xFF79C0FF),
      surfaceVariant: Color(0xFF1B2440),
      muted: Color(0xFF193860),
      warm: Color(0xFF2EA043),
    ),

    AppThemeId.oled: AppThemeColors(
      background: Color(0xFF000000),
      surface: Color(0xFF0C0C12),
      accent: Color(0xFF7B3FE4),
      accentLight: Color(0xFFB08FFF),
      secondary: Color(0xFF14081F),
      highlight: Color(0xFFE040FB),
      surfaceVariant: Color(0xFF110E1E),
      muted: Color(0xFF29184C),
      warm: Color(0xFFD040BE),
    ),

    AppThemeId.cyberpunk: AppThemeColors(
      background: Color(0xFF080814),
      surface: Color(0xFF0F0F22),
      accent: Color(0xFFFF2D95),
      accentLight: Color(0xFFFF7EC7),
      secondary: Color(0xFF0A1F2F),
      highlight: Color(0xFF00FFF5),
      surfaceVariant: Color(0xFF151530),
      muted: Color(0xFF2A0926),
      warm: Color(0xFFFFE000),
    ),

    AppThemeId.forest: AppThemeColors(
      background: Color(0xFF0A120A),
      surface: Color(0xFF121E12),
      accent: Color(0xFF2E7D32),
      accentLight: Color(0xFF69BB5E),
      secondary: Color(0xFF1C3A10),
      highlight: Color(0xFFB2FF59),
      surfaceVariant: Color(0xFF172B17),
      muted: Color(0xFF1F3A12),
      warm: Color(0xFFD4A017),
    ),

    AppThemeId.sunset: AppThemeColors(
      background: Color(0xFF120A04),
      surface: Color(0xFF1E1008),
      accent: Color(0xFFE65100),
      accentLight: Color(0xFFFF8A3D),
      secondary: Color(0xFF3B1A0A),
      highlight: Color(0xFFFFD740),
      surfaceVariant: Color(0xFF281508),
      muted: Color(0xFF3E200A),
      warm: Color(0xFFFF5072),
    ),

    AppThemeId.ember: AppThemeColors(
      background: Color(0xFF141F22),
      surface: Color(0xFF1E2B2F),
      accent: Color(0xFFFF7F50),
      accentLight: Color(0xFFFFAA80),
      secondary: Color(0xFF253538),
      highlight: Color(0xFFFFBF80),
      surfaceVariant: Color(0xFF233035),
      muted: Color(0xFF2E3F44),
      warm: Color(0xFFFFD86E),
    ),

    AppThemeId.light: AppThemeColors(
      background: Color(0xFF2C2F3E),
      surface: Color(0xFF363A4C),
      accent: Color(0xFF5C6BC0),
      accentLight: Color(0xFF7986CB),
      secondary: Color(0xFF454A60),
      highlight: Color(0xFF9FA8DA),
      surfaceVariant: Color(0xFF40455A),
      muted: Color(0xFF4E5478),
      warm: Color(0xFFE87F6E),
    ),
  };

  static String label(AppThemeId id) {
    return switch (id) {
      AppThemeId.jujo => 'JUJO Purple',
      AppThemeId.deBoosy => 'De Boosy',
      AppThemeId.lazyAnkui => 'Lazy Ankui',
      AppThemeId.shioryPan => 'Shiory Pan',
      AppThemeId.midnight => 'Midnight Blue',
      AppThemeId.oled => 'OLED Black',
      AppThemeId.cyberpunk => 'Cyberpunk Neon',
      AppThemeId.forest => 'Forest',
      AppThemeId.sunset => 'Sunset',
      AppThemeId.ember => 'Ember',
      AppThemeId.light => 'Light',
    };
  }

  static IconData icon(AppThemeId id) {
    return switch (id) {
      AppThemeId.jujo => Icons.auto_awesome,
      AppThemeId.deBoosy => Icons.pets,
      AppThemeId.lazyAnkui => Icons.pets,
      AppThemeId.shioryPan => Icons.pets,
      AppThemeId.midnight => Icons.dark_mode,
      AppThemeId.oled => Icons.brightness_1,
      AppThemeId.cyberpunk => Icons.electric_bolt,
      AppThemeId.forest => Icons.park,
      AppThemeId.sunset => Icons.wb_twilight,
      AppThemeId.ember => Icons.local_fire_department,
      AppThemeId.light => Icons.light_mode,
    };
  }

  static AppThemeId fromName(String? name) {
    if (name == null) return AppThemeId.jujo;
    return AppThemeId.values.firstWhere(
      (e) => e.name == name,
      orElse: () => AppThemeId.jujo,
    );
  }
}
