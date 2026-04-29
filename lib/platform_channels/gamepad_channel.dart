import 'package:flutter/services.dart';

class GamepadChannel {
  static const _channel = MethodChannel('com.jujostream/gamepad');

  /// True when the native gamepad channel is available on this platform.
  static bool _available = true;

  static VoidCallback? onComboDetected;

  static void Function(String direction)? onOverlayDpad;

  static VoidCallback? onMouseModeToggle;

  static VoidCallback? onPanicComboDetected;

  static VoidCallback? onQuickFavComboDetected;

  static void Function(int controllerNumber)? onControllerConnected;

  static void Function(int controllerNumber)? onControllerDisconnected;

  /// Fired when a gamepad D-Pad / A / B is pressed while not streaming.
  /// [key] is one of: 'up', 'down', 'left', 'right', 'select', 'back'.
  static void Function(String key)? onNavInput;

  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onComboDetected') {
        onComboDetected?.call();
      } else if (call.method == 'onOverlayDpad') {
        final dir = call.arguments as String?;
        if (dir != null) onOverlayDpad?.call(dir);
      } else if (call.method == 'onMouseModeToggle') {
        onMouseModeToggle?.call();
      } else if (call.method == 'onPanicComboDetected') {
        onPanicComboDetected?.call();
      } else if (call.method == 'onQuickFavComboDetected') {
        onQuickFavComboDetected?.call();
      } else if (call.method == 'onControllerConnected') {
        final args = call.arguments;
        final int? slot = args is Map ? args['slot'] as int? : args as int?;
        if (slot != null) onControllerConnected?.call(slot);
      } else if (call.method == 'onControllerDisconnected') {
        final args = call.arguments;
        final int? slot = args is Map ? args['slot'] as int? : args as int?;
        if (slot != null) onControllerDisconnected?.call(slot);
      } else if (call.method == 'onNavInput') {
        final key = call.arguments as String?;
        if (key != null) onNavInput?.call(key);
      }
    });
  }

  static Future<T?> _invoke<T>(String method, [dynamic arguments]) async {
    if (!_available) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      _available = false;
      return null;
    }
  }

  static Future<int> setStreamingActive(bool active) async {
    final result = await _invoke<int>('setStreamingActive', {'active': active});
    return result ?? 0;
  }

  static Future<void> setOverlayVisible(bool visible) async {
    await _invoke('setOverlayVisible', {'visible': visible});
  }

  static Future<int> getConnectedGamepadCount() async {
    final result = await _invoke<int>('getConnectedGamepadCount');
    return result ?? 0;
  }

  static Future<int> redetectControllers() async {
    final result = await _invoke<int>('redetectControllers');
    return result ?? 0;
  }

  static Future<void> setDeadzone(int percent) async {
    await _invoke('setDeadzone', {'percent': percent});
  }

  static Future<void> setResponseCurve(double curve) async {
    await _invoke('setResponseCurve', {'curve': curve});
  }

  static Future<void> setTouchpadAsMouse(bool enabled) async {
    await _invoke('setTouchpadAsMouse', {'enabled': enabled});
  }

  static Future<void> setMotionSensors(bool enabled, bool fallback) async {
    await _invoke('setMotionSensors', {
      'enabled': enabled,
      'fallback': fallback,
    });
  }

  static Future<void> setRumbleConfig(
    bool enabled,
    bool fallback,
    bool deviceRumble,
    int strength,
  ) async {
    await _invoke('setRumbleConfig', {
      'enabled': enabled,
      'fallback': fallback,
      'deviceRumble': deviceRumble,
      'strength': strength.clamp(0, 100),
    });
  }

  static Future<void> setControllerPreferences({
    required bool backButtonAsMeta,
    required bool backButtonAsGuide,
    required int controllerDriver,
  }) async {
    await _invoke('setControllerPreferences', {
      'backButtonAsMeta': backButtonAsMeta,
      'backButtonAsGuide': backButtonAsGuide,
      'controllerDriver': controllerDriver,
    });
  }

  static Future<void> setInputPreferences({
    required bool forceQwertyLayout,
    required bool usbDriverEnabled,
    required bool usbBindAll,
    required bool joyConEnabled,
  }) async {
    await _invoke('setInputPreferences', {
      'forceQwertyLayout': forceQwertyLayout,
      'usbDriverEnabled': usbDriverEnabled,
      'usbBindAll': usbBindAll,
      'joyConEnabled': joyConEnabled,
    });
  }

  static Future<void> setButtonRemap(Map<int, int>? remapTable) async {
    await _invoke('setButtonRemap', {'remap': remapTable});
  }

  static Future<void> setMouseSensitivity(double sensitivity) async {
    await _invoke('setMouseSensitivity', {
      'sensitivity': sensitivity.clamp(0.1, 5.0),
    });
  }

  static Future<void> setMouseEmulationSpeed(double factor) async {
    await _invoke('setMouseEmulationSpeed', {'factor': factor.clamp(0.5, 5.0)});
  }

  static Future<void> setScrollSensitivity(double sensitivity) async {
    await _invoke('setScrollSensitivity', {
      'sensitivity': sensitivity.clamp(0.1, 5.0),
    });
  }

  static Future<void> setTriggerDeadzone(int percent) async {
    await _invoke('setTriggerDeadzone', {'percent': percent.clamp(0, 20)});
  }

  static Future<List<Map<String, dynamic>>> getControllerInfo() async {
    final result = await _invoke<List<dynamic>>('getControllerInfo');
    if (result == null) return [];
    return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> setMouseEmulation(bool active) async {
    await _invoke('setMouseEmulation', {'enabled': active});
  }

  static Future<bool> getMouseEmulation() async {
    final result = await _invoke<bool>('getMouseEmulation');
    return result ?? false;
  }

  static Future<void> setOverlayTriggerConfig(int combo, int holdMs) async {
    await _invoke('setOverlayTriggerConfig', {
      'combo': combo,
      'holdMs': holdMs.clamp(0, 8000),
    });
  }

  static Future<void> setMouseModeConfig(int combo, int holdMs) async {
    await _invoke('setMouseModeConfig', {
      'combo': combo,
      'holdMs': holdMs.clamp(0, 8000),
    });
  }

  static Future<void> setPanicComboConfig(int combo, int holdMs) async {
    await _invoke('setPanicComboConfig', {
      'combo': combo,
      'holdMs': holdMs.clamp(0, 8000),
    });
  }

  static Future<void> setQuickFavComboConfig(int combo, int holdMs) async {
    await _invoke('setQuickFavComboConfig', {
      'combo': combo,
      'holdMs': holdMs.clamp(0, 8000),
    });
  }
}
