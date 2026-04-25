import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/stream_configuration.dart';
import '../../models/theme_config.dart';
import '../../providers/locale_provider.dart';
import '../../providers/plugins_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../models/computer_details.dart';
import '../../providers/computer_provider.dart';
import '../preferences/launcher_preferences.dart';
import '../pro/pro_service.dart';
import '../stream/host_preset_profiles.dart';

class CompanionServer {
  CompanionServer._();
  static final CompanionServer instance = CompanionServer._();

  HttpServer? _server;
  PluginsProvider? _plugins;
  SettingsProvider? _settingsProvider;
  LocaleProvider? _localeProvider;
  ThemeProvider? _themeProvider;
  LauncherPreferences? _launcherPreferences;
  ComputerProvider? _computerProvider;

  // Pairing state (ephemeral, lives only while a pairing attempt is active)
  String? _pairingPin;
  String _pairingStatus = 'idle'; // idle | waiting_pin | pairing | done | error
  String? _pairingError;

  static const int port = 9876;

  bool get isRunning => _server != null;

  void setComputerProvider(ComputerProvider provider) {
    _computerProvider = provider;
  }

  Future<void> start(
    PluginsProvider plugins, {
    SettingsProvider? settingsProvider,
    LocaleProvider? localeProvider,
    ThemeProvider? themeProvider,
    LauncherPreferences? launcherPreferences,
    ComputerProvider? computerProvider,
  }) async {
    _plugins = plugins;
    _settingsProvider = settingsProvider ?? _settingsProvider;
    _localeProvider = localeProvider ?? _localeProvider;
    _themeProvider = themeProvider ?? _themeProvider;
    _launcherPreferences = launcherPreferences ?? _launcherPreferences;
    _computerProvider = computerProvider ?? _computerProvider;
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server!.listen(_handleRequest);
      debugPrint('[CompanionServer] listening on port $port');
    } catch (e) {
      debugPrint('[CompanionServer] failed to bind: $e');
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<String?> get lanUrl async {
    final interfaces = await NetworkInterface.list();

    for (final iface in interfaces) {
      final n = iface.name.toLowerCase();
      if (!n.startsWith('wlan') && !n.startsWith('eth')) continue;
      for (final addr in iface.addresses) {
        if (addr.type == InternetAddressType.IPv4 &&
            !addr.isLoopback &&
            (addr.address.startsWith('192.168.') ||
                _isPrivate172(addr.address))) {
          debugPrint('[CompanionServer] using ${iface.name} → ${addr.address}');
          return 'http://${addr.address}:$port';
        }
      }
    }

    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (addr.type == InternetAddressType.IPv4 &&
            !addr.isLoopback &&
            (addr.address.startsWith('192.168.') ||
                _isPrivate172(addr.address))) {
          debugPrint('[CompanionServer] using ${iface.name} → ${addr.address}');
          return 'http://${addr.address}:$port';
        }
      }
    }

