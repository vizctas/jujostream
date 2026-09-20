import 'package:flutter/foundation.dart';
import '../models/stream_configuration.dart';
import '../platform_channels/gamepad_channel.dart';
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
      try {
        _config = StreamConfiguration.fromJson(jsonDecode(configJson));
      } catch (e) {
        // main() awaits this before runApp(), so anything thrown here used to
        // stop the app from starting at all. Falling back to defaults keeps a
        // corrupt pref from bricking the install; the next save overwrites it.
        debugPrint('SettingsProvider: stored stream_config unusable ($e); '
            'falling back to defaults.');
      }
    }
    _loaded = true;
    _pushBlockedButtons();
    notifyListeners();
  }

  Future<void> updateConfig(StreamConfiguration newConfig) async {
    _config = newConfig;
    _pushBlockedButtons();
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('stream_config', jsonEncode(newConfig.toJson()));
  }

  Future<void> applySerializedConfig(Map<String, dynamic> partialConfig) async {
    final merged = <String, dynamic>{..._config.toJson(), ...partialConfig};
    await updateConfig(StreamConfiguration.fromJson(merged));
  }

  /// Blocked buttons are pushed from here rather than from the stream screen:
  /// a button the user disabled has to stay dead in the launcher too, and this
  /// is the one place every config change passes through.
  void _pushBlockedButtons() {
    GamepadChannel.setBlockedButtons(_config.blockedGamepadButtons.keys.toList());
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
