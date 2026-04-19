import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/plugin_config.dart';

class PluginsProvider extends ChangeNotifier {
  static const _kPrefix = 'plugin_enabled_';
  static const _kMicrotrailerMuted = 'microtrailer_muted';
  static const _kVideoDelaySecs = 'microtrailer_delay_secs';
  static const _kApiKeyPrefix = 'plugin_apikey_';
  static const _kSettingPrefix = 'plugin_setting_';

  PluginsProvider._();

  late List<PluginConfig> _plugins;
  final Map<String, String> _apiKeys = <String, String>{};
  bool _microtrailerMuted = true;
  int _videoDelaySeconds = 3;

  List<PluginConfig> get plugins => List.unmodifiable(_plugins);
  bool get microtrailerMuted => _microtrailerMuted;
  int get videoDelaySeconds => _videoDelaySeconds;

  Future<void> setMicrotrailerMuted(bool muted) async {
    _microtrailerMuted = muted;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMicrotrailerMuted, muted);
  }

  Future<void> setVideoDelaySeconds(int seconds) async {
    _videoDelaySeconds = seconds.clamp(1, 30);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kVideoDelaySecs, _videoDelaySeconds);
  }

  static const List<PluginConfig> _builtInPlugins = [
    PluginConfig(
      id: 'metadata',
      name: 'Game Metadata',
      description:
          'Fetches game info (description, cover art, rating, genres) '
          'from IGDB / RAWG. Requires an internet connection.',
      category: PluginCategory.metadata,
      enabled: false,
    ),
    PluginConfig(
      id: 'game_video',
      name: 'Game Videos (Extra Metadata)',
      description:
          'Shows Steam micro-trailers and animated background videos '
          'when browsing your game library. Requires an internet connection.',
      category: PluginCategory.extraMetadata,
      enabled: false,
    ),
    PluginConfig(
      id: 'smart_genre_filters',
      name: 'Smart Genre Filters',
      description:
          'Groups RAWG metadata into broad genres like Accion, RPG, '
          'Plataforma o Carreras so you can filter the library faster. '
          'Requires Metadata + RAWG API key.',
      category: PluginCategory.metadata,
      enabled: false,
    ),
    PluginConfig(
      id: 'steam_connect',
      name: 'Steam Connect',
      description:
          'Connect your Steam account (Web API key + SteamID64) to enable '
          'playtime and achievement-based features.',
      category: PluginCategory.metadata,
      enabled: false,
    ),
    PluginConfig(
      id: 'steam_library_info',
      name: 'Steam Library Info',
      description:
          'Shows data from your Steam library in each game\'s sheet: '
          'play time, achievements, reviews, Steam Store genres, and filters '
          'by 100%%, pending or never started. Requires Steam Connect.',
      category: PluginCategory.metadata,
      enabled: false,
    ),
    PluginConfig(
      id: 'discovery_boost',
      name: 'Discovery Boost',
      description:
          'Suggests similar games using metadata genres and tags to help '
          'you discover what to play next.',
      category: PluginCategory.metadata,
      enabled: false,
    ),
    PluginConfig(
      id: 'screensaver',
      name: 'Screensaver',
      description:
          'Shows a game-art slideshow with Ken Burns effect after a period '
          'of inactivity in the game library. Configurable idle timeout. '
          'Disclaimer: feature may have bugs.',
      category: PluginCategory.extraMetadata,
      enabled: false,
    ),
    PluginConfig(
      id: 'startup_intro_video',
      name: 'Startup Intro Video',
      description:
          'Plays a short intro video when opening the app. Recommended '
          'length: 2-4 seconds. Playback can be interrupted.',
      category: PluginCategory.extraMetadata,
      enabled: false,
    ),
  ];

  static Future<PluginsProvider> load() async {
    final prefs = await SharedPreferences.getInstance();
    final provider = PluginsProvider._();
    provider._plugins = _builtInPlugins.map((p) {
      final saved = prefs.getBool('$_kPrefix${p.id}');
      return saved != null ? p.copyWith(enabled: saved) : p;
    }).toList();
    for (final plugin in provider._plugins) {
      final key = prefs.getString('$_kApiKeyPrefix${plugin.id}');
      if (key != null && key.isNotEmpty) {
        provider._apiKeys[plugin.id] = key;
      }
    }
    provider._microtrailerMuted = prefs.getBool(_kMicrotrailerMuted) ?? true;
    provider._videoDelaySeconds = prefs.getInt(_kVideoDelaySecs) ?? 3;
    return provider;
  }

  Future<void> setEnabled(String id, {required bool enabled}) async {
    final index = _plugins.indexWhere((p) => p.id == id);
    if (index < 0) return;
    _plugins[index] = _plugins[index].copyWith(enabled: enabled);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_kPrefix$id', enabled);
  }

  bool isEnabled(String id) => _plugins.any((p) => p.id == id && p.enabled);

  bool hasApiKey(String id) => (_apiKeys[id]?.trim().isNotEmpty ?? false);

  bool get canUseSmartGenreFilters =>
      isEnabled('smart_genre_filters') &&
      isEnabled('metadata') &&
      hasApiKey('metadata');

  bool get canUseSteamLibraryInfo =>
      isEnabled('steam_connect') && isEnabled('steam_library_info');

  bool get canUseAchievementsOverlay => isEnabled('steam_connect');

  bool get canUseDiscoveryBoost =>
      isEnabled('discovery_boost') && isEnabled('metadata');

  PluginConfig? pluginById(String id) {
    try {
      return _plugins.firstWhere((p) => p.id == id);
    } on StateError {
      return null;
    }
  }

  static String _apiKeyPref(String id) => '$_kApiKeyPrefix$id';
  static String settingPref(String id, String key) =>
      '$_kSettingPrefix${id}_$key';

  Future<String?> getApiKey(String id) async {
    final cached = _apiKeys[id];
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_apiKeyPref(id));
    if (value != null && value.isNotEmpty) {
      _apiKeys[id] = value;
    }
    return value;
  }

  Future<void> setApiKey(String id, String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (key.isEmpty) {
      _apiKeys.remove(id);
      await prefs.remove(_apiKeyPref(id));
    } else {
      _apiKeys[id] = key;
      await prefs.setString(_apiKeyPref(id), key);
    }
    notifyListeners();
  }

  Future<String?> getSetting(String id, String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(settingPref(id, key));
  }

  Future<void> setSetting(String id, String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final prefKey = settingPref(id, key);
    if (value.isEmpty) {
      await prefs.remove(prefKey);
    } else {
      await prefs.setString(prefKey, value);
    }
    notifyListeners();
  }
}
