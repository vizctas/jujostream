import 'package:flutter/foundation.dart';
import '../models/stream_configuration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SettingsProvider extends ChangeNotifier {
  StreamConfiguration _config = const StreamConfiguration();
  bool _loaded = false;

  StreamConfiguration get config => _config;
  bool get loaded => _loaded;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final configJson = prefs.getString('stream_config');
    if (configJson != null) {
      _config = StreamConfiguration.fromJson(jsonDecode(configJson));
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> updateConfig(StreamConfiguration newConfig) async {
    _config = newConfig;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('stream_config', jsonEncode(newConfig.toJson()));
  }

  Future<void> applySerializedConfig(Map<String, dynamic> partialConfig) async {
    final merged = <String, dynamic>{..._config.toJson(), ...partialConfig};
    await updateConfig(StreamConfiguration.fromJson(merged));
  }

  Future<void> setResolution(int width, int height) async {
    await updateConfig(_config.copyWith(width: width, height: height));
  }

  Future<void> setFps(int fps) async {
    await updateConfig(_config.copyWith(fps: fps));
  }

  Future<void> setBitrate(int bitrate) async {
    await updateConfig(_config.copyWith(bitrate: bitrate));
  }

  Future<void> setVideoCodec(VideoCodec codec) async {
    await updateConfig(_config.copyWith(videoCodec: codec));
  }

  Future<void> setHdr(bool enabled) async {
    await updateConfig(_config.copyWith(enableHdr: enabled));
  }

  Future<void> setScaleMode(VideoScaleMode mode) async {
    await updateConfig(_config.copyWith(scaleMode: mode));
  }
}
