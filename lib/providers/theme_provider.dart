import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/theme_config.dart';
import '../services/audio/ui_sound_service.dart';
import '../services/database/achievement_service.dart';
import '../services/tv/tv_detector.dart';
import '../themes/launcher_theme.dart';
import '../themes/launcher_theme_registry.dart';

/// Bundled Focus Mode wallpapers, selectable in Settings → Personalization and
/// during onboarding. Stored in the focus_wallpaper pref as `asset:path`.
const kFocusWallpaperAssets = <String>[
  'assets/images/focus/wallpaper_00.jpg',
  'assets/images/focus/wallpaper_01.jpg',
  'assets/images/focus/wallpaper_02.jpg',
  'assets/images/focus/wallpaper_03.jpg',
  'assets/images/focus/wallpaper_04.jpg',
  'assets/images/focus/wallpaper_05.jpg',
  'assets/images/focus/wallpaper_06.jpg',
  'assets/images/focus/wallpaper_07.jpg',
  'assets/images/focus/wallpaper_08.jpg',
  'assets/images/focus/wallpaper_09.jpg',
  'assets/images/focus/wallpaper_10.jpg',
  'assets/images/focus/wallpaper_11.jpg',
];

class ThemeProvider extends ChangeNotifier {
  static const _keyTheme = 'app_theme';
  static const _keyReduceEffects = 'reduce_effects';
  static const _keyPerformanceMode = 'performance_mode';
  static const _keyArtQuality = 'art_quality';
  static const _keyLauncherTheme = 'launcher_theme';
  static const _keyAmbienceLayout = 'ambience_layout';
  static const _keyStandbySound = 'standby_sound';
  static const _keyAmbienceEffect = 'ambience_effect';
  static const _keyStandbyCustomPath = 'standby_custom_path';
  static const _keyStandbyCustomName = 'standby_custom_name';
  static const _keyStandbyVolume = 'standby_volume';
  static const _keyFocusWallpaper = 'focus_wallpaper';
  static const _keyFocusMusicScale = 'focus_music_scale';
  static const _keyFocusMusicOpacity = 'focus_music_opacity';

  final SharedPreferences _prefs;
  AppThemeId _themeId;
  bool _reduceEffects;
  bool _performanceMode;
  String _artQuality;
  LauncherThemeId _launcherThemeId;
  String _ambienceLayout;
  String _standbySound;
  String _ambienceEffect;
  String _standbyCustomPath;
  String _standbyCustomName;
  double _standbyVolume;
  String _focusWallpaper;
  double _focusMusicScale;
  double _focusMusicOpacity;

  String? _serverHostId;
  bool _serverOverrideActive = false;
  Future<void> Function(String hostId)? onAutoEnableServerOverride;
  Future<void> Function(LauncherThemeId id)? _onScopedLauncherThemeChanged;

  ThemeProvider._({
    required SharedPreferences prefs,
    required AppThemeId themeId,
    required bool reduceEffects,
    required bool performanceMode,
    required String artQuality,
    required LauncherThemeId launcherThemeId,
    required String ambienceLayout,
    required String standbySound,
    required String ambienceEffect,
    required String standbyCustomPath,
    required String standbyCustomName,
    required double standbyVolume,
    required String focusWallpaper,
    required double focusMusicScale,
    required double focusMusicOpacity,
  }) : _prefs = prefs,
       _themeId = themeId,
       _reduceEffects = reduceEffects,
       _performanceMode = performanceMode,
       _artQuality = artQuality,
       _launcherThemeId = launcherThemeId,
       _ambienceLayout = ambienceLayout,
       _standbySound = standbySound,
       _ambienceEffect = ambienceEffect,
       _standbyCustomPath = standbyCustomPath,
       _standbyCustomName = standbyCustomName,
       _standbyVolume = standbyVolume,
       _focusWallpaper = focusWallpaper,
       _focusMusicScale = focusMusicScale,
       _focusMusicOpacity = focusMusicOpacity;

