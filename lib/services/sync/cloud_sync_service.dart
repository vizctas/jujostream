import 'dart:convert';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/google_auth_service.dart';

class CloudSyncService {
  CloudSyncService._();
  static final instance = CloudSyncService._();

  final _log = Logger(printer: SimplePrinter());

  static const _fileName = 'jujostream_config.json';
  static const _mimeType = 'application/json';

  static const _kStreamConfig = 'stream_config';

  static const _kTheme = 'app_theme';
  static const _kReduceEffects = 'reduce_effects';
  static const _kPerformanceMode = 'performance_mode';

  static const _kLocale = 'app_locale';

  static const _kPluginEnabledPrefix = 'plugin_enabled_';
  static const _kPluginApiKeyPrefix = 'plugin_apikey_';
  static const _kMicrotrailerMuted = 'microtrailer_muted';
  static const _kVideoDelaySecs = 'microtrailer_delay_secs';
  static const _kPluginSettingPrefix = 'plugin_setting_';

  Future<bool> pushConfig() async {
    final client = await GoogleAuthService.instance.authenticatedClient;
    if (client == null) {
      _log.w('pushConfig: not authenticated');
      return false;
    }

    try {
      final driveApi = drive.DriveApi(client);
      final payload = await _collectLocalConfig();
      final bytes = utf8.encode(jsonEncode(payload));

      final existingId = await _findConfigFileId(driveApi);

      final media = drive.Media(
        Stream.value(bytes),
        bytes.length,
        contentType: _mimeType,
      );

      if (existingId != null) {

        await driveApi.files.update(
          drive.File()..name = _fileName,
          existingId,
          uploadMedia: media,
        );
      } else {

        await driveApi.files.create(
          drive.File()
            ..name = _fileName
            ..parents = ['appDataFolder'],
          uploadMedia: media,
        );
      }

      _log.i('pushConfig OK (${bytes.length} bytes)');
      return true;
    } catch (e) {
      _log.e('pushConfig failed: $e');
      return false;
    } finally {
      client.close();
    }
  }

  Future<bool> pullConfig() async {
    final client = await GoogleAuthService.instance.authenticatedClient;
    if (client == null) {
      _log.w('pullConfig: not authenticated');
      return false;
    }

    try {
      final driveApi = drive.DriveApi(client);
      final fileId = await _findConfigFileId(driveApi);
      if (fileId == null) {
        _log.i('pullConfig: no cloud config found');
        return false;
      }

      final media = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }

      final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      await _applyCloudConfig(payload);

      _log.i('pullConfig OK');
      return true;
    } catch (e) {
      _log.e('pullConfig failed: $e');
      return false;
    } finally {
      client.close();
    }
  }

  Future<String?> _findConfigFileId(drive.DriveApi api) async {
    final list = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_fileName'",
      $fields: 'files(id)',
    );
    final files = list.files;
    if (files == null || files.isEmpty) return null;
    return files.first.id;
  }

  Future<Map<String, dynamic>> _collectLocalConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{
      'version': 1,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    final streamConfig = prefs.getString(_kStreamConfig);
    if (streamConfig != null) data[_kStreamConfig] = streamConfig;

    final theme = prefs.getString(_kTheme);
    if (theme != null) data[_kTheme] = theme;
    data[_kReduceEffects] = prefs.getBool(_kReduceEffects) ?? false;
    data[_kPerformanceMode] = prefs.getBool(_kPerformanceMode) ?? false;

    final locale = prefs.getString(_kLocale);
    if (locale != null) data[_kLocale] = locale;

    final pluginToggles = <String, bool>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_kPluginEnabledPrefix)) {
        pluginToggles[key] = prefs.getBool(key) ?? false;
      }
    }
    data['plugin_toggles'] = pluginToggles;

    final pluginSettings = <String, String>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_kPluginSettingPrefix)) {
        final val = prefs.getString(key);
        if (val != null) pluginSettings[key] = val;
      }
    }
    data['plugin_settings'] = pluginSettings;

    final pluginApiKeys = <String, String>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_kPluginApiKeyPrefix)) {
        final val = prefs.getString(key);
        if (val != null && val.isNotEmpty) pluginApiKeys[key] = val;
      }
    }
    data['plugin_api_keys'] = pluginApiKeys;

    data[_kMicrotrailerMuted] = prefs.getBool(_kMicrotrailerMuted) ?? true;
    data[_kVideoDelaySecs] = prefs.getInt(_kVideoDelaySecs) ?? 3;

    return data;
  }

  Future<void> _applyCloudConfig(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();

    if (data.containsKey(_kStreamConfig)) {
      await prefs.setString(_kStreamConfig, data[_kStreamConfig] as String);
    }

    if (data.containsKey(_kTheme)) {
      await prefs.setString(_kTheme, data[_kTheme] as String);
    }
    if (data.containsKey(_kReduceEffects)) {
      await prefs.setBool(_kReduceEffects, data[_kReduceEffects] as bool);
    }
    if (data.containsKey(_kPerformanceMode)) {
      await prefs.setBool(_kPerformanceMode, data[_kPerformanceMode] as bool);
    }

    if (data.containsKey(_kLocale)) {
      await prefs.setString(_kLocale, data[_kLocale] as String);
    }

    if (data.containsKey('plugin_toggles')) {
      final toggles = data['plugin_toggles'] as Map<String, dynamic>;
      for (final entry in toggles.entries) {
        await prefs.setBool(entry.key, entry.value as bool);
      }
    }

    if (data.containsKey('plugin_settings')) {
      final settings = data['plugin_settings'] as Map<String, dynamic>;
      for (final entry in settings.entries) {
        await prefs.setString(entry.key, entry.value as String);
      }
    }

    if (data.containsKey('plugin_api_keys')) {
      final apiKeys = data['plugin_api_keys'] as Map<String, dynamic>;
      for (final entry in apiKeys.entries) {
        await prefs.setString(entry.key, entry.value as String);
      }
    }

    if (data.containsKey(_kMicrotrailerMuted)) {
      await prefs.setBool(
          _kMicrotrailerMuted, data[_kMicrotrailerMuted] as bool);
    }
    if (data.containsKey(_kVideoDelaySecs)) {
      await prefs.setInt(_kVideoDelaySecs, data[_kVideoDelaySecs] as int);
    }
  }
}
