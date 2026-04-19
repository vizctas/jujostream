import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/theme_config.dart';
import '../services/database/achievement_service.dart';
import '../themes/launcher_theme.dart';
import '../themes/launcher_theme_registry.dart';

class ThemeProvider extends ChangeNotifier {
  static const _keyTheme = 'app_theme';
  static const _keyReduceEffects = 'reduce_effects';
  static const _keyPerformanceMode = 'performance_mode';
  static const _keyArtQuality = 'art_quality';
  static const _keyLauncherTheme = 'launcher_theme';
  static const _keyAmbienceLayout = 'ambience_layout';
  static const _keyStandbySound = 'standby_sound';
  static const _keyAmbienceEffect = 'ambience_effect';

  AppThemeId _themeId;
  bool _reduceEffects;
  bool _performanceMode;
  String _artQuality;
  LauncherThemeId _launcherThemeId;
  String _ambienceLayout;
  String _standbySound;
  String _ambienceEffect;

  ThemeProvider._({
    required AppThemeId themeId,
    required bool reduceEffects,
    required bool performanceMode,
    required String artQuality,
    required LauncherThemeId launcherThemeId,
    required String ambienceLayout,
    required String standbySound,
    required String ambienceEffect,
  })  : _themeId = themeId,
        _reduceEffects = reduceEffects,
        _performanceMode = performanceMode,
        _artQuality = artQuality,
        _launcherThemeId = launcherThemeId,
        _ambienceLayout = ambienceLayout,
        _standbySound = standbySound,
        _ambienceEffect = ambienceEffect;

  static Future<ThemeProvider> load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString(_keyTheme);
    final reduce = prefs.getBool(_keyReduceEffects) ?? false;
    final perf = prefs.getBool(_keyPerformanceMode) ?? false;
    final artQuality = prefs.getString(_keyArtQuality) ?? 'high';
    final launcherName = prefs.getString(_keyLauncherTheme);
    return ThemeProvider._(
      themeId: AppThemes.fromName(themeName),
      reduceEffects: reduce || perf,
      performanceMode: perf,
      artQuality: artQuality,
      launcherThemeId: LauncherThemeRegistry.fromName(launcherName),
      ambienceLayout: prefs.getString(_keyAmbienceLayout) ?? 'card',
      standbySound: prefs.getString(_keyStandbySound) ?? 'Alone',
      ambienceEffect: prefs.getString(_keyAmbienceEffect) ?? 'waves', // Default to waves for better performance on Android TV
    );
  }

  AppThemeId get themeId => _themeId;

  AppThemeColors get colors =>
      AppThemes.presets[_themeId] ?? AppThemes.presets[AppThemeId.jujo]!;

  bool get reduceEffects => _reduceEffects;

  bool get performanceMode => _performanceMode;

  String get artQuality => _artQuality;

  int? get artQualityCacheWidth {
    switch (_artQuality) {
      case 'medium': return 720;
      case 'low': return 400;
      default: return null;
    }
  }

  LauncherThemeId get launcherThemeId => _launcherThemeId;

  LauncherTheme get launcherTheme => LauncherThemeRegistry.get(_launcherThemeId);

  String get ambienceLayout => _ambienceLayout;

  String get standbySound => _standbySound;

  String get ambienceEffect => _ambienceEffect;

  Color get background => colors.background;
  Color get surface => colors.surface;
  Color get accent => colors.accent;
  Color get accentLight => colors.accentLight;
  Color get secondary => colors.secondary;
  Color get highlight => colors.highlight;
  Color get surfaceVariant => colors.surfaceVariant;
  Color get muted => colors.muted;
  Color get warm => colors.warm;

  Future<void> setTheme(AppThemeId id) async {
    if (id == _themeId) return;
    _themeId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTheme, id.name);

    unawaited(AchievementService.instance.unlock('changed_theme'));
  }

  Future<void> setReduceEffects(bool value) async {
    if (value == _reduceEffects) return;
    _reduceEffects = value;

    if (!value) _performanceMode = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReduceEffects, _reduceEffects);
    await prefs.setBool(_keyPerformanceMode, _performanceMode);
  }

  Future<void> setArtQuality(String value) async {
    if (value == _artQuality) return;
    _artQuality = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyArtQuality, value);
  }

  Future<void> setLauncherTheme(LauncherThemeId id) async {
    if (id == _launcherThemeId) return;
    _launcherThemeId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLauncherTheme, id.name);
  }

  Future<void> setAmbienceLayout(String layout) async {
    if (layout == _ambienceLayout) return;
    _ambienceLayout = layout;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAmbienceLayout, layout);
  }

  Future<void> setAmbienceEffect(String effect) async {
    if (effect == _ambienceEffect) return;
    _ambienceEffect = effect;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAmbienceEffect, effect);
  }

  Future<void> setStandbySound(String sound) async {
    if (sound == _standbySound) return;
    _standbySound = sound;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStandbySound, sound);
  }

  Future<void> setPerformanceMode(bool value) async {
    if (value == _performanceMode) return;
    _performanceMode = value;

    if (value) _reduceEffects = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPerformanceMode, _performanceMode);
    await prefs.setBool(_keyReduceEffects, _reduceEffects);
  }

  ThemeData buildThemeData() {
    final c = colors;
    final bool light = c.isLight;
    final Brightness brightness = light ? Brightness.light : Brightness.dark;

    final Color onSurface = light ? Colors.black87 : Colors.white;
    final Color onSurfaceMedium = light ? Colors.black54 : Colors.white70;
    final Color onSurfaceSubtle = light ? Colors.black38 : Colors.white54;
    final Color onSurfaceFaint = light ? Colors.black26 : Colors.white38;
    final Color onSurfaceDivider = light ? Colors.black12 : Colors.white24;
    final Color onSurfaceOverlay = light ? Colors.black12 : Colors.white12;

    return ThemeData(
      brightness: brightness,
      primaryColor: c.accent,
      scaffoldBackgroundColor: c.background,

      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashColor: c.accent.withValues(alpha: 0.10),
      colorScheme: light
          ? ColorScheme.light(
              primary: c.accent,
              secondary: c.secondary,
              surface: c.surface,
              onSurface: onSurface,
              onPrimary: Colors.white,
            )
          : ColorScheme.dark(
              primary: c.accent,
              secondary: c.secondary,
              surface: c.surface,
              onSurface: onSurface,
              onPrimary: Colors.white,
            ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: onSurface,
        elevation: 0,

        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        titleTextStyle: TextStyle(
          color: onSurface, fontSize: 18, fontWeight: FontWeight.bold,
        ),
        contentTextStyle: TextStyle(color: onSurfaceMedium, fontSize: 14),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.accent;
          return onSurfaceFaint;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return c.accent.withValues(alpha: 0.4);
          }
          return onSurfaceOverlay;
        }),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: onSurfaceSubtle,
        textColor: onSurface,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accentLight,
          overlayColor: c.accent.withValues(alpha: 0.08),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: Colors.white,
          overlayColor: c.accentLight.withValues(alpha: 0.15),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) return Colors.transparent;
            if (states.contains(WidgetState.hovered)) {
              return onSurface.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.pressed)) {
              return onSurface.withValues(alpha: 0.12);
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return onSurface;
          }),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.accentLight),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: onSurfaceDivider),
        ),
        labelStyle: TextStyle(color: onSurfaceSubtle),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: c.accent.withValues(alpha: 0.2),
        checkmarkColor: onSurface,
        labelStyle: TextStyle(color: onSurface),
        side: BorderSide.none,
      ),
      useMaterial3: true,
    );
  }
}
