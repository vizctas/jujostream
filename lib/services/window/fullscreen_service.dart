import 'dart:io' as io;
import 'package:flutter/services.dart';

/// Manages borderless fullscreen state on Windows via the window channel.
/// F11 toggles fullscreen. State is persisted via LauncherPreferences.
class FullscreenService {
  FullscreenService._();

  static const _channel = MethodChannel('com.jujostream/window');

  static bool _fullscreen = false;
  static bool _available = true;

  /// Callback invoked when F11 fires at the native layer.
  /// The native side already toggled the window; this callback should
  /// persist the new state without re-issuing the native call.
  static void Function(bool newState)? onF11Toggle;

  static void init({bool initialState = false}) {
    if (!io.Platform.isWindows) return;
    _fullscreen = initialState;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onF11') {
        // Native already applied the toggle — just flip our bool and notify.
        _fullscreen = call.arguments as bool? ?? !_fullscreen;
        onF11Toggle?.call(_fullscreen);
      }
    });
    // Apply persisted state on startup
    _applyState(_fullscreen);
  }

  static bool get isFullscreen => _fullscreen;

  static Future<void> setFullscreen(bool enabled) async {
    _fullscreen = await _applyState(enabled);
  }

  static Future<void> toggle() async {
    await setFullscreen(!_fullscreen);
  }

  static Future<bool> _applyState(bool enabled) async {
    if (!_available) return _fullscreen;
    try {
      final result = await _channel.invokeMethod<bool>(
        'setFullscreen',
        {'enabled': enabled},
      );
      return result ?? enabled;
    } on MissingPluginException {
      _available = false;
      return _fullscreen;
    }
  }
}