    for (final iface in interfaces) {
      if (_isMobileDataInterface(iface.name)) continue;
      for (final addr in iface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          debugPrint(
            '[CompanionServer] fallback ${iface.name} → ${addr.address}',
          );
          return 'http://${addr.address}:$port';
        }
      }
    }
    return null;
  }

  static bool _isMobileDataInterface(String name) {
    final n = name.toLowerCase();
    return n.startsWith('rmnet') ||
        n.startsWith('ccmni') ||
        n.startsWith('wwan') ||
        n.contains('mobile') ||
        n.startsWith('pdp_ip');
  }

  static bool _isPrivate172(String addr) {
    if (!addr.startsWith('172.')) return false;
    final second = int.tryParse(addr.split('.')[1]) ?? 0;
    return second >= 16 && second <= 31;
  }

  Map<String, dynamic> _buildHostPresetExport(
    Map<String, dynamic>? streamConfig,
  ) {
    final config = StreamConfiguration.fromJson(
      streamConfig ?? const <String, dynamic>{},
    );
    return buildHostPresetExport(config);
  }

  void _handleRequest(HttpRequest req) async {
    req.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method == 'OPTIONS') {
      req.response.statusCode = 204;
      await req.response.close();
      return;
    }

    final path = req.uri.path;

    if (path == '/' || path == '/index.html') {
      _serveWebUI(req);
      return;
    }

    if (path == '/api/config' && req.method == 'GET') {
      await _handleGetConfig(req);
      return;
    }

    if (path == '/api/config' && req.method == 'POST') {
      await _handlePostConfig(req);
      return;
    }

    if (path == '/api/servers' && req.method == 'GET') {
      await _handleGetServers(req);
      return;
    }

    if (path == '/api/pair' && req.method == 'POST') {
      await _handlePair(req);
      return;
    }

    if (path == '/api/pair/status' && req.method == 'GET') {
      await _handlePairStatus(req);
      return;
    }

    req.response
      ..statusCode = 404
      ..write('Not Found');
    await req.response.close();
  }

  Future<void> _handleGetConfig(HttpRequest req) async {
    final prefs = await SharedPreferences.getInstance();
    final plugins = _plugins;
    final settingsProvider = _settingsProvider;
    final localeProvider = _localeProvider;
    final themeProvider = _themeProvider;
    final launcherPreferences = _launcherPreferences;
    if (plugins == null) {
      req.response
        ..statusCode = 500
        ..write('Plugins not loaded');
      await req.response.close();
      return;
    }

    final steamApiKey = await plugins.getApiKey('steam_connect') ?? '';
    final steamId = await plugins.getSetting('steam_connect', 'steam_id') ?? '';
    final steamPersona =
        await plugins.getSetting('steam_connect', 'steam_persona') ?? '';
    final rawgApiKey = await plugins.getApiKey('metadata') ?? '';

    Map<String, dynamic>? streamConfig = settingsProvider?.config.toJson();
    if (streamConfig == null) {
      final streamJson = prefs.getString('stream_config');
      if (streamJson != null) {
        try {
          streamConfig = jsonDecode(streamJson) as Map<String, dynamic>;
        } catch (_) {}
      }
    }

    final config = <String, dynamic>{
      'steam_connect_enabled': plugins.isEnabled('steam_connect'),
      'metadata_enabled': plugins.isEnabled('metadata'),
      'game_video_enabled': plugins.isEnabled('game_video'),
      'smart_genre_filters_enabled': plugins.isEnabled('smart_genre_filters'),
      'steam_library_info_enabled': plugins.isEnabled('steam_library_info'),
      'discovery_boost_enabled': plugins.isEnabled('discovery_boost'),
      'startup_intro_video_enabled': plugins.isEnabled('startup_intro_video'),
      'screensaver_enabled': plugins.isEnabled('screensaver'),
      'achievements_overlay_enabled': plugins.isEnabled('steam_connect'),
      'screensaver_timeout_sec':
          int.tryParse(
            prefs.getString(
                  PluginsProvider.settingPref('screensaver', 'timeout_sec'),
                ) ??
                '',
          ) ??
          120,

      'steam_api_key': steamApiKey,
      'steam_id': steamId,
      'steam_persona': steamPersona,
      'rawg_api_key': rawgApiKey,

      'video_trigger':
          prefs.getString(
            PluginsProvider.settingPref('startup_intro_video', 'video_trigger'),
          ) ??
          'before_app',
      'microtrailer_muted': prefs.getBool('microtrailer_muted') ?? false,
      'microtrailer_delay_secs': prefs.getInt('microtrailer_delay_secs') ?? 3,

      'app_locale':
          localeProvider?.locale.languageCode ??
          prefs.getString('app_locale') ??
          'en',
      'app_theme':
          themeProvider?.themeId.name ?? prefs.getString('app_theme') ?? 'jujo',
      'reduce_effects':
          themeProvider?.reduceEffects ??
          prefs.getBool('reduce_effects') ??
          false,
      'performance_mode':
          themeProvider?.performanceMode ??
          prefs.getBool('performance_mode') ??
          false,

      'lp_bg_blur':
          launcherPreferences?.backgroundBlur ??
          prefs.getDouble('lp_bgBlur') ??
          1.0,
      'lp_bg_dim':
          launcherPreferences?.backgroundDim ??
          prefs.getDouble('lp_bgDim') ??
          0.28,
      'lp_card_border_radius':
          launcherPreferences?.cardBorderRadius ??
          prefs.getDouble('lp_cardRadius') ??
          7.0,
      'lp_card_width':
          launcherPreferences?.cardWidth ??
          prefs.getDouble('lp_cardWidth') ??
          156.0,
      'lp_card_height':
          launcherPreferences?.cardHeight ??
          prefs.getDouble('lp_cardHeight') ??
          214.0,
      'lp_card_spacing':
          launcherPreferences?.cardSpacing ??
          prefs.getDouble('lp_cardSpacing') ??
          10.0,
      'lp_show_labels':
          launcherPreferences?.showCardLabels ??
          prefs.getBool('lp_cardLabels') ??
          true,
      'lp_show_running_badge':
          launcherPreferences?.showRunningBadge ??
          prefs.getBool('lp_runningBadge') ??
          true,
      'lp_show_category_bar':
          launcherPreferences?.showCategoryBar ??
          prefs.getBool('lp_categoryBar') ??
          true,
      'lp_parallax':
          launcherPreferences?.enableParallaxDrift ??
          prefs.getBool('lp_parallax') ??
          true,

      'stream_width': streamConfig?['width'] ?? 1920,
      'stream_height': streamConfig?['height'] ?? 1080,
      'stream_fps': streamConfig?['fps'] ?? 60,
      'stream_bitrate': streamConfig?['bitrate'] ?? 20000,
      'stream_video_codec': streamConfig?['videoCodec'] ?? 0,
      'stream_enable_hdr': streamConfig?['enableHdr'] ?? false,
      'stream_smart_bitrate': streamConfig?['smartBitrateEnabled'] ?? false,
      'stream_smart_bitrate_min': streamConfig?['smartBitrateMin'] ?? 10000,
      'stream_smart_bitrate_max': streamConfig?['smartBitrateMax'] ?? 35000,
      'stream_dynamic_bitrate': streamConfig?['dynamicBitrateEnabled'] ?? false,
      'stream_dynamic_bitrate_sens':
          streamConfig?['dynamicBitrateSensitivity'] ?? 2,
      'stream_session_metrics': streamConfig?['enableSessionMetrics'] ?? false,
      'stream_host_preset_override':
          streamConfig?['hostPresetOverrideEnabled'] ?? false,
      'stream_host_preset_override_id':
          streamConfig?['hostPresetOverrideId'] ?? '',

      'stream_scale_mode': streamConfig?['scaleMode'] ?? 0,
      'stream_frame_pacing': streamConfig?['framePacing'] ?? 0,
      'stream_frame_queue_depth': streamConfig?['frameQueueDepth'] ?? 0,
      'stream_choreographer_vsync':
          streamConfig?['choreographerVsync'] ?? false,
      'stream_vrr': streamConfig?['enableVrr'] ?? false,
      'stream_direct_submit': streamConfig?['enableDirectSubmit'] ?? false,
      'stream_full_range': streamConfig?['fullRange'] ?? false,
      'stream_ultra_low_latency': streamConfig?['ultraLowLatency'] ?? false,
      'stream_low_latency_balance':
          streamConfig?['lowLatencyFrameBalance'] ?? false,
      'stream_pip': streamConfig?['pipEnabled'] ?? true,

      'stream_audio_config': streamConfig?['audioConfig'] ?? 0,
      'stream_audio_quality': streamConfig?['audioQuality'] ?? 0,
      'stream_play_local_audio': streamConfig?['playLocalAudio'] ?? false,
      'stream_audio_fx': streamConfig?['enableAudioFx'] ?? false,

      'stream_enable_sops': streamConfig?['enableSops'] ?? true,
      'stream_perf_overlay': streamConfig?['enablePerfOverlay'] ?? false,

      'stream_mouse_mode': streamConfig?['mouseMode'] ?? 0,
      'stream_mouse_emulation': streamConfig?['mouseEmulation'] ?? false,
      'stream_gamepad_mouse': streamConfig?['gamepadMouseEmulation'] ?? false,
      'stream_mouse_local_cursor': streamConfig?['mouseLocalCursor'] ?? false,
      'stream_multi_touch': streamConfig?['multiTouchGestures'] ?? false,
      'stream_absolute_mouse': streamConfig?['absoluteMouseMode'] ?? false,
      'stream_gamepad_mouse_speed': streamConfig?['gamepadMouseSpeed'] ?? 1.5,
      'stream_trackpad_x': streamConfig?['trackpadSensitivityX'] ?? 100,
      'stream_trackpad_y': streamConfig?['trackpadSensitivityY'] ?? 100,

      'stream_force_qwerty': streamConfig?['forceQwertyLayout'] ?? false,
      'stream_back_meta': streamConfig?['backButtonAsMeta'] ?? false,
      'stream_back_guide': streamConfig?['backButtonAsGuide'] ?? false,

      'stream_deadzone': streamConfig?['deadzone'] ?? 5,
      'stream_flip_face': streamConfig?['flipFaceButtons'] ?? false,
      'stream_multi_controller':
          streamConfig?['multiControllerEnabled'] ?? false,
      'stream_controller_count': streamConfig?['controllerCount'] ?? 0,
      'stream_controller_driver': streamConfig?['controllerDriver'] ?? 0,
      'stream_usb_driver': streamConfig?['usbDriverEnabled'] ?? false,
      'stream_usb_bind_all': streamConfig?['usbBindAll'] ?? false,
      'stream_joycon': streamConfig?['joyCon'] ?? false,
      'stream_battery_report': streamConfig?['gamepadBatteryReport'] ?? false,
      'stream_motion_sensors': streamConfig?['gamepadMotionSensors'] ?? false,
      'stream_motion_fallback': streamConfig?['gamepadMotionFallback'] ?? false,
      'stream_touchpad_mouse': streamConfig?['gamepadTouchpadAsMouse'] ?? false,
      'stream_button_remap': streamConfig?['buttonRemapProfile'] ?? 0,
      'stream_custom_remap':
          streamConfig?['customRemapTable'] ?? const <String, dynamic>{},
      'stream_overlay_trigger_combo':
          streamConfig?['overlayTriggerCombo'] ?? 0x00C0,
      'stream_overlay_trigger_hold_ms':
          streamConfig?['overlayTriggerHoldMs'] ?? 2000,

      'stream_rumble': streamConfig?['enableRumble'] ?? true,
      'stream_vibrate_fallback': streamConfig?['vibrateFallback'] ?? false,
      'stream_device_rumble': streamConfig?['deviceRumble'] ?? false,
      'stream_vibrate_strength':
          streamConfig?['vibrateFallbackStrength'] ?? 100,

      'stream_show_osc': streamConfig?['showOnscreenControls'] ?? true,
      'stream_hide_osc_gamepad': streamConfig?['hideOscWithGamepad'] ?? true,
      'stream_osc_opacity': streamConfig?['oscOpacity'] ?? 50,

      ..._buildHostPresetExport(streamConfig),
    };

    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(config));
    await req.response.close();
  }

  Future<void> _handlePostConfig(HttpRequest req) async {
    final plugins = _plugins;
    if (plugins == null) {
      req.response
        ..statusCode = 500
        ..write('Plugins not loaded');
      await req.response.close();
      return;
    }

    try {
      final body = await utf8.decoder.bind(req).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      final localeProvider = _localeProvider;
      final themeProvider = _themeProvider;
      final launcherPreferences = _launcherPreferences;
      final settingsProvider = _settingsProvider;

      for (final id in [
        'steam_connect',
        'metadata',
        'game_video',
        'smart_genre_filters',
        'steam_library_info',
        'discovery_boost',
        'startup_intro_video',
        'screensaver',
      ]) {
        final key = '${id}_enabled';
        if (data.containsKey(key)) {
          final wantEnabled = data[key] as bool;

          if (wantEnabled && !ProService().canEnablePlugin(id)) continue;
          await plugins.setEnabled(id, enabled: wantEnabled);
        }
      }

      if (data.containsKey('steam_api_key')) {
        await plugins.setApiKey(
          'steam_connect',
          (data['steam_api_key'] as String).trim(),
        );
      }
      if (data.containsKey('rawg_api_key')) {
        await plugins.setApiKey(
          'metadata',
          (data['rawg_api_key'] as String).trim(),
        );
      }

      if (data.containsKey('steam_id')) {
        await plugins.setSetting(
          'steam_connect',
          'steam_id',
          (data['steam_id'] as String).trim(),
        );
      }
      if (data.containsKey('video_trigger')) {
        await prefs.setString(
          PluginsProvider.settingPref('startup_intro_video', 'video_trigger'),
          data['video_trigger'] as String,
        );
      }
      if (data.containsKey('microtrailer_muted')) {
        await prefs.setBool(
          'microtrailer_muted',
          data['microtrailer_muted'] as bool,
        );
      }
      if (data.containsKey('microtrailer_delay_secs')) {
        await prefs.setInt(
          'microtrailer_delay_secs',
          (data['microtrailer_delay_secs'] as num).toInt(),
        );
      }
      if (data.containsKey('screensaver_timeout_sec')) {
        await prefs.setString(
          PluginsProvider.settingPref('screensaver', 'timeout_sec'),
          (data['screensaver_timeout_sec'] as num).toInt().toString(),
        );
      }

      if (data.containsKey('app_locale')) {
        final localeCode = data['app_locale'] as String;
        if (localeProvider != null) {
          await localeProvider.setByLanguageCode(localeCode);
        } else {
          await prefs.setString('app_locale', localeCode);
        }
      }
      if (data.containsKey('app_theme')) {
        final themeName = data['app_theme'] as String;
        if (themeProvider != null) {
          await themeProvider.setTheme(AppThemes.fromName(themeName));
        } else {
          await prefs.setString('app_theme', themeName);
        }
      }
      if (data.containsKey('reduce_effects')) {
        final reduceEffects = data['reduce_effects'] as bool;
        if (themeProvider != null) {
          await themeProvider.setReduceEffects(reduceEffects);
        } else {
          await prefs.setBool('reduce_effects', reduceEffects);
        }
      }
      if (data.containsKey('performance_mode')) {
        final performanceMode = data['performance_mode'] as bool;
        if (themeProvider != null) {
          await themeProvider.setPerformanceMode(performanceMode);
        } else {
          await prefs.setBool('performance_mode', performanceMode);
        }
      }

      if (data.containsKey('lp_bg_blur')) {
        final value = (data['lp_bg_blur'] as num).toDouble();
        if (launcherPreferences != null) {
          launcherPreferences.setBackgroundBlur(value);
        } else {
          await prefs.setDouble('lp_bgBlur', value);
        }
      }
      if (data.containsKey('lp_bg_dim')) {
        final value = (data['lp_bg_dim'] as num).toDouble();
        if (launcherPreferences != null) {
          launcherPreferences.setBackgroundDim(value);
        } else {
          await prefs.setDouble('lp_bgDim', value);
        }
      }
      if (data.containsKey('lp_card_border_radius')) {
        final value = (data['lp_card_border_radius'] as num).toDouble();
        if (launcherPreferences != null) {
          launcherPreferences.setCardBorderRadius(value);
        } else {
          await prefs.setDouble('lp_cardRadius', value);
        }
      }
      if (data.containsKey('lp_card_width')) {
        final value = (data['lp_card_width'] as num).toDouble();
        if (launcherPreferences != null) {
          launcherPreferences.setCardWidth(value);
        } else {
          await prefs.setDouble('lp_cardWidth', value);
        }
      }
      if (data.containsKey('lp_card_height')) {
        final value = (data['lp_card_height'] as num).toDouble();
        if (launcherPreferences != null) {
          launcherPreferences.setCardHeight(value);
        } else {
          await prefs.setDouble('lp_cardHeight', value);
        }
      }
      if (data.containsKey('lp_card_spacing')) {
        final value = (data['lp_card_spacing'] as num).toDouble();
        if (launcherPreferences != null) {
          launcherPreferences.setCardSpacing(value);
        } else {
          await prefs.setDouble('lp_cardSpacing', value);
        }
      }
      if (data.containsKey('lp_show_labels')) {
        final value = data['lp_show_labels'] as bool;
        if (launcherPreferences != null) {
          launcherPreferences.setShowCardLabels(value);
        } else {
          await prefs.setBool('lp_cardLabels', value);
        }
      }
      if (data.containsKey('lp_show_running_badge')) {
        final value = data['lp_show_running_badge'] as bool;
        if (launcherPreferences != null) {
          launcherPreferences.setShowRunningBadge(value);
        } else {
          await prefs.setBool('lp_runningBadge', value);
        }
      }
      if (data.containsKey('lp_show_category_bar')) {
        final value = data['lp_show_category_bar'] as bool;
        if (launcherPreferences != null) {
          launcherPreferences.setShowCategoryBar(value);
        } else {
          await prefs.setBool('lp_categoryBar', value);
        }
      }
      if (data.containsKey('lp_parallax')) {
        final value = data['lp_parallax'] as bool;
        if (launcherPreferences != null) {
          launcherPreferences.setEnableParallaxDrift(value);
        } else {
          await prefs.setBool('lp_parallax', value);
        }
      }

      final streamJson = prefs.getString('stream_config');
      final streamConfig = <String, dynamic>{};
      if (streamJson != null) {
        try {
          streamConfig.addAll(jsonDecode(streamJson) as Map<String, dynamic>);
        } catch (_) {}
      }
      bool streamChanged = false;
      for (final entry in {
        'stream_width': 'width',
        'stream_height': 'height',
        'stream_fps': 'fps',
        'stream_bitrate': 'bitrate',
        'stream_video_codec': 'videoCodec',
        'stream_enable_hdr': 'enableHdr',
        'stream_smart_bitrate': 'smartBitrateEnabled',
        'stream_smart_bitrate_min': 'smartBitrateMin',
        'stream_smart_bitrate_max': 'smartBitrateMax',
        'stream_dynamic_bitrate': 'dynamicBitrateEnabled',
        'stream_dynamic_bitrate_sens': 'dynamicBitrateSensitivity',
        'stream_session_metrics': 'enableSessionMetrics',
        'stream_host_preset_override': 'hostPresetOverrideEnabled',
        'stream_host_preset_override_id': 'hostPresetOverrideId',

        'stream_scale_mode': 'scaleMode',
        'stream_frame_pacing': 'framePacing',
        'stream_frame_queue_depth': 'frameQueueDepth',
        'stream_choreographer_vsync': 'choreographerVsync',
        'stream_vrr': 'enableVrr',
        'stream_direct_submit': 'enableDirectSubmit',
        'stream_full_range': 'fullRange',
        'stream_ultra_low_latency': 'ultraLowLatency',
        'stream_low_latency_balance': 'lowLatencyFrameBalance',
        'stream_pip': 'pipEnabled',

        'stream_audio_config': 'audioConfig',
        'stream_audio_quality': 'audioQuality',
        'stream_play_local_audio': 'playLocalAudio',
        'stream_audio_fx': 'enableAudioFx',

        'stream_enable_sops': 'enableSops',
        'stream_perf_overlay': 'enablePerfOverlay',

        'stream_mouse_mode': 'mouseMode',
        'stream_mouse_emulation': 'mouseEmulation',
        'stream_gamepad_mouse': 'gamepadMouseEmulation',
        'stream_mouse_local_cursor': 'mouseLocalCursor',
        'stream_multi_touch': 'multiTouchGestures',
        'stream_absolute_mouse': 'absoluteMouseMode',
        'stream_gamepad_mouse_speed': 'gamepadMouseSpeed',
        'stream_trackpad_x': 'trackpadSensitivityX',
        'stream_trackpad_y': 'trackpadSensitivityY',

        'stream_force_qwerty': 'forceQwertyLayout',
        'stream_back_meta': 'backButtonAsMeta',
        'stream_back_guide': 'backButtonAsGuide',

        'stream_deadzone': 'deadzone',
        'stream_flip_face': 'flipFaceButtons',
        'stream_multi_controller': 'multiControllerEnabled',
        'stream_controller_count': 'controllerCount',
        'stream_controller_driver': 'controllerDriver',
        'stream_usb_driver': 'usbDriverEnabled',
        'stream_usb_bind_all': 'usbBindAll',
        'stream_joycon': 'joyCon',
        'stream_battery_report': 'gamepadBatteryReport',
        'stream_motion_sensors': 'gamepadMotionSensors',
        'stream_motion_fallback': 'gamepadMotionFallback',
        'stream_touchpad_mouse': 'gamepadTouchpadAsMouse',
        'stream_button_remap': 'buttonRemapProfile',
        'stream_custom_remap': 'customRemapTable',
        'stream_overlay_trigger_combo': 'overlayTriggerCombo',
        'stream_overlay_trigger_hold_ms': 'overlayTriggerHoldMs',

        'stream_rumble': 'enableRumble',
        'stream_vibrate_fallback': 'vibrateFallback',
        'stream_device_rumble': 'deviceRumble',
        'stream_vibrate_strength': 'vibrateFallbackStrength',

        'stream_show_osc': 'showOnscreenControls',
        'stream_hide_osc_gamepad': 'hideOscWithGamepad',
        'stream_osc_opacity': 'oscOpacity',
      }.entries) {
        if (data.containsKey(entry.key)) {
          streamConfig[entry.value] = data[entry.key];
          streamChanged = true;
        }
      }
      if (streamChanged) {
        if (settingsProvider != null) {
          await settingsProvider.applySerializedConfig(streamConfig);
        } else {
          await prefs.setString('stream_config', jsonEncode(streamConfig));
        }
      }

      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': true}));
      await req.response.close();
    } catch (e) {
      req.response
        ..statusCode = 400
        ..write('Bad Request: $e');
      await req.response.close();
    }
  }

  Future<void> _handleGetServers(HttpRequest req) async {
    final provider = _computerProvider;
    if (provider == null) {
      req.response
        ..statusCode = 503
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'ComputerProvider not available'}));
      await req.response.close();
      return;
    }

    final servers = provider.computers.map((c) {
      final addr = c.activeAddress.isNotEmpty
          ? c.activeAddress
          : c.localAddress;
      return <String, dynamic>{
        'name': c.name,
        'address': addr,
        'uuid': c.uuid,
        'paired': c.pairState.name == 'paired',
        'online': c.state.name == 'online',
      };
    }).toList();

    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'servers': servers}));
    await req.response.close();
  }

  Future<void> _handlePair(HttpRequest req) async {
    final provider = _computerProvider;
    if (provider == null) {
      req.response
        ..statusCode = 503
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'ComputerProvider not available'}));
      await req.response.close();
      return;
    }

    try {
      final body = await utf8.decoder.bind(req).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final address = (data['address'] as String?)?.trim() ?? '';

      if (address.isEmpty) {
        req.response
          ..statusCode = 400
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Missing address'}));
        await req.response.close();
        return;
      }

      // Find or create the computer entry
      var computer = provider.computers.cast<ComputerDetails?>().firstWhere(
        (c) => c!.localAddress == address || c.activeAddress == address,
        orElse: () => null,
      );

      if (computer == null) {
        await provider.addComputerManually(address);
        computer = provider.computers.cast<ComputerDetails?>().firstWhere(
          (c) => c!.localAddress == address || c.activeAddress == address,
          orElse: () => null,
        );
      }

      if (computer == null) {
        req.response
          ..statusCode = 500
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Failed to add server'}));
        await req.response.close();
        return;
      }

      // Generate PIN and start pairing
      final pin = provider.generatePairingPin();
      _pairingPin = pin;
      _pairingStatus = 'waiting_pin';
      _pairingError = null;

      // Respond immediately with the PIN so the user can enter it in Sunshine
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': true, 'pin': pin, 'status': 'waiting_pin'}));
      await req.response.close();

      // Run pairing in background
      _pairingStatus = 'pairing';
      try {
        final result = await provider.pairComputer(computer, pin);
        if (result.paired) {
          _pairingStatus = 'done';
          _pairingError = null;
        } else {
          _pairingStatus = 'error';
          _pairingError = result.error ?? 'Pairing failed';
        }
      } catch (e) {
        _pairingStatus = 'error';
        _pairingError = e.toString();
      }
    } catch (e) {
      req.response
        ..statusCode = 400
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'Bad request: $e'}));
      await req.response.close();
    }
  }

  Future<void> _handlePairStatus(HttpRequest req) async {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'status': _pairingStatus,
          'pin': _pairingPin,
          if (_pairingError != null) 'error': _pairingError,
        }),
      );
    await req.response.close();
  }

  void _serveWebUI(HttpRequest req) {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(_companionHtml);
    req.response.close();
  }
}

