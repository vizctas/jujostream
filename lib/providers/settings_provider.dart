import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_settings_profile.dart';
import '../models/stream_configuration.dart';
import '../platform_channels/gamepad_channel.dart';
import '../services/preferences/launcher_preferences.dart';
import '../themes/launcher_theme.dart';
import '../themes/launcher_theme_registry.dart';
import 'theme_provider.dart';

class SettingsProvider extends ChangeNotifier {
  static const String _globalConfigKey = 'stream_config';
  static const String _serverProfilesKey = 'server_settings_profiles_v1';

  StreamConfiguration _globalConfig = const StreamConfiguration();
  final Map<String, ServerSettingsProfile> _serverProfiles = {};
  String? _activeServerScopeId;
  LauncherPreferences? _scopedLauncherPreferences;
  ThemeProvider? _scopedThemeProvider;
  bool _loaded = false;

  /// Returns the effective [StreamConfiguration] for the currently active
  /// editing scope (`Global` when [activeServerScopeId] is null, or the
  /// selected server's configuration when editing a server).
  StreamConfiguration get config => configForServer(_activeServerScopeId);

  /// Always returns the global [StreamConfiguration].
  StreamConfiguration get globalConfig => _globalConfig;

  /// Currently selected scope in Settings (`null` = Global, non-null = server `hostId`).
  String? get activeServerScopeId => _activeServerScopeId;

  bool get isEditingServerScope =>
      _activeServerScopeId != null && _activeServerScopeId!.isNotEmpty;

  bool get loaded => _loaded;

  Map<String, ServerSettingsProfile> get serverProfiles =>
      Map.unmodifiable(_serverProfiles);

  ServerSettingsProfile? serverProfile(String? hostId) {
    if (hostId == null || hostId.isEmpty) return null;
    return _serverProfiles[hostId];
  }

  bool hasServerOverride(String? hostId) {
    if (hostId == null || hostId.isEmpty) return false;
    return _serverProfiles[hostId]?.overrideEnabled == true;
  }

  /// Resolves the effective [StreamConfiguration] for a given server [hostId].
  /// Returns the server's custom override if enabled, or [_globalConfig] otherwise.
  StreamConfiguration configForServer(String? hostId) {
    if (hostId != null && hostId.isNotEmpty) {
      final profile = _serverProfiles[hostId];
      if (profile != null && profile.overrideEnabled) {
        return profile.streamConfig;
      }
    }
    return _globalConfig;
  }