  static Future<ThemeProvider> load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString(_keyTheme);
    final reduce = prefs.getBool(_keyReduceEffects) ?? false;
    final perf = prefs.getBool(_keyPerformanceMode) ?? false;
    final artQuality = prefs.getString(_keyArtQuality) ?? 'high';
    final launcherName = prefs.getString(_keyLauncherTheme);
    return ThemeProvider._(
      prefs: prefs,
      themeId: AppThemes.fromName(themeName),
      reduceEffects: reduce,
      performanceMode: perf,
      artQuality: artQuality,
      launcherThemeId: LauncherThemeRegistry.fromName(launcherName),
      ambienceLayout: prefs.getString(_keyAmbienceLayout) ?? 'circular',
      standbySound: prefs.getString(_keyStandbySound) ?? 'Alone',
      ambienceEffect:
          prefs.getString(_keyAmbienceEffect) ??
          'waves', // Default to waves for better performance on Android TV
      standbyCustomPath: prefs.getString(_keyStandbyCustomPath) ?? '',
      standbyCustomName: prefs.getString(_keyStandbyCustomName) ?? '',
      standbyVolume: prefs.getDouble(_keyStandbyVolume) ?? 0.25,
      focusWallpaper: prefs.getString(_keyFocusWallpaper) ?? '',
      focusMusicScale: (prefs.getDouble(_keyFocusMusicScale) ?? 0.40).clamp(
        0.40,
        1.50,
      ),
      focusMusicOpacity: (prefs.getDouble(_keyFocusMusicOpacity) ?? 0.82).clamp(
        0.20,
        1.00,
      ),
    );
  }

  String? get serverHostId => _serverHostId;
  bool get isServerScopeActive =>
      _serverOverrideActive &&
      _serverHostId != null &&
      _serverHostId!.isNotEmpty;

  String _srvKey(String base, [String? hostId]) =>
      'srv_${hostId ?? _serverHostId}_$base';

  void setServerScope({
    String? hostId,
    required bool overrideActive,
    Future<void> Function(String hostId)? onAutoEnable,
    Future<void> Function(LauncherThemeId id)? onLauncherThemeChanged,
  }) {
    final normalized = (hostId != null && hostId.isNotEmpty) ? hostId : null;
    final active = overrideActive && normalized != null;
    final changed =
        _serverHostId != normalized ||
        _serverOverrideActive != active ||
        onAutoEnableServerOverride != onAutoEnable ||
        _onScopedLauncherThemeChanged != onLauncherThemeChanged;
    _serverHostId = normalized;
    _serverOverrideActive = active;
    onAutoEnableServerOverride = onAutoEnable;
    _onScopedLauncherThemeChanged = onLauncherThemeChanged;
    if (changed) notifyListeners();
  }

  void markServerOverrideActive(bool active) {
    final normalized = (_serverHostId != null && _serverHostId!.isNotEmpty)
        ? _serverHostId
        : null;
    final next = active && normalized != null;
    if (_serverOverrideActive != next) {
      _serverOverrideActive = next;
      notifyListeners();
    }
  }

  Future<void> setServerLauncherThemeKey(
    String hostId,
    LauncherThemeId id,
  ) async {
    if (hostId.isEmpty) return;
    await _prefs.setString(_srvKey(_keyLauncherTheme, hostId), id.name);
    if (_serverHostId == hostId) {
      notifyListeners();
    }
  }

  Future<void> _ensureServerOverrideBeforeWrite(String hostId) async {
    if (!_serverOverrideActive) {
      _serverOverrideActive = true;
      if (onAutoEnableServerOverride != null) {
        await onAutoEnableServerOverride!(hostId);
      }
    }
  }

  Future<void> clearServerOverrides(String hostId) async {
    if (hostId.isEmpty) return;
    final prefix = 'srv_${hostId}_';
    final keys = _prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      await _prefs.remove(k);
    }
    notifyListeners();
  }

  // ── Per-server lookup helpers (used by FocusModeScreen / PcViewScreen) ──

  AppThemeId themeIdForServer(String? hostId, {required bool hasOverride}) {
    if (hasOverride && hostId != null && hostId.isNotEmpty) {
      final raw = _prefs.getString(_srvKey(_keyTheme, hostId));
      if (raw != null && raw.isNotEmpty) return AppThemes.fromName(raw);
    }
    return _themeId;
  }

  AppThemeColors colorsForServer(String? hostId, {required bool hasOverride}) {
    final id = themeIdForServer(hostId, hasOverride: hasOverride);
    return AppThemes.presets[id] ?? AppThemes.presets[AppThemeId.oled]!;
  }

  LauncherThemeId launcherThemeIdForServer(
    String? hostId, {
    required bool hasOverride,
  }) {
    if (hasOverride && hostId != null && hostId.isNotEmpty) {
      final raw = _prefs.getString(_srvKey(_keyLauncherTheme, hostId));
      if (raw != null && raw.isNotEmpty) {
        return LauncherThemeRegistry.fromName(raw);
      }
    }
    return _launcherThemeId;
  }

  String focusWallpaperForServer(String? hostId, {required bool hasOverride}) {
    if (hasOverride && hostId != null && hostId.isNotEmpty) {
      final raw = _prefs.getString(_srvKey(_keyFocusWallpaper, hostId));
      if (raw != null) return raw;
    }
    return _focusWallpaper;
  }

  String ambienceLayoutForServer(String? hostId, {required bool hasOverride}) {
    if (hasOverride && hostId != null && hostId.isNotEmpty) {
      final raw = _prefs.getString(_srvKey(_keyAmbienceLayout, hostId));
      if (raw != null && raw.isNotEmpty) return raw;
    }
    return _ambienceLayout;
  }

  String ambienceEffectForServer(String? hostId, {required bool hasOverride}) {
    if (hasOverride && hostId != null && hostId.isNotEmpty) {
      final raw = _prefs.getString(_srvKey(_keyAmbienceEffect, hostId));
      if (raw != null && raw.isNotEmpty) return raw;
    }
    return _ambienceEffect;
  }

  String standbySoundForServer(String? hostId, {required bool hasOverride}) {
    if (hasOverride && hostId != null && hostId.isNotEmpty) {
      final raw = _prefs.getString(_srvKey(_keyStandbySound, hostId));
      if (raw != null && raw.isNotEmpty) return raw;
    }
    return _standbySound;
  }

  String standbyCustomNameForServer(
    String? hostId, {
    required bool hasOverride,
  }) {
    if (hasOverride && hostId != null && hostId.isNotEmpty) {
      final raw = _prefs.getString(_srvKey(_keyStandbyCustomName, hostId));
      if (raw != null && raw.isNotEmpty) return raw;
    }
    return _standbyCustomName;
  }

  String standbyCustomPathForServer(
    String? hostId, {
    required bool hasOverride,
  }) {
    if (hasOverride && hostId != null && hostId.isNotEmpty) {
      final raw = _prefs.getString(_srvKey(_keyStandbyCustomPath, hostId));
      if (raw != null && raw.isNotEmpty) return raw;
    }
    return _standbyCustomPath;
  }

  double standbyVolumeForServer(String? hostId, {required bool hasOverride}) {
    if (hasOverride && hostId != null && hostId.isNotEmpty) {
      final raw = _prefs.getDouble(_srvKey(_keyStandbyVolume, hostId));
      if (raw != null) return raw.clamp(0.0, 1.0);
    }
    return _standbyVolume;
  }

  double focusMusicScaleForServer(String? hostId, {required bool hasOverride}) {
    if (hasOverride && hostId != null && hostId.isNotEmpty) {
      final raw = _prefs.getDouble(_srvKey(_keyFocusMusicScale, hostId));
      if (raw != null) return raw.clamp(0.40, 1.50);
    }
    return _focusMusicScale;
  }

  double focusMusicOpacityForServer(
    String? hostId, {
    required bool hasOverride,
  }) {
    if (hasOverride && hostId != null && hostId.isNotEmpty) {
      final raw = _prefs.getDouble(_srvKey(_keyFocusMusicOpacity, hostId));
      if (raw != null) return raw.clamp(0.20, 1.00);
    }
    return _focusMusicOpacity;
  }

  bool reduceEffectsForServer(String? hostId, {required bool hasOverride}) {
    if (hasOverride && hostId != null && hostId.isNotEmpty) {
      final raw = _prefs.getBool(_srvKey(_keyReduceEffects, hostId));
      if (raw != null) return raw;
    }
    return _reduceEffects;
  }

  bool performanceModeForServer(String? hostId, {required bool hasOverride}) {
    if (hasOverride && hostId != null && hostId.isNotEmpty) {
      final raw = _prefs.getBool(_srvKey(_keyPerformanceMode, hostId));
      if (raw != null) return raw;
    }
    return _performanceMode;
  }

  String artQualityForServer(String? hostId, {required bool hasOverride}) {
    if (hasOverride && hostId != null && hostId.isNotEmpty) {
      final raw = _prefs.getString(_srvKey(_keyArtQuality, hostId));
      if (raw != null && raw.isNotEmpty) return raw;
    }
    return _artQuality;
  }

  // ── Active Scope Getters ──

  AppThemeId get globalThemeId => _themeId;

  AppThemeId get themeId =>
      themeIdForServer(_serverHostId, hasOverride: isServerScopeActive);

  AppThemeColors get colors =>
      AppThemes.presets[themeId] ?? AppThemes.presets[AppThemeId.oled]!;

  bool get reduceEffects =>
      reduceEffectsForServer(_serverHostId, hasOverride: isServerScopeActive);

  bool get performanceMode =>
      performanceModeForServer(_serverHostId, hasOverride: isServerScopeActive);

  String get artQuality =>
      artQualityForServer(_serverHostId, hasOverride: isServerScopeActive);

  int get backgroundArtCacheWidth {
    if (TvDetector.instance.isTV) return 960;
    return performanceMode || artQuality != 'high' ? 1280 : 1920;
  }

  int? get artQualityCacheWidth {
    switch (artQuality) {
      case 'medium':
        return 720;
      case 'low':
        return 400;
      default:
        return null;
    }
  }

  LauncherThemeId get globalLauncherThemeId => _launcherThemeId;

  LauncherThemeId get launcherThemeId =>
      launcherThemeIdForServer(_serverHostId, hasOverride: isServerScopeActive);

  LauncherTheme get launcherTheme =>
      LauncherThemeRegistry.get(launcherThemeId);

  String get ambienceLayout =>
      ambienceLayoutForServer(_serverHostId, hasOverride: isServerScopeActive);

  String get standbySound =>
      standbySoundForServer(_serverHostId, hasOverride: isServerScopeActive);

  String get ambienceEffect =>
      ambienceEffectForServer(_serverHostId, hasOverride: isServerScopeActive);

  String get standbyCustomPath {
    if (isServerScopeActive) {
      final raw = _prefs.getString(_srvKey(_keyStandbyCustomPath));
      if (raw != null && raw.isNotEmpty) return raw;
    }
    return _standbyCustomPath;
  }

  String get standbyCustomName => standbyCustomNameForServer(
    _serverHostId,
    hasOverride: isServerScopeActive,
  );

  double get standbyVolume =>
      standbyVolumeForServer(_serverHostId, hasOverride: isServerScopeActive);

  String get focusWallpaper =>
      focusWallpaperForServer(_serverHostId, hasOverride: isServerScopeActive);

  double get focusMusicScale =>
      focusMusicScaleForServer(_serverHostId, hasOverride: isServerScopeActive);

  double get focusMusicOpacity => focusMusicOpacityForServer(
    _serverHostId,
    hasOverride: isServerScopeActive,
  );

  Color get background => colors.background;
  Color get surface => colors.surface;
  Color get accent => colors.accent;
  Color get accentLight => colors.accentLight;
  Color get secondary => colors.secondary;
  Color get highlight => colors.highlight;
  Color get surfaceVariant => colors.surfaceVariant;
  Color get muted => colors.muted;
  Color get warm => colors.warm;

  // ── Setters (Write to active server override when scoped, or Global when null) ──

  Future<void> setTheme(AppThemeId id) async {
    final hostId = _serverHostId;
    if (hostId != null && hostId.isNotEmpty) {
      await _ensureServerOverrideBeforeWrite(hostId);
      await _prefs.setString(_srvKey(_keyTheme, hostId), id.name);
      notifyListeners();
      unawaited(AchievementService.instance.unlock('changed_theme'));
      return;
    }
    if (id == _themeId) return;
    _themeId = id;
    notifyListeners();
    await _prefs.setString(_keyTheme, id.name);
    unawaited(AchievementService.instance.unlock('changed_theme'));
  }

  Future<void> setReduceEffects(bool value) async {
    final hostId = _serverHostId;
    if (hostId != null && hostId.isNotEmpty) {
      await _ensureServerOverrideBeforeWrite(hostId);
      await _prefs.setBool(_srvKey(_keyReduceEffects, hostId), value);
      notifyListeners();
      return;
    }
    if (value == _reduceEffects) return;
    _reduceEffects = value;
    notifyListeners();
    await _prefs.setBool(_keyReduceEffects, _reduceEffects);
    await _prefs.setBool(_keyPerformanceMode, _performanceMode);
  }

  Future<void> setArtQuality(String value) async {
    final hostId = _serverHostId;
    if (hostId != null && hostId.isNotEmpty) {
      await _ensureServerOverrideBeforeWrite(hostId);
      await _prefs.setString(_srvKey(_keyArtQuality, hostId), value);
      notifyListeners();
      return;
    }
    if (value == _artQuality) return;
    _artQuality = value;
    notifyListeners();
    await _prefs.setString(_keyArtQuality, value);
  }

  Future<void> setLauncherTheme(LauncherThemeId id) async {
    final hostId = _serverHostId;
    if (hostId != null && hostId.isNotEmpty) {
      await _ensureServerOverrideBeforeWrite(hostId);
      await _prefs.setString(_srvKey(_keyLauncherTheme, hostId), id.name);
      if (_onScopedLauncherThemeChanged != null) {
        await _onScopedLauncherThemeChanged!(id);
      }
      notifyListeners();
      return;
    }
    if (id == _launcherThemeId) return;
    _launcherThemeId = id;
    notifyListeners();
    await _prefs.setString(_keyLauncherTheme, id.name);
  }

  Future<void> setAmbienceLayout(String layout) async {
    final hostId = _serverHostId;
    if (hostId != null && hostId.isNotEmpty) {
      await _ensureServerOverrideBeforeWrite(hostId);
      await _prefs.setString(_srvKey(_keyAmbienceLayout, hostId), layout);
      notifyListeners();
      return;
    }
    if (layout == _ambienceLayout) return;
    _ambienceLayout = layout;
    notifyListeners();
    await _prefs.setString(_keyAmbienceLayout, layout);
  }

  Future<void> setAmbienceEffect(String effect) async {
    final hostId = _serverHostId;
    if (hostId != null && hostId.isNotEmpty) {
      await _ensureServerOverrideBeforeWrite(hostId);
      await _prefs.setString(_srvKey(_keyAmbienceEffect, hostId), effect);
      notifyListeners();
      return;
    }
    if (effect == _ambienceEffect) return;
    _ambienceEffect = effect;
    notifyListeners();
    await _prefs.setString(_keyAmbienceEffect, effect);
  }

  Future<void> setStandbySound(String sound) async {
    final hostId = _serverHostId;
    if (hostId != null && hostId.isNotEmpty) {
      await _ensureServerOverrideBeforeWrite(hostId);
      await _prefs.setString(_srvKey(_keyStandbySound, hostId), sound);
      notifyListeners();
      return;
    }
    if (sound == _standbySound) return;
    _standbySound = sound;
    notifyListeners();
    await _prefs.setString(_keyStandbySound, sound);
  }

  Future<void> setStandbyCustomPath(String path, String name) async {
    final hostId = _serverHostId;
    if (hostId != null && hostId.isNotEmpty) {
      await _ensureServerOverrideBeforeWrite(hostId);
      await _prefs.setString(_srvKey(_keyStandbyCustomPath, hostId), path);
      await _prefs.setString(_srvKey(_keyStandbyCustomName, hostId), name);
      await _prefs.setString(_srvKey(_keyStandbySound, hostId), 'custom');
      notifyListeners();
      return;
    }
    _standbyCustomPath = path;
    _standbyCustomName = name;
    _standbySound = 'custom';
    notifyListeners();
    await _prefs.setString(_keyStandbyCustomPath, path);
    await _prefs.setString(_keyStandbyCustomName, name);
    await _prefs.setString(_keyStandbySound, 'custom');
  }

  Future<void> setFocusWallpaper(String value) async {
    final hostId = _serverHostId;
    if (hostId != null && hostId.isNotEmpty) {
      await _ensureServerOverrideBeforeWrite(hostId);
      await _prefs.setString(_srvKey(_keyFocusWallpaper, hostId), value);
      notifyListeners();
      return;
    }
    if (value == _focusWallpaper) return;
    _focusWallpaper = value;
    notifyListeners();
    await _prefs.setString(_keyFocusWallpaper, value);
  }

  Future<void> setStandbyVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    final hostId = _serverHostId;
    if (hostId != null && hostId.isNotEmpty) {
      await _ensureServerOverrideBeforeWrite(hostId);
      await _prefs.setDouble(_srvKey(_keyStandbyVolume, hostId), clamped);
      notifyListeners();
      unawaited(UiSoundService.setAmbienceVolume(clamped));
      return;
    }
    if (clamped == _standbyVolume) return;
    _standbyVolume = clamped;
    notifyListeners();
    unawaited(UiSoundService.setAmbienceVolume(clamped));
    await _prefs.setDouble(_keyStandbyVolume, clamped);
  }

  Future<void> setFocusMusicScale(double value) async {
    final clamped = value.clamp(0.40, 1.50);
    final hostId = _serverHostId;
    if (hostId != null && hostId.isNotEmpty) {
      await _ensureServerOverrideBeforeWrite(hostId);
      await _prefs.setDouble(_srvKey(_keyFocusMusicScale, hostId), clamped);
      notifyListeners();
      return;
    }
    if (clamped == _focusMusicScale) return;
    _focusMusicScale = clamped;
    notifyListeners();
    await _prefs.setDouble(_keyFocusMusicScale, clamped);
  }

  Future<void> setFocusMusicOpacity(double value) async {
    final clamped = value.clamp(0.20, 1.00);
    final hostId = _serverHostId;
    if (hostId != null && hostId.isNotEmpty) {
      await _ensureServerOverrideBeforeWrite(hostId);
      await _prefs.setDouble(_srvKey(_keyFocusMusicOpacity, hostId), clamped);
      notifyListeners();
      return;
    }
    if (clamped == _focusMusicOpacity) return;
    _focusMusicOpacity = clamped;
    notifyListeners();
    await _prefs.setDouble(_keyFocusMusicOpacity, clamped);
  }

  Future<void> setPerformanceMode(bool value) async {
    final hostId = _serverHostId;
    if (hostId != null && hostId.isNotEmpty) {
      await _ensureServerOverrideBeforeWrite(hostId);
      await _prefs.setBool(_srvKey(_keyPerformanceMode, hostId), value);
      notifyListeners();
      return;
    }
    if (value == _performanceMode) return;
    _performanceMode = value;
    notifyListeners();
    await _prefs.setBool(_keyPerformanceMode, _performanceMode);
    await _prefs.setBool(_keyReduceEffects, _reduceEffects);
  }

  ThemeData buildThemeData() {
    final c = colors;
    final bool light = c.isLight;
    final Brightness brightness = light ? Brightness.light : Brightness.dark;

    final Color onSurface = light ? Colors.black87 : Colors.white;
    final Color onSurfaceMedium = light ? Colors.black54 : Colors.white70;
    final Color onSurfaceSubtle = light ? Colors.black38 : Colors.white54;
    final Color onSurfaceFaint = light ? Colors.black26 : Colors.white38;
    final Color onSurfaceOverlay = light ? Colors.black12 : Colors.white12;

    return ThemeData(
      brightness: brightness,
      primaryColor: c.accent,
      scaffoldBackgroundColor: c.background,
      focusColor: c.accent.withValues(alpha: 0.18),
      hoverColor: c.accent.withValues(alpha: 0.08),
      highlightColor: c.accent.withValues(alpha: 0.12),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 18,
          fontWeight: FontWeight.bold,
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
      inputDecorationTheme: const InputDecorationTheme(
        focusColor: Colors.transparent,
      ),
    );
  }
}