const _companionHtml = r'''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>JUJO Companion Setup</title>
<style>
  :root { --bg: #0E0E1C; --card: #16192E; --card-v: #1C1D38; --accent: #6C3CE1; --accent-l: #9B71F5; --secondary: #1B3A6B; --highlight: #00E5FF; --muted: #2D2864; --r: 16px; }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
         background: var(--bg); color: #fff; min-height: 100vh; padding: 24px; }
  h1 { font-size: 1.6rem; margin-bottom: 8px; }
  .subtitle { color: #aaa; margin-bottom: 24px; }
  .lang-bar { display: flex; gap: 8px; margin-bottom: 20px; }
  .lang-bar button { padding: 6px 14px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.15);
    background: transparent; color: #aaa; cursor: pointer; font-size: 0.85rem; }
  .lang-bar button.active { background: var(--accent); color: #fff; border-color: var(--accent); }
  .card { background: var(--card); border-radius: var(--r); padding: 20px; margin-bottom: 16px;
          border: 1px solid rgba(255,255,255,0.08); }
  .card h2 { font-size: 1.1rem; margin-bottom: 12px; color: var(--accent-l); }
  label { display: block; color: #bbb; font-size: 0.85rem; margin-bottom: 4px; margin-top: 12px; }
  input[type="text"], input[type="password"], select {
    width: 100%; padding: 10px 12px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.12);
    background: rgba(255,255,255,0.04); color: #fff; font-size: 0.95rem; outline: none;
  }
  select { appearance: none; }
  input:focus, select:focus { border-color: var(--accent); }
  .toggle { display: flex; align-items: center; gap: 12px; margin-top: 12px; }
  .toggle span { color: #ddd; font-size: 0.9rem; }
  .switch { position: relative; display: inline-block; width: 44px; height: 24px; flex-shrink: 0; }
  .switch input { opacity: 0; width: 0; height: 0; }
  .switch .slider { position: absolute; cursor: pointer; inset: 0; background: rgba(255,255,255,0.12);
    border-radius: 24px; transition: background 0.2s; }
  .switch .slider::before { content: ''; position: absolute; width: 18px; height: 18px; left: 3px; bottom: 3px;
    background: #888; border-radius: 50%; transition: transform 0.2s, background 0.2s; }
  .switch input:checked + .slider { background: var(--accent); }
  .switch input:checked + .slider::before { transform: translateX(20px); background: #fff; }
  .btn { display: inline-block; padding: 12px 28px; border-radius: 10px; border: none;
         background: var(--accent); color: #fff; font-weight: 700; font-size: 1rem;
         cursor: pointer; margin-top: 20px; }
  .btn:hover { background: var(--accent-l); }
  .btn:disabled { opacity: 0.5; cursor: default; }
  .msg { margin-top: 12px; padding: 10px; border-radius: 8px; font-size: 0.9rem; }
  .msg.ok { background: rgba(0,229,83,0.15); color: #2ecc71; }
  .msg.err { background: rgba(255,60,60,0.15); color: #e74c3c; }
  .hint { color: #666; font-size: 0.8rem; margin-top: 4px; }
  .row { display: flex; gap: 12px; }
  .row > * { flex: 1; }
  textarea { width:100%; padding:10px 12px; border-radius:8px; border:1px solid rgba(255,255,255,0.12);
    background:rgba(255,255,255,0.04); color:#fff; font-size:0.85rem; outline:none; resize:vertical; font-family:inherit; }
  textarea:focus { border-color:var(--accent); }
  .srv-chip { display:flex; align-items:center; gap:8px; padding:8px 14px; border-radius:10px;
    background:var(--card-v); border:1px solid rgba(255,255,255,0.06); cursor:pointer;
    transition:border-color 0.15s, background 0.15s; font-size:0.85rem; }
  .srv-chip:hover { border-color:var(--accent); }
  .srv-chip .dot { width:8px; height:8px; border-radius:50%; flex-shrink:0; }
  .srv-chip .dot.on { background:#2ecc71; }
  .srv-chip .dot.off { background:#e74c3c; }
  .srv-chip .dot.unpaired { background:#f39c12; }
  .pin-display { text-align:center; padding:20px; background:var(--card-v); border-radius:var(--r);
    margin-top:12px; border:1px solid rgba(255,255,255,0.06); }
  .pin-display .pin-value { font-size:2.8rem; font-weight:800; letter-spacing:12px; color:var(--accent-l);
    font-variant-numeric:tabular-nums; }
  .pin-display .pin-label { color:#888; font-size:0.8rem; margin-bottom:6px; }
  .pin-display .pin-hint { color:#555; font-size:0.75rem; margin-top:6px; }
  .pair-status { margin-top:10px; padding:10px; border-radius:8px; font-size:0.85rem; }
  .pair-status.polling { background:rgba(108,60,225,0.1); color:var(--accent-l); }
  .pair-status.done { background:rgba(0,229,83,0.15); color:#2ecc71; }
  .pair-status.error { background:rgba(255,60,60,0.15); color:#e74c3c; }
  @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.4} }
  .pulsing { animation: pulse 1.5s ease-in-out infinite; }
</style>
</head>
<body>

<div class="lang-bar">
  <button id="btnEn" onclick="setLang('en')">English</button>
  <button id="btnEs" onclick="setLang('es')">Español</button>
</div>

<h1><span data-i18n="companionSetupTitle"></span></h1>
<p class="subtitle" data-i18n="subtitle"></p>

<!-- ── Server Pairing ── -->
<div class="card">
  <h2><span data-i18n="pairingTitle"></span></h2>
  <p style="color:#bbb;font-size:0.9rem;margin-bottom:12px"><span data-i18n="pairingDesc"></span></p>
  <div id="serverList" style="margin-bottom:8px;display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:8px"></div>
  <div class="row" style="align-items:flex-end">
    <div style="flex:2">
      <label data-i18n="pairingIpLabel"></label>
      <input type="text" id="pairIp" placeholder="192.168.1.100" inputmode="url">
    </div>
    <div style="flex:1">
      <label data-i18n="pairingPortLabel"></label>
      <input type="text" id="pairPort" placeholder="47989" inputmode="numeric" maxlength="5">
    </div>
    <button class="btn" id="pairBtn" style="margin-top:0;padding:10px 20px;font-size:0.9rem;flex-shrink:0" onclick="startPair()"><span data-i18n="pairBtn"></span></button>
  </div>
  <p class="hint" data-i18n="pairingPortHint"></p>
  <div id="pairResult" style="display:none">
    <div class="pin-display">
      <div class="pin-label"><span data-i18n="pairingPinLabel"></span></div>
      <div class="pin-value" id="pairPinValue"></div>
      <div class="pin-hint"><span data-i18n="pairingPinHint"></span></div>
    </div>
    <div id="pairStatusMsg" class="pair-status"></div>
  </div>
</div>

<!-- ── App Settings ── -->
<div class="card">
  <h2><span data-i18n="appSettings"></span></h2>
  <label data-i18n="languageLabel"></label>
  <select id="appLocale">
    <option value="en">English</option>
    <option value="es">Español</option>
  </select>
  <label data-i18n="themeLabel"></label>
  <select id="appTheme">
    <option value="jujo">JUJO Purple</option>
    <option value="midnight">Midnight Blue</option>
    <option value="oled">OLED Black</option>
    <option value="cyberpunk">Cyberpunk Neon</option>
    <option value="forest">Forest</option>
    <option value="sunset">Sunset</option>
    <option value="deBoosy">De Boosy</option>
    <option value="shioryPan">Shiory Pan</option>
    <option value="lazyAnkui">Lazy Ankui</option>
    <option value="ember">Ember</option>
    <option value="light">Light</option>
  </select>
  <div class="toggle"><input type="checkbox" id="reduceEffects"><span data-i18n="reduceEffects"></span></div>
  <div class="toggle"><input type="checkbox" id="performanceMode"><span data-i18n="performanceMode"></span></div>
</div>

<!-- ── Launcher Layout ── -->
<div class="card">
  <h2><span data-i18n="layoutTitle"></span></h2>
  <div class="row">
    <div>
      <label data-i18n="bgBlurLabel"></label>
      <input type="text" id="lpBgBlur" inputmode="decimal" placeholder="1.0">
    </div>
    <div>
      <label data-i18n="bgDimLabel"></label>
      <input type="text" id="lpBgDim" inputmode="decimal" placeholder="0.28">
    </div>
  </div>
  <div class="row">
    <div>
      <label data-i18n="cardWidthLabel"></label>
      <input type="text" id="lpCardWidth" inputmode="numeric" placeholder="156">
    </div>
    <div>
      <label data-i18n="cardHeightLabel"></label>
      <input type="text" id="lpCardHeight" inputmode="numeric" placeholder="214">
    </div>
  </div>
  <div class="row">
    <div>
      <label data-i18n="cardRadiusLabel"></label>
      <input type="text" id="lpCardRadius" inputmode="numeric" placeholder="7">
    </div>
    <div>
      <label data-i18n="cardSpacingLabel"></label>
      <input type="text" id="lpCardSpacing" inputmode="numeric" placeholder="10">
    </div>
  </div>
  <div class="toggle"><input type="checkbox" id="lpShowLabels"><span data-i18n="showLabels"></span></div>
  <div class="toggle"><input type="checkbox" id="lpRunningBadge"><span data-i18n="showRunning"></span></div>
  <div class="toggle"><input type="checkbox" id="lpCategoryBar"><span data-i18n="showCategories"></span></div>
  <div class="toggle"><input type="checkbox" id="lpParallax"><span data-i18n="enableParallax"></span></div>
</div>

<!-- ── Stream Config ── -->
<div class="card">
  <h2><span data-i18n="streamTitle"></span></h2>
  <div class="row">
    <div>
      <label data-i18n="resolution"></label>
      <select id="streamRes" onchange="onResChange()">
        <option value="854x480">480p (854×480)</option>
        <option value="960x540">540p (960×540)</option>
        <option value="1024x576">576p (1024×576)</option>
        <option value="1280x720">720p (1280×720)</option>
        <option value="1280x800">Steam Deck (1280×800)</option>
        <option value="1600x900">900p (1600×900)</option>
        <option value="1920x1080">1080p (1920×1080)</option>
        <option value="1920x1200">1200p (1920×1200)</option>
        <option value="2560x1080">UW 1080p (2560×1080)</option>
        <option value="2560x1440">1440p / 2K (2560×1440)</option>
        <option value="2560x1600">1600p / Legion Go (2560×1600)</option>
        <option value="3440x1440">UW 1440p (3440×1440)</option>
        <option value="3840x1600">UW 1600p (3840×1600)</option>
        <option value="3840x2160">4K UHD (3840×2160)</option>
        <option value="5120x1440">Super UW (5120×1440)</option>
        <option value="5120x2880">5K (5120×2880)</option>
        <option value="7680x4320">8K (7680×4320)</option>
        <option value="custom" data-i18n="customResLabel">Custom…</option>
      </select>
      <div id="customResBlock" style="display:none;margin-top:8px">
        <div class="row">
          <div><label data-i18n="widthLabel"></label><input type="text" id="customResW" inputmode="numeric" placeholder="1920"></div>
          <div><label data-i18n="heightLabel"></label><input type="text" id="customResH" inputmode="numeric" placeholder="1080"></div>
        </div>
      </div>
    </div>
    <div>
      <label data-i18n="fpsLabel"></label>
      <select id="streamFps">
        <option value="30">30</option>
        <option value="60">60</option>
        <option value="120">120</option>
      </select>
    </div>
  </div>
  <div id="manualBitrateBlock">
    <label data-i18n="bitrateLabel"></label>
    <input type="text" id="streamBitrate" inputmode="numeric" placeholder="20000">
    <p class="hint" data-i18n="bitrateHint"></p>
  </div>
  <label data-i18n="codecLabel"></label>
  <select id="streamCodec">
    <option value="0">H.264</option>
    <option value="1" data-i18n="hevcH265"></option>
    <option value="2">AV1</option>
  </select>
  <div class="toggle"><input type="checkbox" id="streamHdr"><span data-i18n="hdrLabel"></span></div>
  <div class="toggle"><input type="checkbox" id="smartBitrate"><span data-i18n="smartBitrate"></span></div>
  <div class="row" id="smartBitrateRange" style="display:none">
    <div>
      <label data-i18n="smartBitrateMin"></label>
      <input type="text" id="smartBitrateMin" inputmode="numeric" placeholder="10000">
    </div>
    <div>
      <label data-i18n="smartBitrateMax"></label>
      <input type="text" id="smartBitrateMax" inputmode="numeric" placeholder="35000">
    </div>
  </div>
  <p class="hint" data-i18n="smartBitrateHint"></p>
  <div class="toggle"><input type="checkbox" id="streamDynamicBitrate"><span data-i18n="dynamicBitrate"></span></div>
  <div class="row" id="dynamicBitrateRow" style="display:none">
    <div>
      <label data-i18n="dynamicBitrateSensitivity"></label>
      <select id="streamDynamicBitrateSens"><option value="1" data-i18n="conservativeLabel"></option><option value="2" data-i18n="balancedLabel"></option><option value="3" data-i18n="aggressiveLabel"></option></select>
    </div>
    <div>
      <label data-i18n="frameQueueDepth"></label>
      <input type="text" id="streamFrameQueueDepth" inputmode="numeric" placeholder="0">
    </div>
  </div>
  <label data-i18n="scaleMode"></label>
  <select id="streamScaleMode"><option value="0" data-i18n="fitLetterbox"></option><option value="1" data-i18n="fillCrop"></option><option value="2" data-i18n="stretchLabel"></option></select>
  <label data-i18n="framePacing"></label>
  <select id="streamFramePacing"><option value="0" data-i18n="lowestLatency"></option><option value="1" data-i18n="balancedLabel"></option><option value="2" data-i18n="capFps"></option><option value="3" data-i18n="smoothnessLabel"></option><option value="4" data-i18n="adaptiveLabel"></option></select>
  <div class="toggle"><input type="checkbox" id="streamFullRange"><span data-i18n="fullRangeColor"></span></div>
  <div class="toggle"><input type="checkbox" id="streamULL"><span data-i18n="ultraLowLatency"></span></div>
  <div class="toggle"><input type="checkbox" id="streamLLB"><span data-i18n="lowLatencyFrameBalance"></span></div>
  <div class="toggle"><input type="checkbox" id="streamPip"><span data-i18n="pipLabel"></span></div>
  <div class="toggle"><input type="checkbox" id="streamSops"><span data-i18n="optimizeGameSettings"></span></div>
  <div class="toggle"><input type="checkbox" id="streamPerfOverlay"><span data-i18n="performanceOverlayLabel"></span></div>
  <div class="toggle"><input type="checkbox" id="streamSessionMetrics"><span data-i18n="sessionMetrics"></span></div>
  <div class="toggle"><input type="checkbox" id="streamChoreoVsync"><span data-i18n="choreographerVsync"></span></div>
  <div class="toggle"><input type="checkbox" id="streamVrr"><span data-i18n="variableRefreshRate"></span></div>
  <div class="toggle"><input type="checkbox" id="streamDirectSubmit"><span data-i18n="directSubmit"></span></div>
</div>

<!-- ── Audio ── -->
<div class="card">
  <h2><span data-i18n="audioTitle"></span></h2>
  <label data-i18n="audioConfigLabel"></label>
  <select id="streamAudio"><option value="0" data-i18n="stereoLabel"></option><option value="1" data-i18n="surround51"></option><option value="2" data-i18n="surround71"></option></select>
  <label data-i18n="audioQualityLabel"></label>
  <select id="streamAudioQuality"><option value="0" data-i18n="highLabel"></option><option value="1" data-i18n="normalLabel"></option></select>
  <div class="toggle"><input type="checkbox" id="streamLocalAudio"><span data-i18n="playAudioOnPc"></span></div>
  <div class="toggle"><input type="checkbox" id="streamAudioFx"><span data-i18n="audioEffectsEq"></span></div>
</div>

<!-- ── Host Presets ── -->
<div class="card">
  <h2><span data-i18n="hostPresetTitle"></span></h2>
  <div class="toggle"><input type="checkbox" id="hostPresetOverride"><span data-i18n="hostPresetOverride"></span></div>
  <label data-i18n="hostPresetProfile"></label>
  <select id="hostPresetProfile">
    <option value="" data-i18n="hostPresetAuto"></option>
    <option value="nv_competitive_1080p60">NVIDIA · Competitive 1080p60</option>
    <option value="nv_balanced_1440p60">NVIDIA · Balanced 1440p60</option>
    <option value="nv_visual_4k60">NVIDIA · Visual 4K60</option>
    <option value="amd_competitive_1080p60">AMD · Competitive 1080p60</option>
    <option value="amd_balanced_1440p60">AMD · Balanced 1440p60</option>
    <option value="amd_visual_4k60">AMD · Visual 4K60</option>
  </select>
  <label data-i18n="hostPresetTier"></label>
  <input type="text" id="hostPresetTier" readonly>
  <div class="row">
    <div><label data-i18n="hostPresetNvidia"></label><input type="text" id="hostPresetNvidia" readonly></div>
    <div><label data-i18n="hostPresetAmd"></label><input type="text" id="hostPresetAmd" readonly></div>
  </div>
  <label data-i18n="hostPresetReason"></label>
  <textarea id="hostPresetReason" rows="3" readonly></textarea>
  <label data-i18n="hostPresetLaunchQuery"></label>
  <textarea id="hostPresetLaunchQuery" rows="4" readonly></textarea>
  <label data-i18n="hostPresetSunshinePayload"></label>
  <textarea id="hostPresetSunshinePayload" rows="6" readonly></textarea>
  <label data-i18n="hostPresetApolloPayload"></label>
  <textarea id="hostPresetApolloPayload" rows="5" readonly></textarea>
</div>

<!-- ── Input / Touch ── -->
<div class="card">
  <h2><span data-i18n="inputTouchTitle"></span></h2>
  <label data-i18n="touchMode"></label>
  <select id="streamMouseMode"><option value="0" data-i18n="directTouch"></option><option value="1" data-i18n="trackpadLabel"></option><option value="2" data-i18n="mouseLabel"></option></select>
  <div class="toggle"><input type="checkbox" id="streamMouseEmu"><span data-i18n="mouseEmulationStick"></span></div>
  <div class="toggle"><input type="checkbox" id="streamGamepadMouse"><span data-i18n="gamepadMouseLabel"></span></div>
  <label data-i18n="gamepadMouseSpeed"></label>
  <input type="text" id="streamGamepadMouseSpeed" inputmode="decimal" placeholder="1.5">
  <div class="toggle"><input type="checkbox" id="streamLocalCursor"><span data-i18n="localMouseCursor"></span></div>
  <div class="toggle"><input type="checkbox" id="streamAbsMouse"><span data-i18n="absoluteMouseMode"></span></div>
  <div class="toggle"><input type="checkbox" id="streamMultiTouch"><span data-i18n="multiTouchGestures"></span></div>
  <div class="row">
    <div><label data-i18n="trackpadSensitivityX"></label><input type="text" id="streamTrackpadX" inputmode="numeric" placeholder="100"></div>
    <div><label data-i18n="trackpadSensitivityY"></label><input type="text" id="streamTrackpadY" inputmode="numeric" placeholder="100"></div>
  </div>
</div>

<!-- ── Keyboard ── -->
<div class="card">
  <h2><span data-i18n="keyboardTitle"></span></h2>
  <div class="toggle"><input type="checkbox" id="streamQwerty"><span data-i18n="forceQwerty"></span></div>
  <div class="toggle"><input type="checkbox" id="streamBackMeta"><span data-i18n="backMeta"></span></div>
  <div class="toggle"><input type="checkbox" id="streamBackGuide"><span data-i18n="backGuide"></span></div>
</div>

<!-- ── Gamepad ── -->
<div class="card">
  <h2><span data-i18n="gamepadTitle"></span></h2>
  <label data-i18n="deadzoneLabel"></label>
  <input type="text" id="streamDeadzone" inputmode="numeric" placeholder="5">
  <div class="toggle"><input type="checkbox" id="streamFlipFace"><span data-i18n="flipFaceButtons"></span></div>
  <div class="toggle"><input type="checkbox" id="streamMultiCtrl"><span data-i18n="multipleControllers"></span></div>
  <label data-i18n="controllerCountLabel"></label>
  <input type="text" id="streamCtrlCount" inputmode="numeric" placeholder="0">
  <label data-i18n="controllerDriverLabel"></label>
  <select id="streamCtrlDriver"><option value="0" data-i18n="autoLabel"></option><option value="1">Xbox 360</option><option value="2">DualShock</option><option value="3">DualSense</option></select>
  <div class="toggle"><input type="checkbox" id="streamUsbDriver"><span data-i18n="xboxUsbDriver"></span></div>
  <div class="toggle"><input type="checkbox" id="streamUsbBindAll"><span data-i18n="usbBindAll"></span></div>
  <div class="toggle"><input type="checkbox" id="streamJoyCon"><span data-i18n="joyConSupport"></span></div>
  <div class="toggle"><input type="checkbox" id="streamBattery"><span data-i18n="batteryStatusReport"></span></div>
  <div class="toggle"><input type="checkbox" id="streamMotion"><span data-i18n="motionSensors"></span></div>
  <div class="toggle"><input type="checkbox" id="streamMotionFB"><span data-i18n="motionFallback"></span></div>
  <div class="toggle"><input type="checkbox" id="streamTouchpadMouse"><span data-i18n="touchpadAsMouse"></span></div>
  <label data-i18n="buttonRemapLabel"></label>
  <select id="streamBtnRemap"><option value="0" data-i18n="defaultLabel"></option><option value="1" data-i18n="nintendoSwap"></option><option value="2" data-i18n="southpawLabel"></option><option value="3" data-i18n="customLabel"></option></select>
  <label data-i18n="customRemapJson"></label>
  <textarea id="streamCustomRemap" rows="4" placeholder='{"4096":8192}'></textarea>
  <div class="row">
    <div><label data-i18n="overlayTriggerCombo"></label><input type="text" id="streamOverlayTriggerCombo" inputmode="numeric" placeholder="192"></div>
    <div><label data-i18n="overlayTriggerHold"></label><input type="text" id="streamOverlayTriggerHold" inputmode="numeric" placeholder="2000"></div>
  </div>
</div>

<!-- ── Vibration ── -->
<div class="card">
  <h2><span data-i18n="vibrationTitle"></span></h2>
  <div class="toggle"><input type="checkbox" id="streamRumble"><span data-i18n="vibrationRumble"></span></div>
  <div class="toggle"><input type="checkbox" id="streamVibFB"><span data-i18n="vibrationFallbackPhone"></span></div>
  <div class="toggle"><input type="checkbox" id="streamDevRumble"><span data-i18n="deviceRumbleMotor"></span></div>
  <label data-i18n="vibrationStrength"></label>
  <input type="text" id="streamVibStr" inputmode="numeric" placeholder="100">
</div>

<!-- ── On-Screen Controls ── -->
<div class="card">
  <h2><span data-i18n="onScreenControlsTitle"></span></h2>
  <div class="toggle"><input type="checkbox" id="streamShowOsc"><span data-i18n="showVirtualGamepad"></span></div>
  <div class="toggle"><input type="checkbox" id="streamHideOscGP"><span data-i18n="hideWithPhysicalGamepad"></span></div>
  <label data-i18n="opacityLabel"></label>
  <input type="text" id="streamOscOpacity" inputmode="numeric" placeholder="50">
</div>

<!-- ── VPN Guide ── -->
<div class="card">
  <h2><span data-i18n="vpnTitle"></span></h2>
  <p style="color:#bbb;font-size:0.9rem;line-height:1.5">
    <span data-i18n="vpnIntro"></span>
    <span data-i18n="vpnRecommended"></span>
  </p>
  <ul style="color:#aaa;font-size:0.85rem;margin:12px 0 0 20px;line-height:1.8">
    <li><a href="https://tailscale.com" target="_blank" style="color:var(--accent-l)">Tailscale</a><span data-i18n="tailscaleDesc"></span></li>
    <li><a href="https://zerotier.com" target="_blank" style="color:var(--accent-l)">ZeroTier</a><span data-i18n="zerotierDesc"></span></li>
    <li><a href="https://www.wireguard.com" target="_blank" style="color:var(--accent-l)">WireGuard</a><span data-i18n="wireguardDesc"></span></li>
  </ul>
  <p style="color:#666;font-size:0.8rem;margin-top:8px">
    <span data-i18n="vpnAfterConnect"></span>
  </p>
</div>

<!-- ── Steam Connect ── -->
<div class="card">
  <h2><span data-i18n="steamConnectTitle"></span></h2>
  <div class="toggle">
    <input type="checkbox" id="steamEnabled">
    <span data-i18n="enableSteam"></span>
  </div>
  <label for="steamKey" data-i18n="steamApiKeyLabel"></label>
  <input type="password" id="steamKey" data-placeholder-i18n="pasteSteamKey">
  <p class="hint"><span data-i18n="getSteamKey"></span> <a href="https://steamcommunity.com/dev/apikey" target="_blank" style="color:var(--accent-l)">steamcommunity.com/dev/apikey</a></p>
  <label for="steamId" data-i18n="steamIdLabel"></label>
  <input type="text" id="steamId" placeholder="76561198xxxxxxxxx" maxlength="17" inputmode="numeric" pattern="[0-9]*">
</div>

<!-- ── Metadata (RAWG) ── -->
<div class="card">
  <h2><span data-i18n="metadataTitle"></span></h2>
  <div class="toggle">
    <input type="checkbox" id="rawgEnabled">
    <span data-i18n="enableMetadata"></span>
  </div>
  <label for="rawgKey" data-i18n="rawgApiKeyLabel"></label>
  <input type="password" id="rawgKey" data-placeholder-i18n="pasteRawgKey">
  <p class="hint"><span data-i18n="getRawgKey"></span> <a href="https://rawg.io/apidocs" target="_blank" style="color:var(--accent-l)">rawg.io/apidocs</a></p>
</div>

<!-- ── Plugin Toggles ── -->
<div class="card">
  <h2><span data-i18n="pluginsTitle"></span></h2>
  <div class="toggle"><input type="checkbox" id="gameVideoEnabled"><span data-i18n="enableGameVideo"></span></div>
  <div class="toggle"><input type="checkbox" id="smartGenreEnabled"><span data-i18n="enableSmartGenre"></span></div>
  <div class="toggle"><input type="checkbox" id="steamLibEnabled"><span data-i18n="enableSteamLib"></span></div>
  <div class="toggle"><input type="checkbox" id="discoveryEnabled"><span data-i18n="enableDiscovery"></span></div>
  <div class="toggle"><input type="checkbox" id="introVideoEnabled"><span data-i18n="enableIntroVideo"></span></div>
  <div class="toggle"><input type="checkbox" id="screensaverEnabled"><span data-i18n="enableScreensaver"></span></div>
  <label data-i18n="screensaverTimeout"></label>
  <input type="range" id="screensaverTimeout" min="30" max="600" step="30" value="120">
  <span id="screensaverTimeoutLabel">2m</span>
  <div class="toggle"><input type="checkbox" id="achievementsEnabled"><span data-i18n="enableAchievements"></span></div>
  <div class="toggle"><input type="checkbox" id="microtrailerMuted"><span data-i18n="muteMicrotrailer"></span></div>
  <label data-i18n="microtrailerDelay"></label>
  <input type="text" id="microtrailerDelay" inputmode="numeric" pattern="[0-9]*" placeholder="3">
</div>

<!-- ── Support ── -->
<div class="card" style="text-align:center">
  <h2><span data-i18n="supportTitle"></span></h2>
  <p style="color:#bbb;font-size:0.9rem;margin-bottom:12px">
    <span data-i18n="supportIntro"></span>
  </p>
  <a href="https://ko-fi.com/jujodev" target="_blank" style="display:inline-block;padding:12px 28px;border-radius:10px;background:#FF5E5B;color:#fff;font-weight:700;font-size:1rem;text-decoration:none">
    <span data-i18n="kofiCta"></span>
  </a>
</div>

<button class="btn" id="saveBtn" onclick="save()"><span data-i18n="saveBtn"></span></button>
<div id="msg"></div>

<script>
const L = {
  en: {
    companionSetupTitle: 'JUJO Companion Setup',
    subtitle: 'Configure your JUJO TV from this device',
    steamConnectTitle: 'Steam Connect',
    enableSteam: 'Enable Steam Connect', enableMetadata: 'Enable Metadata',
    steamApiKeyLabel: 'Steam Web API Key', rawgApiKeyLabel: 'RAWG API Key',
    steamIdLabel: 'Steam ID (SteamID64 — 17 digits)',
    pasteSteamKey: 'Paste your Steam Web API Key', pasteRawgKey: 'Paste your RAWG API Key',
    getSteamKey: 'Get it at', getRawgKey: 'Sign up free at',
    metadataTitle: 'Metadata (RAWG)',
    pluginsTitle: 'Plugins', enableGameVideo: 'Game Videos & Trailers',
    enableSmartGenre: 'Smart Genre Filters', enableSteamLib: 'Steam Library Info',
    enableDiscovery: 'Discovery Boost', enableIntroVideo: 'Startup Intro Video',
    enableScreensaver: 'Screensaver', screensaverTimeout: 'Screensaver Timeout',
    enableAchievements: 'Achievements Overlay',
    muteMicrotrailer: 'Mute Micro-trailers', microtrailerDelay: 'Micro-trailer Delay (seconds)',
    appSettings: 'App Settings', languageLabel: 'Language', themeLabel: 'Color Theme',
    reduceEffects: 'Reduce Effects', performanceMode: 'Performance Mode',
    layoutTitle: 'Launcher Layout',
    bgBlurLabel: 'Background Blur', bgDimLabel: 'Background Dim',
    cardWidthLabel: 'Card Width (px)', cardHeightLabel: 'Card Height (px)',
    cardRadiusLabel: 'Border Radius (px)', cardSpacingLabel: 'Card Spacing (px)',
    showLabels: 'Show Card Labels', showRunning: 'Show Running Badge',
    showCategories: 'Show Category Bar', enableParallax: 'Parallax Animation',
    streamTitle: 'Streaming', resolution: 'Resolution', bitrateLabel: 'Bitrate (kbps)',
    fpsLabel: 'FPS',
    bitrateHint: 'Higher = better quality, more bandwidth', codecLabel: 'Video Codec',
    hevcH265: 'HEVC (H.265)', hdrLabel: 'HDR',
    smartBitrate: 'Smart Bitrate (auto-adjust)', smartBitrateMin: 'Min (kbps)', smartBitrateMax: 'Max (kbps)',
    smartBitrateHint: 'Measures network speed before each session and picks optimal bitrate',
    dynamicBitrate: 'Dynamic Bitrate', dynamicBitrateSensitivity: 'Dynamic Bitrate Sensitivity',
    conservativeLabel: 'Conservative', balancedLabel: 'Balanced', aggressiveLabel: 'Aggressive',
    frameQueueDepth: 'Frame Queue Depth', scaleMode: 'Scale Mode',
    fitLetterbox: 'Fit (letterbox)', fillCrop: 'Fill (crop)', stretchLabel: 'Stretch',
    framePacing: 'Frame Pacing', lowestLatency: 'Lowest latency', capFps: 'Cap FPS',
    smoothnessLabel: 'Smoothness', adaptiveLabel: 'Adaptive',
    fullRangeColor: 'Full Range Color (0-255)', ultraLowLatency: 'Ultra Low Latency',
    lowLatencyFrameBalance: 'Low Latency Frame Balance', pipLabel: 'Picture in Picture (PiP)',
    optimizeGameSettings: 'Optimize Game Settings', performanceOverlayLabel: 'Performance Overlay',
    sessionMetrics: 'Session Metrics', choreographerVsync: 'Choreographer Vsync',
    variableRefreshRate: 'Variable Refresh Rate', directSubmit: 'Direct Submit',
    audioTitle: 'Audio', audioConfigLabel: 'Audio Config', stereoLabel: 'Stereo',
    surround51: '5.1 Surround', surround71: '7.1 Surround',
    audioQualityLabel: 'Audio Quality', highLabel: 'High', normalLabel: 'Normal',
    playAudioOnPc: 'Play Audio on PC', audioEffectsEq: 'Local Audio Effects',
    hostPresetTitle: 'Host Encoder Presets', hostPresetOverride: 'Manual Override',
    hostPresetProfile: 'Override Profile', hostPresetAuto: 'Auto (recommended tier)', hostPresetTier: 'Recommended Tier',
    hostPresetNvidia: 'NVIDIA Preset ID', hostPresetAmd: 'AMD Preset ID',
    hostPresetReason: 'Selection Reason', hostPresetLaunchQuery: 'Launch Query Payload',
    hostPresetSunshinePayload: 'Sunshine Payload', hostPresetApolloPayload: 'Apollo Payload',
    inputTouchTitle: 'Input / Touch', touchMode: 'Touch Mode', directTouch: 'Direct Touch',
    trackpadLabel: 'Trackpad', mouseLabel: 'Mouse', mouseEmulationStick: 'Mouse Emulation (stick)',
    gamepadMouseLabel: 'Gamepad → Mouse', gamepadMouseSpeed: 'Gamepad Mouse Speed',
    localMouseCursor: 'Local Mouse Cursor', absoluteMouseMode: 'Absolute Mouse Mode',
    multiTouchGestures: 'Multi-Touch Gestures',
    trackpadSensitivityX: 'Trackpad Sensitivity X (%)', trackpadSensitivityY: 'Trackpad Sensitivity Y (%)',
    keyboardTitle: 'Keyboard', forceQwerty: 'Force QWERTY Layout',
    backMeta: 'Back = Meta (Win key)', backGuide: 'Back = Guide (Xbox)',
    gamepadTitle: 'Gamepad', deadzoneLabel: 'Deadzone (%)',
    flipFaceButtons: 'Flip Face Buttons (A↔B, X↔Y)', multipleControllers: 'Multiple Controllers',
    controllerCountLabel: 'Controller Count (0=auto)', controllerDriverLabel: 'Controller Driver',
    customResLabel: 'Custom…', widthLabel: 'Width (px)', heightLabel: 'Height (px)',
    autoLabel: 'Auto', xboxUsbDriver: 'Enhanced USB/XInput Detection', usbBindAll: 'USB Bind All',
    joyConSupport: 'Joy-Con Support', batteryStatusReport: 'Battery Status Report',
    motionSensors: 'Motion Sensors', motionFallback: 'Motion Fallback (touchscreen)',
    touchpadAsMouse: 'Touchpad as Mouse', buttonRemapLabel: 'Button Remap',
    defaultLabel: 'Default', nintendoSwap: 'Nintendo (A↔B, X↔Y)', southpawLabel: 'Southpaw',
    customLabel: 'Custom', customRemapJson: 'Custom Remap JSON',
    overlayTriggerCombo: 'Overlay Trigger Combo (bitmask)', overlayTriggerHold: 'Overlay Trigger Hold (ms)',
    vibrationTitle: 'Vibration', vibrationRumble: 'Vibration / Rumble',
    vibrationFallbackPhone: 'Vibration Fallback (phone)', deviceRumbleMotor: 'Device Rumble Motor',
    vibrationStrength: 'Vibration Strength (%)', onScreenControlsTitle: 'On-Screen Controls',
    showVirtualGamepad: 'Show Virtual Gamepad', hideWithPhysicalGamepad: 'Hide with Physical Gamepad',
    opacityLabel: 'Opacity (%)', vpnTitle: 'VPN / Remote Play',
    vpnIntro: 'To play from outside your home network, you need a VPN that connects your phone/TV to your PC\'s local network.',
    vpnRecommended: ' Recommended options:',
    tailscaleDesc: ' — Free, zero-config mesh VPN. Install on PC + phone/TV. Both devices get a virtual LAN IP.',
    zerotierDesc: ' — Similar to Tailscale, free for up to 25 devices.',
    wireguardDesc: ' — Fast, lightweight. Requires manual setup on your router or PC.',
    vpnAfterConnect: 'After connecting via VPN, use the VPN IP address of your PC as the server address in JUJO Stream.',
    supportTitle: 'Support Development',
    supportIntro: 'JUJO Stream is built by a solo developer. If you enjoy it, consider buying me a coffee!',
    kofiCta: 'Ko-fi — Buy me a coffee',
    pairingTitle: 'Server Pairing', pairingDesc: 'Pair with a Sunshine / Apollo host on your network.',
    pairingIpLabel: 'IP Address or Hostname', pairingPortLabel: 'Port', pairingPortHint: 'Leave port empty for default (47989). Use a custom port only if your host is configured differently.',
    pairingAddressLabel: 'Server IP Address', pairBtn: 'Pair',
    pairingPinLabel: 'Enter this PIN on your host', pairingPinHint: 'Open Sunshine/Apollo web UI and enter the PIN when prompted.',
    pairingPolling: 'Waiting for host to accept…', pairingDone: 'Paired successfully!',
    pairingError: 'Pairing failed', pairingNoServers: 'No servers discovered yet.',
    saveBtn: 'Save Configuration', saving: 'Saving…',
    saved: 'Configuration saved successfully', errLoad: 'Error loading config: ', errSave: 'Error: '
  },
  es: {
    companionSetupTitle: 'Configuración de JUJO Companion',
    subtitle: 'Configura tu JUJO TV desde este dispositivo',
    steamConnectTitle: 'Steam Connect',
    enableSteam: 'Habilitar Steam Connect', enableMetadata: 'Habilitar Metadata',
    steamApiKeyLabel: 'Steam Web API Key', rawgApiKeyLabel: 'RAWG API Key',
    steamIdLabel: 'Steam ID (SteamID64 — 17 dígitos)',
    pasteSteamKey: 'Pega tu Steam Web API Key', pasteRawgKey: 'Pega tu RAWG API Key',
    getSteamKey: 'Obtenla en', getRawgKey: 'Regístrate gratis en',
    metadataTitle: 'Metadata (RAWG)',
    pluginsTitle: 'Plugins', enableGameVideo: 'Videos y Tráilers de Juegos',
    enableSmartGenre: 'Filtros Inteligentes de Género', enableSteamLib: 'Info de Biblioteca Steam',
    enableDiscovery: 'Impulso de Descubrimiento', enableIntroVideo: 'Video Intro al Iniciar',
    enableScreensaver: 'Protector de Pantalla', screensaverTimeout: 'Tiempo de Espera del Protector',
    enableAchievements: 'Logros Overlay',
    muteMicrotrailer: 'Silenciar Micro-tráilers', microtrailerDelay: 'Demora de Micro-tráiler (segundos)',
    appSettings: 'Ajustes', languageLabel: 'Idioma', themeLabel: 'Tema de Color',
    reduceEffects: 'Reducir Efectos', performanceMode: 'Modo Rendimiento',
    layoutTitle: 'Diseño del Launcher',
    bgBlurLabel: 'Desenfoque Fondo', bgDimLabel: 'Oscurecer Fondo',
    cardWidthLabel: 'Ancho Tarjeta (px)', cardHeightLabel: 'Alto Tarjeta (px)',
    cardRadiusLabel: 'Radio Borde (px)', cardSpacingLabel: 'Espaciado (px)',
    showLabels: 'Mostrar Nombres', showRunning: 'Mostrar Indicador Activo',
    showCategories: 'Mostrar Barra de Categorías', enableParallax: 'Animación Parallax',
    streamTitle: 'Streaming', resolution: 'Resolución', bitrateLabel: 'Bitrate (kbps)',
    fpsLabel: 'FPS',
    bitrateHint: 'Mayor = mejor calidad, más ancho de banda', codecLabel: 'Códec de Video',
    saveBtn: 'Guardar Configuración', saving: 'Guardando…',
    smartBitrate: 'Smart Bitrate (auto-ajuste)', smartBitrateMin: 'Mín (kbps)', smartBitrateMax: 'Máx (kbps)',
    smartBitrateHint: 'Mide la velocidad de red antes de cada sesión y elige el bitrate óptimo',
    hevcH265: 'HEVC (H.265)', hdrLabel: 'HDR',
    dynamicBitrate: 'Bitrate dinámico', dynamicBitrateSensitivity: 'Sensibilidad de bitrate dinámico',
    conservativeLabel: 'Conservador', balancedLabel: 'Equilibrado', aggressiveLabel: 'Agresivo',
    frameQueueDepth: 'Profundidad de cola de frames', scaleMode: 'Modo de escala',
    fitLetterbox: 'Ajustar (barras)', fillCrop: 'Rellenar (recorte)', stretchLabel: 'Estirar',
    framePacing: 'Sincronización de frames', lowestLatency: 'Latencia más baja', capFps: 'Limitar FPS',
    smoothnessLabel: 'Suavidad', adaptiveLabel: 'Adaptativo',
    fullRangeColor: 'Color de rango completo (0-255)', ultraLowLatency: 'Ultra baja latencia',
    lowLatencyFrameBalance: 'Balance de frames en baja latencia', pipLabel: 'Picture in Picture (PiP)',
    optimizeGameSettings: 'Optimizar ajustes del juego', performanceOverlayLabel: 'Overlay de rendimiento',
    sessionMetrics: 'Métricas de sesión', choreographerVsync: 'Vsync con Choreographer',
    variableRefreshRate: 'Frecuencia de refresco variable', directSubmit: 'Direct Submit',
    audioTitle: 'Audio', audioConfigLabel: 'Configuración de audio', stereoLabel: 'Estéreo',
    surround51: 'Surround 5.1', surround71: 'Surround 7.1',
    audioQualityLabel: 'Calidad de audio', highLabel: 'Alta', normalLabel: 'Normal',
    playAudioOnPc: 'Reproducir audio en el PC', audioEffectsEq: 'Efectos locales de audio',
    hostPresetTitle: 'Presets del encoder del host', hostPresetOverride: 'Override manual',
    hostPresetProfile: 'Perfil de override', hostPresetAuto: 'Auto (nivel recomendado)', hostPresetTier: 'Nivel recomendado',
    hostPresetNvidia: 'ID de preset NVIDIA', hostPresetAmd: 'ID de preset AMD',
    hostPresetReason: 'Motivo de la selección', hostPresetLaunchQuery: 'Payload de lanzamiento',
    hostPresetSunshinePayload: 'Payload de Sunshine', hostPresetApolloPayload: 'Payload de Apollo',
    inputTouchTitle: 'Entrada / táctil', touchMode: 'Modo táctil', directTouch: 'Toque directo',
    trackpadLabel: 'Trackpad', mouseLabel: 'Ratón', mouseEmulationStick: 'Emulación de ratón (stick)',
    gamepadMouseLabel: 'Mando → ratón', gamepadMouseSpeed: 'Velocidad del ratón con mando',
    localMouseCursor: 'Cursor local del ratón', absoluteMouseMode: 'Modo de ratón absoluto',
    multiTouchGestures: 'Gestos multitáctiles',
    trackpadSensitivityX: 'Sensibilidad X del trackpad (%)', trackpadSensitivityY: 'Sensibilidad Y del trackpad (%)',
    keyboardTitle: 'Teclado', forceQwerty: 'Forzar layout QWERTY',
    backMeta: 'Atrás = Meta (tecla Win)', backGuide: 'Atrás = Guide (Xbox)',
    gamepadTitle: 'Mando', deadzoneLabel: 'Zona muerta (%)',
    flipFaceButtons: 'Invertir botones frontales (A↔B, X↔Y)', multipleControllers: 'Múltiples mandos',
    controllerCountLabel: 'Cantidad de mandos (0=auto)', controllerDriverLabel: 'Driver del mando',
    customResLabel: 'Personalizado…', widthLabel: 'Ancho (px)', heightLabel: 'Alto (px)',
    autoLabel: 'Auto', xboxUsbDriver: 'Deteccion USB/XInput mejorada', usbBindAll: 'Vincular todos los USB',
    joyConSupport: 'Soporte Joy-Con', batteryStatusReport: 'Reporte de batería',
    motionSensors: 'Sensores de movimiento', motionFallback: 'Respaldo de movimiento (pantalla táctil)',
    touchpadAsMouse: 'Touchpad como ratón', buttonRemapLabel: 'Remapeo de botones',
    defaultLabel: 'Predeterminado', nintendoSwap: 'Nintendo (A↔B, X↔Y)', southpawLabel: 'Southpaw',
    customLabel: 'Personalizado', customRemapJson: 'JSON de remapeo personalizado',
    overlayTriggerCombo: 'Combo del trigger del overlay (bitmask)', overlayTriggerHold: 'Mantener trigger del overlay (ms)',
    vibrationTitle: 'Vibración', vibrationRumble: 'Vibración / rumble',
    vibrationFallbackPhone: 'Respaldo de vibración (teléfono)', deviceRumbleMotor: 'Motor de vibración del dispositivo',
    vibrationStrength: 'Intensidad de vibración (%)', onScreenControlsTitle: 'Controles en pantalla',
    showVirtualGamepad: 'Mostrar mando virtual', hideWithPhysicalGamepad: 'Ocultar con mando físico',
    opacityLabel: 'Opacidad (%)', vpnTitle: 'VPN / juego remoto',
    vpnIntro: 'Para jugar fuera de tu red doméstica, necesitas una VPN que conecte tu teléfono/TV con la red local de tu PC.',
    vpnRecommended: ' Opciones recomendadas:',
    tailscaleDesc: ' — VPN mesh gratis y sin configuración complicada. Instálala en PC + teléfono/TV. Ambos dispositivos obtienen una IP de LAN virtual.',
    zerotierDesc: ' — Similar a Tailscale, gratis hasta 25 dispositivos.',
    wireguardDesc: ' — Rápido y liviano. Requiere configuración manual en tu router o PC.',
    vpnAfterConnect: 'Después de conectar la VPN, usa la IP VPN de tu PC como dirección del servidor en JUJO Stream.',
    supportTitle: 'Apoyar el desarrollo',
    supportIntro: 'JUJO Stream está hecho por un desarrollador en solitario. Si te gusta, considera invitarme un café.',
    kofiCta: 'Ko-fi — Invítame un café',
    pairingTitle: 'Emparejamiento de Servidor', pairingDesc: 'Empareja con un host Sunshine / Apollo en tu red.',
    pairingIpLabel: 'Dirección IP o Hostname', pairingPortLabel: 'Puerto', pairingPortHint: 'Deja el puerto vacío para usar el predeterminado (47989). Usa un puerto personalizado solo si tu host está configurado diferente.',
    pairingAddressLabel: 'Dirección IP del servidor', pairBtn: 'Emparejar',
    pairingPinLabel: 'Ingresa este PIN en tu host', pairingPinHint: 'Abre la interfaz web de Sunshine/Apollo e ingresa el PIN cuando se solicite.',
    pairingPolling: 'Esperando que el host acepte…', pairingDone: '¡Emparejado exitosamente!',
    pairingError: 'Error al emparejar', pairingNoServers: 'Aún no se han descubierto servidores.',
    saved: 'Configuración guardada correctamente', errLoad: 'Error cargando configuración: ', errSave: 'Error: '
  }
};

let lang = (navigator.language || 'en').startsWith('es') ? 'es' : 'en';

function setLang(l) {
  lang = l;
  document.getElementById('btnEn').className = l==='en' ? 'active' : '';
  document.getElementById('btnEs').className = l==='es' ? 'active' : '';
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const key = el.getAttribute('data-i18n');
    if (L[lang][key]) el.textContent = L[lang][key];
  });
  document.querySelectorAll('[data-placeholder-i18n]').forEach(el => {
    const key = el.getAttribute('data-placeholder-i18n');
    if (L[lang][key]) el.placeholder = L[lang][key];
  });
}

const base = location.origin;

async function load() {
  try {
    const r = await fetch(base + '/api/config');
    const c = await r.json();
    // Plugin toggles
    document.getElementById('steamEnabled').checked = c.steam_connect_enabled || false;
    document.getElementById('rawgEnabled').checked = c.metadata_enabled || false;
    document.getElementById('gameVideoEnabled').checked = c.game_video_enabled || false;
    document.getElementById('smartGenreEnabled').checked = c.smart_genre_filters_enabled || false;
    document.getElementById('steamLibEnabled').checked = c.steam_library_info_enabled || false;
    document.getElementById('discoveryEnabled').checked = c.discovery_boost_enabled || false;
    document.getElementById('introVideoEnabled').checked = c.startup_intro_video_enabled || false;
    document.getElementById('screensaverEnabled').checked = c.screensaver_enabled ?? true;
    document.getElementById('achievementsEnabled').checked = c.achievements_overlay_enabled || false;
    // Screensaver timeout slider
    const ssTimeout = c.screensaver_timeout_sec || 120;
    document.getElementById('screensaverTimeout').value = ssTimeout;
    const ssMin = Math.floor(ssTimeout / 60);
    const ssSec = ssTimeout % 60;
    document.getElementById('screensaverTimeoutLabel').textContent = ssSec === 0 ? ssMin + 'm' : ssMin + 'm ' + ssSec + 's';
    document.getElementById('screensaverTimeout').oninput = function() {
      const v = parseInt(this.value);
      const m = Math.floor(v / 60);
      const s = v % 60;
      document.getElementById('screensaverTimeoutLabel').textContent = s === 0 ? m + 'm' : m + 'm ' + s + 's';
    };
    // Plugin credentials
    document.getElementById('steamKey').value = c.steam_api_key || '';
    document.getElementById('steamId').value = c.steam_id || '';
    document.getElementById('rawgKey').value = c.rawg_api_key || '';
    // Plugin settings
    document.getElementById('microtrailerMuted').checked = c.microtrailer_muted || false;
    document.getElementById('microtrailerDelay').value = c.microtrailer_delay_secs || 3;
    // App settings
    document.getElementById('appLocale').value = c.app_locale || 'en';
    document.getElementById('appTheme').value = c.app_theme || 'jujo';
    document.getElementById('reduceEffects').checked = c.reduce_effects || false;
    document.getElementById('performanceMode').checked = c.performance_mode || false;
    // Launcher layout
    document.getElementById('lpBgBlur').value = c.lp_bg_blur ?? 1.0;
    document.getElementById('lpBgDim').value = c.lp_bg_dim ?? 0.28;
    document.getElementById('lpCardWidth').value = c.lp_card_width ?? 156;
    document.getElementById('lpCardHeight').value = c.lp_card_height ?? 214;
    document.getElementById('lpCardRadius').value = c.lp_card_border_radius ?? 7;
    document.getElementById('lpCardSpacing').value = c.lp_card_spacing ?? 10;
    document.getElementById('lpShowLabels').checked = c.lp_show_labels ?? true;
    document.getElementById('lpRunningBadge').checked = c.lp_show_running_badge ?? true;
    document.getElementById('lpCategoryBar').checked = c.lp_show_category_bar ?? true;
    document.getElementById('lpParallax').checked = c.lp_parallax ?? true;
    // Stream config
    const w = c.stream_width || 1920, h = c.stream_height || 1080;
    const presetVal = w + 'x' + h;
    const sel = document.getElementById('streamRes');
    if ([...sel.options].some(o => o.value === presetVal)) {
      sel.value = presetVal;
      document.getElementById('customResBlock').style.display = 'none';
    } else {
      sel.value = 'custom';
      document.getElementById('customResW').value = w;
      document.getElementById('customResH').value = h;
      document.getElementById('customResBlock').style.display = '';
    }
    document.getElementById('streamFps').value = String(c.stream_fps || 60);
    document.getElementById('streamBitrate').value = c.stream_bitrate || 20000;
    document.getElementById('streamCodec').value = String(c.stream_video_codec || 0);
    document.getElementById('streamHdr').checked = c.stream_enable_hdr || false;
    // Smart Bitrate
    const sb = c.stream_smart_bitrate || false;
    document.getElementById('smartBitrate').checked = sb;
    document.getElementById('smartBitrateMin').value = c.stream_smart_bitrate_min || 10000;
    document.getElementById('smartBitrateMax').value = c.stream_smart_bitrate_max || 35000;
    document.getElementById('manualBitrateBlock').style.display = sb ? 'none' : 'block';
    document.getElementById('smartBitrateRange').style.display = sb ? 'flex' : 'none';
    document.getElementById('smartBitrate').onchange = function() {
      document.getElementById('manualBitrateBlock').style.display = this.checked ? 'none' : 'block';
      document.getElementById('smartBitrateRange').style.display = this.checked ? 'flex' : 'none';
    };
    const dyn = c.stream_dynamic_bitrate || false;
    document.getElementById('streamDynamicBitrate').checked = dyn;
    document.getElementById('streamDynamicBitrateSens').value = String(c.stream_dynamic_bitrate_sens || 2);
    document.getElementById('streamFrameQueueDepth').value = c.stream_frame_queue_depth || 0;
    document.getElementById('dynamicBitrateRow').style.display = dyn ? 'flex' : 'none';
    document.getElementById('streamDynamicBitrate').onchange = function() {
      document.getElementById('dynamicBitrateRow').style.display = this.checked ? 'flex' : 'none';
    };
    // Video extras
    document.getElementById('streamScaleMode').value = String(c.stream_scale_mode || 0);
    document.getElementById('streamFramePacing').value = String(c.stream_frame_pacing || 0);
    document.getElementById('streamFullRange').checked = c.stream_full_range || false;
    document.getElementById('streamULL').checked = c.stream_ultra_low_latency || false;
    document.getElementById('streamLLB').checked = c.stream_low_latency_balance || false;
    document.getElementById('streamPip').checked = c.stream_pip ?? true;
    document.getElementById('streamSops').checked = c.stream_enable_sops ?? true;
    document.getElementById('streamPerfOverlay').checked = c.stream_perf_overlay || false;
    document.getElementById('streamSessionMetrics').checked = c.stream_session_metrics || false;
    document.getElementById('streamChoreoVsync').checked = c.stream_choreographer_vsync || false;
    document.getElementById('streamVrr').checked = c.stream_vrr || false;
    document.getElementById('streamDirectSubmit').checked = c.stream_direct_submit || false;
    // Audio
    document.getElementById('streamAudio').value = String(c.stream_audio_config || 0);
    document.getElementById('streamAudioQuality').value = String(c.stream_audio_quality || 0);
    document.getElementById('streamLocalAudio').checked = c.stream_play_local_audio || false;
    document.getElementById('streamAudioFx').checked = c.stream_audio_fx || false;
    document.getElementById('hostPresetOverride').checked = c.stream_host_preset_override || false;
    document.getElementById('hostPresetProfile').value = c.stream_host_preset_override_id || '';
    document.getElementById('hostPresetTier').value = c.host_preset_tier || '';
    document.getElementById('hostPresetNvidia').value = c.host_preset_nvidia_id || '';
    document.getElementById('hostPresetAmd').value = c.host_preset_amd_id || '';
    document.getElementById('hostPresetReason').value = c.host_preset_reason || '';
    document.getElementById('hostPresetLaunchQuery').value = JSON.stringify(c.host_preset_launch_query || {}, null, 2);
    document.getElementById('hostPresetSunshinePayload').value = JSON.stringify(c.host_preset_sunshine_payload || {}, null, 2);
    document.getElementById('hostPresetApolloPayload').value = JSON.stringify(c.host_preset_apollo_payload || {}, null, 2);
    const syncHostPresetOverrideState = function() {
      document.getElementById('hostPresetProfile').disabled = !document.getElementById('hostPresetOverride').checked;
    };
    document.getElementById('hostPresetOverride').onchange = syncHostPresetOverrideState;
    syncHostPresetOverrideState();
    // Input / Touch
    document.getElementById('streamMouseMode').value = String(c.stream_mouse_mode || 0);
    document.getElementById('streamMouseEmu').checked = c.stream_mouse_emulation || false;
    document.getElementById('streamGamepadMouse').checked = c.stream_gamepad_mouse || false;
    document.getElementById('streamGamepadMouseSpeed').value = c.stream_gamepad_mouse_speed || 1.5;
    document.getElementById('streamLocalCursor').checked = c.stream_mouse_local_cursor || false;
    document.getElementById('streamAbsMouse').checked = c.stream_absolute_mouse || false;
    document.getElementById('streamMultiTouch').checked = c.stream_multi_touch || false;
    document.getElementById('streamTrackpadX').value = c.stream_trackpad_x || 100;
    document.getElementById('streamTrackpadY').value = c.stream_trackpad_y || 100;
    // Keyboard
    document.getElementById('streamQwerty').checked = c.stream_force_qwerty || false;
    document.getElementById('streamBackMeta').checked = c.stream_back_meta || false;
    document.getElementById('streamBackGuide').checked = c.stream_back_guide || false;
    // Gamepad
    document.getElementById('streamDeadzone').value = c.stream_deadzone ?? 5;
    document.getElementById('streamFlipFace').checked = c.stream_flip_face || false;
    document.getElementById('streamMultiCtrl').checked = c.stream_multi_controller || false;
    document.getElementById('streamCtrlCount').value = c.stream_controller_count || 0;
    document.getElementById('streamCtrlDriver').value = String(c.stream_controller_driver || 0);
    document.getElementById('streamUsbDriver').checked = c.stream_usb_driver || false;
    document.getElementById('streamUsbBindAll').checked = c.stream_usb_bind_all || false;
    document.getElementById('streamJoyCon').checked = c.stream_joycon || false;
    document.getElementById('streamBattery').checked = c.stream_battery_report || false;
    document.getElementById('streamMotion').checked = c.stream_motion_sensors || false;
    document.getElementById('streamMotionFB').checked = c.stream_motion_fallback || false;
    document.getElementById('streamTouchpadMouse').checked = c.stream_touchpad_mouse || false;
    document.getElementById('streamBtnRemap').value = String(c.stream_button_remap || 0);
    document.getElementById('streamCustomRemap').value = JSON.stringify(c.stream_custom_remap || {}, null, 2);
    document.getElementById('streamOverlayTriggerCombo').value = c.stream_overlay_trigger_combo || 192;
    document.getElementById('streamOverlayTriggerHold').value = c.stream_overlay_trigger_hold_ms || 2000;
    // Vibration
    document.getElementById('streamRumble').checked = c.stream_rumble ?? true;
    document.getElementById('streamVibFB').checked = c.stream_vibrate_fallback || false;
    document.getElementById('streamDevRumble').checked = c.stream_device_rumble || false;
    document.getElementById('streamVibStr').value = c.stream_vibrate_strength || 100;
    // On-screen controls
    document.getElementById('streamShowOsc').checked = c.stream_show_osc ?? true;
    document.getElementById('streamHideOscGP').checked = c.stream_hide_osc_gamepad ?? true;
    document.getElementById('streamOscOpacity').value = c.stream_osc_opacity || 50;
  } catch(e) { showMsg(L[lang].errLoad + e, true); }
}

async function save() {
  const btn = document.getElementById('saveBtn');
  btn.disabled = true;
  btn.textContent = L[lang].saving;
  try {
    const resVal = document.getElementById('streamRes').value;
    let resW, resH;
    if (resVal === 'custom') {
      resW = parseInt(document.getElementById('customResW').value) || 1920;
      resH = parseInt(document.getElementById('customResH').value) || 1080;
    } else {
      const res = resVal.split('x');
      resW = parseInt(res[0]); resH = parseInt(res[1]);
    }
    const body = {
      // Plugin toggles
      steam_connect_enabled: document.getElementById('steamEnabled').checked,
      metadata_enabled: document.getElementById('rawgEnabled').checked,
      game_video_enabled: document.getElementById('gameVideoEnabled').checked,
      smart_genre_filters_enabled: document.getElementById('smartGenreEnabled').checked,
      steam_library_info_enabled: document.getElementById('steamLibEnabled').checked,
      discovery_boost_enabled: document.getElementById('discoveryEnabled').checked,
      startup_intro_video_enabled: document.getElementById('introVideoEnabled').checked,
      screensaver_enabled: document.getElementById('screensaverEnabled').checked,
      screensaver_timeout_sec: parseInt(document.getElementById('screensaverTimeout').value) || 120,
      // Plugin credentials
      steam_api_key: document.getElementById('steamKey').value,
      steam_id: document.getElementById('steamId').value,
      rawg_api_key: document.getElementById('rawgKey').value,
      // Plugin settings
      microtrailer_muted: document.getElementById('microtrailerMuted').checked,
      microtrailer_delay_secs: parseInt(document.getElementById('microtrailerDelay').value) || 3,
      // App settings
      app_locale: document.getElementById('appLocale').value,
      app_theme: document.getElementById('appTheme').value,
      reduce_effects: document.getElementById('reduceEffects').checked,
      performance_mode: document.getElementById('performanceMode').checked,
      // Launcher layout
      lp_bg_blur: parseFloat(document.getElementById('lpBgBlur').value) || 1.0,
      lp_bg_dim: parseFloat(document.getElementById('lpBgDim').value) || 0.28,
      lp_card_width: parseFloat(document.getElementById('lpCardWidth').value) || 156,
      lp_card_height: parseFloat(document.getElementById('lpCardHeight').value) || 214,
      lp_card_border_radius: parseFloat(document.getElementById('lpCardRadius').value) || 7,
      lp_card_spacing: parseFloat(document.getElementById('lpCardSpacing').value) || 10,
      lp_show_labels: document.getElementById('lpShowLabels').checked,
      lp_show_running_badge: document.getElementById('lpRunningBadge').checked,
      lp_show_category_bar: document.getElementById('lpCategoryBar').checked,
      lp_parallax: document.getElementById('lpParallax').checked,
      // Stream config
      stream_width: resW,
      stream_height: resH,
      stream_fps: parseInt(document.getElementById('streamFps').value),
      stream_bitrate: parseInt(document.getElementById('streamBitrate').value) || 20000,
      stream_video_codec: parseInt(document.getElementById('streamCodec').value),
      stream_enable_hdr: document.getElementById('streamHdr').checked,
      stream_smart_bitrate: document.getElementById('smartBitrate').checked,
      stream_smart_bitrate_min: parseInt(document.getElementById('smartBitrateMin').value) || 10000,
      stream_smart_bitrate_max: parseInt(document.getElementById('smartBitrateMax').value) || 35000,
      stream_dynamic_bitrate: document.getElementById('streamDynamicBitrate').checked,
      stream_dynamic_bitrate_sens: parseInt(document.getElementById('streamDynamicBitrateSens').value) || 2,
      // Video extras
      stream_scale_mode: parseInt(document.getElementById('streamScaleMode').value),
      stream_frame_pacing: parseInt(document.getElementById('streamFramePacing').value),
      stream_frame_queue_depth: parseInt(document.getElementById('streamFrameQueueDepth').value) || 0,
      stream_full_range: document.getElementById('streamFullRange').checked,
      stream_ultra_low_latency: document.getElementById('streamULL').checked,
      stream_low_latency_balance: document.getElementById('streamLLB').checked,
      stream_pip: document.getElementById('streamPip').checked,
      stream_enable_sops: document.getElementById('streamSops').checked,
      stream_perf_overlay: document.getElementById('streamPerfOverlay').checked,
      stream_session_metrics: document.getElementById('streamSessionMetrics').checked,
      stream_choreographer_vsync: document.getElementById('streamChoreoVsync').checked,
      stream_vrr: document.getElementById('streamVrr').checked,
      stream_direct_submit: document.getElementById('streamDirectSubmit').checked,
      // Audio
      stream_audio_config: parseInt(document.getElementById('streamAudio').value),
      stream_audio_quality: parseInt(document.getElementById('streamAudioQuality').value),
      stream_play_local_audio: document.getElementById('streamLocalAudio').checked,
      stream_audio_fx: document.getElementById('streamAudioFx').checked,
      stream_host_preset_override: document.getElementById('hostPresetOverride').checked,
      stream_host_preset_override_id: document.getElementById('hostPresetProfile').value,
      // Input / Touch
      stream_mouse_mode: parseInt(document.getElementById('streamMouseMode').value),
      stream_mouse_emulation: document.getElementById('streamMouseEmu').checked,
      stream_gamepad_mouse: document.getElementById('streamGamepadMouse').checked,
      stream_gamepad_mouse_speed: parseFloat(document.getElementById('streamGamepadMouseSpeed').value) || 1.5,
      stream_mouse_local_cursor: document.getElementById('streamLocalCursor').checked,
      stream_absolute_mouse: document.getElementById('streamAbsMouse').checked,
      stream_multi_touch: document.getElementById('streamMultiTouch').checked,
      stream_trackpad_x: parseInt(document.getElementById('streamTrackpadX').value) || 100,
      stream_trackpad_y: parseInt(document.getElementById('streamTrackpadY').value) || 100,
      // Keyboard
      stream_force_qwerty: document.getElementById('streamQwerty').checked,
      stream_back_meta: document.getElementById('streamBackMeta').checked,
      stream_back_guide: document.getElementById('streamBackGuide').checked,
      // Gamepad
      stream_deadzone: parseInt(document.getElementById('streamDeadzone').value) || 5,
      stream_flip_face: document.getElementById('streamFlipFace').checked,
      stream_multi_controller: document.getElementById('streamMultiCtrl').checked,
      stream_controller_count: parseInt(document.getElementById('streamCtrlCount').value) || 0,
      stream_controller_driver: parseInt(document.getElementById('streamCtrlDriver').value),
      stream_usb_driver: document.getElementById('streamUsbDriver').checked,
      stream_usb_bind_all: document.getElementById('streamUsbBindAll').checked,
      stream_joycon: document.getElementById('streamJoyCon').checked,
      stream_battery_report: document.getElementById('streamBattery').checked,
      stream_motion_sensors: document.getElementById('streamMotion').checked,
      stream_motion_fallback: document.getElementById('streamMotionFB').checked,
      stream_touchpad_mouse: document.getElementById('streamTouchpadMouse').checked,
      stream_button_remap: parseInt(document.getElementById('streamBtnRemap').value),
      stream_custom_remap: (() => { try { return JSON.parse(document.getElementById('streamCustomRemap').value || '{}'); } catch (_) { return {}; } })(),
      stream_overlay_trigger_combo: parseInt(document.getElementById('streamOverlayTriggerCombo').value) || 192,
      stream_overlay_trigger_hold_ms: parseInt(document.getElementById('streamOverlayTriggerHold').value) || 2000,
      // Vibration
      stream_rumble: document.getElementById('streamRumble').checked,
      stream_vibrate_fallback: document.getElementById('streamVibFB').checked,
      stream_device_rumble: document.getElementById('streamDevRumble').checked,
      stream_vibrate_strength: parseInt(document.getElementById('streamVibStr').value) || 100,
      // On-screen controls
      stream_show_osc: document.getElementById('streamShowOsc').checked,
      stream_hide_osc_gamepad: document.getElementById('streamHideOscGP').checked,
      stream_osc_opacity: parseInt(document.getElementById('streamOscOpacity').value) || 50,
    };
    const r = await fetch(base + '/api/config', {
      method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(body)
    });
    if (r.ok) showMsg(L[lang].saved, false);
    else showMsg(L[lang].errSave + await r.text(), true);
  } catch(e) { showMsg(L[lang].errSave + e, true); }
  btn.disabled = false;
  btn.textContent = L[lang].saveBtn;
}

function onResChange() {
  const v = document.getElementById('streamRes').value;
  document.getElementById('customResBlock').style.display = v === 'custom' ? '' : 'none';
}

function showMsg(text, isErr) {
  const el = document.getElementById('msg');
  el.className = 'msg ' + (isErr ? 'err' : 'ok');
  el.textContent = text;
  setTimeout(() => el.textContent = '', 5000);
}

function initToggles() {
  document.querySelectorAll('.toggle input[type="checkbox"]').forEach(cb => {
    const lbl = document.createElement('label');
    lbl.className = 'switch';
    const slider = document.createElement('span');
    slider.className = 'slider';
    cb.parentNode.insertBefore(lbl, cb);
    lbl.appendChild(cb);
    lbl.appendChild(slider);
  });
}
initToggles();
// ── Pairing functions ──
let _pairPollTimer = null;

async function loadServers() {
  const el = document.getElementById('serverList');
  try {
    const r = await fetch(base + '/api/servers');
    const d = await r.json();
    if (!d.servers || d.servers.length === 0) {
      el.innerHTML = '<span style="color:#666;font-size:0.85rem">' + L[lang].pairingNoServers + '</span>';
      return;
    }
    el.innerHTML = d.servers.map(s => {
      const dotCls = s.paired ? (s.online ? 'on' : 'off') : 'unpaired';
      const label = s.name + ' (' + s.address + ')';
      return '<div class="srv-chip" onclick="document.getElementById(\'pairIp\').value=\'' + s.address + '\';document.getElementById(\'pairPort\').value=\'\';">'
        + '<span class="dot ' + dotCls + '"></span>' + label + '</div>';
    }).join('');
  } catch(e) { el.innerHTML = ''; }
}

async function startPair() {
const ip = document.getElementById('pairIp').value.trim();
if (!ip) return;
const port = document.getElementById('pairPort').value.trim();
const addr = port ? ip + ':' + port : ip;
  const btn = document.getElementById('pairBtn');
  btn.disabled = true;
  const resultEl = document.getElementById('pairResult');
  const pinEl = document.getElementById('pairPinValue');
  const statusEl = document.getElementById('pairStatusMsg');
  resultEl.style.display = 'none';
  statusEl.className = 'pair-status';
  statusEl.textContent = '';
  try {
    const r = await fetch(base + '/api/pair', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({address: addr})
    });
    const d = await r.json();
    if (!r.ok) { throw new Error(d.error || 'Request failed'); }
    pinEl.textContent = d.pin;
    resultEl.style.display = 'block';
    statusEl.className = 'pair-status polling pulsing';
    statusEl.textContent = L[lang].pairingPolling;
    pollPairStatus();
  } catch(e) {
    resultEl.style.display = 'block';
    pinEl.textContent = '----';
    statusEl.className = 'pair-status error';
    statusEl.textContent = L[lang].pairingError + ': ' + e.message;
    btn.disabled = false;
  }
}

function pollPairStatus() {
  if (_pairPollTimer) clearInterval(_pairPollTimer);
  const statusEl = document.getElementById('pairStatusMsg');
  const btn = document.getElementById('pairBtn');
  let attempts = 0;
  _pairPollTimer = setInterval(async () => {
    attempts++;
    if (attempts > 60) { // 60s timeout
      clearInterval(_pairPollTimer);
      statusEl.className = 'pair-status error';
      statusEl.textContent = L[lang].pairingError + ': timeout';
      btn.disabled = false;
      return;
    }
    try {
      const r = await fetch(base + '/api/pair/status');
      const d = await r.json();
      if (d.status === 'done') {
        clearInterval(_pairPollTimer);
        statusEl.className = 'pair-status done';
        statusEl.textContent = L[lang].pairingDone;
        btn.disabled = false;
        loadServers();
      } else if (d.status === 'error') {
        clearInterval(_pairPollTimer);
        statusEl.className = 'pair-status error';
        statusEl.textContent = L[lang].pairingError + ': ' + (d.error || '');
        btn.disabled = false;
      }
    } catch(e) {}
  }, 1000);
}

setLang(lang);
load();
loadServers();
</script>
</body>
</html>
''';