  /// Resolves the effective [LauncherThemeId] for a given server [hostId].
  LauncherThemeId launcherThemeForServer(
    String? hostId,
    LauncherThemeId globalThemeId,
  ) {
    if (hostId != null && hostId.isNotEmpty) {
      final profile = _serverProfiles[hostId];
      if (profile != null &&
          profile.overrideEnabled &&
          profile.launcherThemeName != null &&
          profile.launcherThemeName!.isNotEmpty) {
        return LauncherThemeRegistry.fromName(profile.launcherThemeName);
      }
    }
    return globalThemeId;
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final configJson = prefs.getString(_globalConfigKey);
    if (configJson != null) {
      try {
        _globalConfig = StreamConfiguration.fromJson(jsonDecode(configJson));
      } catch (e) {
        // main() awaits this before runApp(), so anything thrown here used to
        // stop the app from starting at all. Falling back to defaults keeps a
        // corrupt pref from bricking the install; the next save overwrites it.
        debugPrint(
          'SettingsProvider: stored stream_config unusable ($e); '
          'falling back to defaults.',
        );
      }
    }

    _serverProfiles.clear();
    final rawProfiles = prefs.getString(_serverProfilesKey);
    if (rawProfiles != null && rawProfiles.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawProfiles);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final key = entry.key.toString();
            final val = entry.value;
            if (key.isNotEmpty && val is Map) {
              final profile = ServerSettingsProfile.fromJson(
                Map<String, dynamic>.from(val),
                fallbackGlobal: _globalConfig,
              );
              _serverProfiles[key] = profile.copyWith(hostId: key);
            }
          }
        }
      } catch (e) {
        debugPrint(
          'SettingsProvider: stored server_settings_profiles_v1 unusable ($e); '
          'ignoring corrupt profiles.',
        );
      }
    }

    _loaded = true;
    _pushBlockedButtons();
    notifyListeners();
  }

  Future<void> _persistServerProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{
      for (final entry in _serverProfiles.entries)
        entry.key: entry.value.toJson(),
    };
    await prefs.setString(_serverProfilesKey, jsonEncode(map));
  }

  /// Switches the active editing scope in Settings (`null` = Global, `hostId` = Server)
  /// and synchronizes [LauncherPreferences] + [ThemeProvider] if provided.
  Future<void> setScope(
    String? hostId, {
    String? serverName,
    LauncherPreferences? launcherPreferences,
    ThemeProvider? themeProvider,
  }) async {
    final normalized = (hostId != null && hostId.isNotEmpty) ? hostId : null;
    if (launcherPreferences != null) {
      _scopedLauncherPreferences = launcherPreferences;
    }
    if (themeProvider != null) {
      _scopedThemeProvider = themeProvider;
    }
    if (normalized != null &&
        serverName != null &&
        serverName.isNotEmpty &&
        _serverProfiles.containsKey(normalized)) {
      _serverProfiles[normalized] = _serverProfiles[normalized]!.copyWith(
        serverName: serverName,
      );
    }
    _activeServerScopeId = normalized;
    await syncRuntimeServerContext(
      normalized,
      launcherPreferences: launcherPreferences ?? _scopedLauncherPreferences,
      themeProvider: themeProvider ?? _scopedThemeProvider,
      allowEditingLauncherTheme: normalized != null,
      serverName: serverName,
    );
    _pushBlockedButtons();
    notifyListeners();
  }

  /// Synchronizes [LauncherPreferences] and [ThemeProvider] to reflect the
  /// effective launcher settings for [hostId] (or Global when `hostId == null`).
  Future<void> syncRuntimeServerContext(
    String? hostId, {
    LauncherPreferences? launcherPreferences,
    ThemeProvider? themeProvider,
    bool allowEditingLauncherTheme = false,
    String? serverName,
  }) async {
    final normalized = (hostId != null && hostId.isNotEmpty) ? hostId : null;
    final overrideActive = hasServerOverride(normalized);
    final allowEditing = normalized != null && allowEditingLauncherTheme;

    if (themeProvider != null) {
      final profile = normalized != null ? _serverProfiles[normalized] : null;
      if (normalized != null &&
          overrideActive &&
          profile?.launcherThemeName != null &&
          profile!.launcherThemeName!.isNotEmpty) {
        await themeProvider.setServerLauncherThemeKey(
          normalized,
          LauncherThemeRegistry.fromName(profile.launcherThemeName),
        );
      }

      themeProvider.setServerScope(
        hostId: normalized,
        overrideActive: overrideActive,
        onAutoEnable: allowEditing
            ? (String targetHostId) async {
                await enableServerOverrideSilent(
                  targetHostId,
                  serverName: serverName ?? '',
                  launcherPreferences: launcherPreferences,
                  themeProvider: themeProvider,
                );
              }
            : null,
        onLauncherThemeChanged: (normalized != null && (overrideActive || allowEditing))
            ? (LauncherThemeId newThemeId) async {
                await setServerLauncherTheme(
                  normalized,
                  newThemeId,
                  serverName: serverName ?? '',
                  launcherPreferences: launcherPreferences,
                  themeProvider: themeProvider,
                );
              }
            : null,
      );

      final effectiveThemeId = launcherThemeForServer(
        normalized,
        themeProvider.launcherThemeId,
      );

      if (launcherPreferences != null) {
        launcherPreferences.onAutoEnableServerOverride = allowEditing
            ? (String targetHostId) async {
                await enableServerOverrideSilent(
                  targetHostId,
                  serverName: serverName ?? '',
                  launcherPreferences: launcherPreferences,
                  themeProvider: themeProvider,
                );
              }
            : null;
        await launcherPreferences.setServerScope(
          hostId: normalized,
          overrideActive: overrideActive,
          profileId: effectiveThemeId.name,
        );
      }
    } else if (launcherPreferences != null) {
      launcherPreferences.onAutoEnableServerOverride = allowEditing
          ? (String targetHostId) async {
              await enableServerOverrideSilent(
                targetHostId,
                serverName: serverName ?? '',
                launcherPreferences: launcherPreferences,
                themeProvider: themeProvider,
              );
            }
          : null;
      await launcherPreferences.setServerScope(
        hostId: normalized,
        overrideActive: overrideActive,
      );
    }
  }

  /// Silently marks [hostId] override as enabled without reloading
  /// [LauncherPreferences] from disk (preventing in-flight writes from being
  /// overwritten).
  Future<void> enableServerOverrideSilent(
    String hostId, {
    String serverName = '',
    LauncherPreferences? launcherPreferences,
    ThemeProvider? themeProvider,
  }) async {
    if (hostId.isEmpty) return;
    final lp = launcherPreferences ?? _scopedLauncherPreferences;
    final tp = themeProvider ?? _scopedThemeProvider;
    final existing = _serverProfiles[hostId];
    final globalThemeName = tp?.globalLauncherThemeId.name;
    final updated = (existing ??
            ServerSettingsProfile(
              hostId: hostId,
              serverName: serverName,
              streamConfig: _globalConfig,
              launcherThemeName: globalThemeName,
            ))
        .copyWith(
          serverName: serverName.isNotEmpty
              ? serverName
              : (existing?.serverName ?? ''),
          overrideEnabled: true,
        );
    _serverProfiles[hostId] = updated;
    if (lp?.serverHostId == hostId) {
      lp!.markServerOverrideActive(true);
    }
    if (tp?.serverHostId == hostId) {
      tp!.markServerOverrideActive(true);
    }
    await _persistServerProfiles();
    _pushBlockedButtons();
    notifyListeners();
  }

  /// Enables or disables custom per-server override for [hostId].
  /// When enabling for the first time, clones [_globalConfig] so the user starts
  /// from their familiar global baseline.
  Future<void> setServerOverrideEnabled(
    String hostId,
    bool enabled, {
    String serverName = '',
    LauncherPreferences? launcherPreferences,
    ThemeProvider? themeProvider,
  }) async {
    if (hostId.isEmpty) return;
    final existing = _serverProfiles[hostId];
    final globalThemeName = themeProvider?.globalLauncherThemeId.name;
    final updated = (existing ??
            ServerSettingsProfile(
              hostId: hostId,
              serverName: serverName,
              streamConfig: _globalConfig,
              launcherThemeName: globalThemeName,
            ))
        .copyWith(
          serverName: serverName.isNotEmpty
              ? serverName
              : (existing?.serverName ?? ''),
          overrideEnabled: enabled,
        );
    _serverProfiles[hostId] = updated;
    await _persistServerProfiles();

    if (_activeServerScopeId == hostId ||
        launcherPreferences?.serverHostId == hostId ||
        themeProvider?.serverHostId == hostId) {
      await syncRuntimeServerContext(
        hostId,
        launcherPreferences: launcherPreferences ?? _scopedLauncherPreferences,
        themeProvider: themeProvider ?? _scopedThemeProvider,
        allowEditingLauncherTheme: _activeServerScopeId == hostId,
        serverName: updated.serverName,
      );
    }
    _pushBlockedButtons();
    notifyListeners();
  }

  /// Sets the custom [LauncherThemeId] for [hostId] (auto-enabling server override if needed).
  Future<void> setServerLauncherTheme(
    String hostId,
    LauncherThemeId themeId, {
    String serverName = '',
    LauncherPreferences? launcherPreferences,
    ThemeProvider? themeProvider,
  }) async {
    if (hostId.isEmpty) return;
    final existing = _serverProfiles[hostId];
    final updated = (existing ??
            ServerSettingsProfile(
              hostId: hostId,
              serverName: serverName,
              overrideEnabled: true,
              streamConfig: _globalConfig,
            ))
        .copyWith(
          overrideEnabled: true,
          launcherThemeName: themeId.name,
          serverName: serverName.isNotEmpty
              ? serverName
              : (existing?.serverName ?? ''),
        );
    _serverProfiles[hostId] = updated;
    await _persistServerProfiles();

    final tp = themeProvider ?? _scopedThemeProvider;
    if (tp != null) {
      await tp.setServerLauncherThemeKey(hostId, themeId);
      if (tp.serverHostId == hostId) {
        tp.markServerOverrideActive(true);
      }
    }

    final lp = launcherPreferences ?? _scopedLauncherPreferences;
    if (lp != null) {
      await lp.setServerScope(
        hostId: hostId,
        overrideActive: true,
        profileId: themeId.name,
      );
    }
    notifyListeners();
  }

  /// Resets [hostId] back to inheriting Global configuration & launcher settings.
  Future<void> resetServerToGlobal(
    String hostId, {
    String serverName = '',
    LauncherPreferences? launcherPreferences,
    ThemeProvider? themeProvider,
  }) async {
    if (hostId.isEmpty) return;
    _serverProfiles[hostId] = ServerSettingsProfile(
      hostId: hostId,
      serverName: serverName.isNotEmpty
          ? serverName
          : (_serverProfiles[hostId]?.serverName ?? ''),
      overrideEnabled: false,
      streamConfig: _globalConfig,
    );
    await _persistServerProfiles();
    final lp = launcherPreferences ?? _scopedLauncherPreferences;
    final tp = themeProvider ?? _scopedThemeProvider;
    if (lp != null) {
      await lp.clearServerOverrides(hostId);
    }
    if (tp != null) {
      await tp.clearServerOverrides(hostId);
    }
    if (_activeServerScopeId == hostId ||
        lp?.serverHostId == hostId ||
        tp?.serverHostId == hostId) {
      await syncRuntimeServerContext(
        hostId,
        launcherPreferences: lp,
        themeProvider: tp,
        allowEditingLauncherTheme: _activeServerScopeId == hostId,
        serverName: serverName,
      );
    }
    _pushBlockedButtons();
    notifyListeners();
  }

  /// Copies current [_globalConfig] values into [hostId]'s custom override profile
  /// while keeping override enabled.
  Future<void> copyGlobalToServer(
    String hostId, {
    String serverName = '',
    LauncherPreferences? launcherPreferences,
    ThemeProvider? themeProvider,
  }) async {
    if (hostId.isEmpty) return;
    final lp = launcherPreferences ?? _scopedLauncherPreferences;
    final tp = themeProvider ?? _scopedThemeProvider;
    _serverProfiles[hostId] = ServerSettingsProfile(
      hostId: hostId,
      serverName: serverName.isNotEmpty
          ? serverName
          : (_serverProfiles[hostId]?.serverName ?? ''),
      overrideEnabled: true,
      streamConfig: _globalConfig,
      launcherThemeName: tp?.globalLauncherThemeId.name,
    );
    await _persistServerProfiles();
    if (lp != null) {
      await lp.clearServerOverrides(hostId);
    }
    if (tp != null) {
      await tp.clearServerOverrides(hostId);
    }
    if (_activeServerScopeId == hostId ||
        lp?.serverHostId == hostId ||
        tp?.serverHostId == hostId) {
      await syncRuntimeServerContext(
        hostId,
        launcherPreferences: lp,
        themeProvider: tp,
        allowEditingLauncherTheme: _activeServerScopeId == hostId,
        serverName: serverName,
      );
    }
    _pushBlockedButtons();
    notifyListeners();
  }

  Future<void> updateConfig(StreamConfiguration newConfig) async {
    final targetServerId = _activeServerScopeId;
    if (targetServerId != null && targetServerId.isNotEmpty) {
      final existing = _serverProfiles[targetServerId];
      _serverProfiles[targetServerId] = (existing ??
              ServerSettingsProfile(
                hostId: targetServerId,
                overrideEnabled: true,
                streamConfig: newConfig,
              ))
          .copyWith(overrideEnabled: true, streamConfig: newConfig);
      if (_scopedLauncherPreferences?.serverHostId == targetServerId) {
        _scopedLauncherPreferences!.markServerOverrideActive(true);
      }
      if (_scopedThemeProvider?.serverHostId == targetServerId) {
        _scopedThemeProvider!.markServerOverrideActive(true);
      }
      _pushBlockedButtons();
      notifyListeners();
      await _persistServerProfiles();
      return;
    }

    _globalConfig = newConfig;
    _pushBlockedButtons();
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_globalConfigKey, jsonEncode(newConfig.toJson()));
  }

  Future<void> applySerializedConfig(Map<String, dynamic> partialConfig) async {
    final merged = <String, dynamic>{...config.toJson(), ...partialConfig};
    await updateConfig(StreamConfiguration.fromJson(merged));
  }

  /// Blocked buttons are pushed from here rather than from the stream screen:
  /// a button the user disabled has to stay dead in the launcher too, and this
  /// is the one place every config change passes through.
  void _pushBlockedButtons() {
    GamepadChannel.setBlockedButtons(config.blockedGamepadButtons.keys.toList());
  }

  Future<void> setResolution(int width, int height) async {
    await updateConfig(config.copyWith(width: width, height: height));
  }

  Future<void> setFps(int fps) async {
    await updateConfig(config.copyWith(fps: fps));
  }

  Future<void> setBitrate(int bitrate) async {
    await updateConfig(config.copyWith(bitrate: bitrate));
  }

  Future<void> setVideoCodec(VideoCodec codec) async {
    await updateConfig(config.copyWith(videoCodec: codec));
  }

  Future<void> setHdr(bool enabled) async {
    await updateConfig(config.copyWith(enableHdr: enabled));
  }

  Future<void> setScaleMode(VideoScaleMode mode) async {
    await updateConfig(config.copyWith(scaleMode: mode));
  }
}
