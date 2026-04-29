import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/computer_details.dart';
import '../../models/nv_app.dart';
import '../../models/stream_configuration.dart';
import '../../platform_channels/gamepad_channel.dart';
import '../../platform_channels/streaming_channel.dart';
import '../../providers/app_list_provider.dart';
import '../../providers/computer_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/audio/ui_sound_service.dart';
import '../../services/pro/pro_service.dart';
import '../../services/telemetry/beta_telemetry_service.dart';
import '../../services/input/gamepad_button_helper.dart';
import '../../services/stream/image_load_throttle.dart';
import '../../widgets/session_metrics_dialog.dart';
import '../../widgets/virtual_gamepad/virtual_gamepad_overlay.dart';
import 'direct_touch_handler.dart';
import 'dynamic_bitrate_controller.dart';
import 'perf_stats_overlay.dart';
import 'quick_keys_overlay.dart';
import 'special_keys.dart';
import 'stream_overlay_widgets.dart';
import 'trackpad_input_handler.dart';

class GameStreamScreen extends StatefulWidget {
  final ComputerDetails computer;
  final NvApp app;
  final String riKey;
  final int riKeyId;
  final String? rtspSessionUrl;
  final StreamConfiguration? overrideConfig;

  const GameStreamScreen({
    super.key,
    required this.computer,
    required this.app,
    this.riKey = '',
    this.riKeyId = 0,
    this.rtspSessionUrl,
    this.overrideConfig,
  });

  @override
  State<GameStreamScreen> createState() => _GameStreamScreenState();
}

class _GameStreamScreenState extends State<GameStreamScreen>
    with WidgetsBindingObserver {
  static const int _reconnectCooldownMs = 8000;

  static DateTime? _lastDisconnectTime;

  // prevents overlapping start/stop — completes when native stop finishes
  static Completer<void>? _pendingStop;

  int? _textureId;
  late StreamConfiguration _config;
  bool _isConnecting = true;
  bool _isConnected = false;
  String? _error;
  bool _showOverlay = false;
  bool _overlayTransitioning = false;
  bool _showPerfStats = false;
  bool _usingDirectSubmit = false;
  bool _showGamepad = false;
  bool _showSpecialKeys = false;
  int _specialKeyIdx = 0;

  bool _showQuickKeys = false;
  final GlobalKey<QuickKeysOverlayState> _quickKeysKey =
      GlobalKey<QuickKeysOverlayState>();

  bool _showQuitConfirm = false;
  int _quitConfirmSelection = 0;
  int _overlayRow = 0;
  int _overlayCol = 0;
  double _gamepadOpacity = 0.6;
  int _activeControllerSlot = 0;

  String? _activeOverlayPreset;

  bool _isReconnecting = false;
  int _presetReconnectRetries = 0;
  static const int _maxPresetReconnectRetries = 2;

  bool _userInitiatedQuit = false;
  bool _clearActiveSessionOnExit = false;
  bool _stopInFlight = false;
  bool _streamStopped = false;
  DateTime? _ignoreTerminationUntil;

  late MouseMode _touchMode;

  bool _gamepadMouseActive = false;

  // M7: local cursor overlay
  double _cursorX = -1, _cursorY = -1;
  bool _cursorVisible = false;
  int _cursorHideTimer = 0;

  final Set<LogicalKeyboardKey> _heldButtons = {};
  DateTime? _startPressedAt;

  final FocusNode _streamFocusNode = FocusNode(debugLabel: 'game-stream');

  final FocusNode _overlayFocusNode = FocusNode(debugLabel: 'overlay-menu');

  final ScrollController _overlayScrollController = ScrollController();

  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'hidden-keyboard');
  final TextEditingController _keyboardController = TextEditingController();
  bool _keyboardVisible = false;

  bool _panZoomActive = false;
  final TransformationController _panZoomCtrl = TransformationController();

  // live in TrackpadInputHandler; this class only provides the callbacks.
  late final TrackpadInputHandler _trackpadHandler = TrackpadInputHandler(
    onMouseMove: StreamingPlatformChannel.sendMouseMove,
    onMouseButton: StreamingPlatformChannel.sendMouseButton,
    onScroll: StreamingPlatformChannel.sendScroll,
    onHScroll: StreamingPlatformChannel.sendHighResHScroll,
    isMounted: () => mounted,
  );

  late final DirectTouchHandler _directTouchHandler = DirectTouchHandler(
    onMousePosition: StreamingPlatformChannel.sendMousePosition,
    onMouseButton: StreamingPlatformChannel.sendMouseButton,
    onTouchEvent: StreamingPlatformChannel.sendTouchEvent,
    touchToStreamCoords: _touchToStreamCoords,
    updateLocalCursor: _updateLocalCursor,
    isMounted: () => mounted,
    getScreenSize: () => MediaQuery.sizeOf(context),
    getStreamWidth: () => _config.width,
    getStreamHeight: () => _config.height,
  );

  String _fps = '--';
  String _latency = '--';
  String _bitrate = '--';

  late final DynamicBitrateController _dynBitrate = DynamicBitrateController(
    onReconnectNeeded: _onDynBitrateReconnect,
  );

  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const List<int> _reconnectDelaysSeconds = [1, 2, 4, 8, 16];
  String? _reconnectMessage;

  String _currentStageName = '';
  int _currentStageIndex = 0;
  final List<SessionMetricPoint> _sessionMetrics = <SessionMetricPoint>[];
  DateTime? _sessionMetricsStartedAt;
  bool _sessionMetricsDialogShown = false;
  late final SettingsProvider _settingsProvider;
  StreamSubscription<Map<String, dynamic>>? _statsSubscription;
  int _statsTelemetryTicks = 0;

  late ComputerProvider _computerProvider;

  @override
  void initState() {
    super.initState();
    ImageLoadThrottle.pauseForStream();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _settingsProvider = context.read<SettingsProvider>();
    _settingsProvider.addListener(_handleSettingsConfigChanged);
    _config = widget.overrideConfig ?? _settingsProvider.config;
    _touchMode = _config.mouseMode;
    _showGamepad = _config.showOnscreenControls;
    _showPerfStats = _config.enablePerfOverlay;
    _gamepadOpacity = _config.oscOpacity.clamp(0, 100) / 100.0;
    _rebuildDesktopCombo();
    // mouse emulation starts OFF — user activates via combo at runtime

    GamepadChannel.init();
    GamepadChannel.onComboDetected = _onNativeComboDetected;
    GamepadChannel.onOverlayDpad = _onNativeOverlayDpad;
    GamepadChannel.onMouseModeToggle = _onNativeMouseModeToggle;
    GamepadChannel.onControllerConnected = _onControllerConnected;
    GamepadChannel.onControllerDisconnected = _onControllerDisconnected;
    GamepadChannel.onPanicComboDetected = _onPanicComboDetected;
    GamepadChannel.onQuickKeysComboDetected = _onQuickKeysComboDetected;

    if (_config.enableDirectSubmit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startStreaming();
      });
    } else {
      _startStreaming();
    }
    _listenToStats();
    // Stop UI ambience while actively streaming — resume when session ends
    UiSoundService.enterStreamSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settingsProvider.removeListener(_handleSettingsConfigChanged);
    GamepadChannel.onComboDetected = null;
    GamepadChannel.onOverlayDpad = null;
    GamepadChannel.onMouseModeToggle = null;
    GamepadChannel.onControllerConnected = null;
    GamepadChannel.onControllerDisconnected = null;
    GamepadChannel.onPanicComboDetected = null;
    GamepadChannel.onQuickKeysComboDetected = null;

    if (_gamepadMouseActive) {
      GamepadChannel.setMouseEmulation(false);
    }
    if (!_stopInFlight && !_streamStopped) {
      unawaited(_stopStreaming(clearActiveSession: _clearActiveSessionOnExit));
    }
    if (_clearActiveSessionOnExit) {
      _computerProvider.clearActiveSession();
    }
    _streamFocusNode.dispose();
    _overlayFocusNode.dispose();
    _overlayScrollController.dispose();
    _keyboardFocusNode.dispose();
    _keyboardController.dispose();
    _statsSubscription?.cancel();
    _statsSubscription = null;
    _desktopComboHoldTimer?.cancel();
    _desktopComboHoldTimer = null;
    _panZoomCtrl.dispose();
    ImageLoadThrottle.resumeAfterStream();
    // Restore ambience eligibility now that stream has ended
    UiSoundService.exitStreamSession();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      final pro = context.read<ProService>();
      if (_isConnected &&
          _config.pipEnabled &&
          (pro.isPro || ProService.kDevMode)) {
        StreamingPlatformChannel.enterPiP();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (!_keyboardVisible) {
        SystemChannels.textInput.invokeMethod('TextInput.hide');
        _keyboardFocusNode.unfocus();
      }
      _streamFocusNode.requestFocus();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

      if (_isConnected) {
        GamepadChannel.redetectControllers();
      }
    }
  }

  Future<void> _startStreaming() async {
    // wait for any in-flight stop to finish so native doesn't overlap
    if (_pendingStop != null) {
      debugPrint('_startStreaming: waiting for pending stopStream…');
      await _pendingStop!.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('_startStreaming: pendingStop timed out — forcing ahead');
        },
      );
      _pendingStop = null;
    }
    _streamStopped = false;
    _stopInFlight = false;
    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      if (_lastDisconnectTime != null) {
        final elapsed = DateTime.now()
            .difference(_lastDisconnectTime!)
            .inMilliseconds;
        if (elapsed < _reconnectCooldownMs) {
          final waitMs = _reconnectCooldownMs - elapsed;
          debugPrint(
            'Reconnect cooldown: waiting ${waitMs}ms before starting stream',
          );
          await Future.delayed(Duration(milliseconds: waitMs));
        }
      }

      await GamepadChannel.setStreamingActive(false);

      final cfg = _config;
      final address = widget.computer.activeAddress.isNotEmpty
          ? widget.computer.activeAddress
          : widget.computer.localAddress;

      final codecStr = switch (cfg.videoCodec) {
        VideoCodec.h265 => 'H265',
        VideoCodec.av1 => 'AV1',
        VideoCodec.auto => 'auto',
        _ => 'H264',
      };
      final audioStr = switch (cfg.audioConfig) {
        AudioConfig.surround51 => 'surround51',
        AudioConfig.surround71 => 'surround71',
        _ => 'stereo',
      };

      final effectiveBitrate = cfg.ultraLowLatency
          ? (cfg.bitrate * 0.75).round().clamp(1000, 150000)
          : _dynBitrate.effectiveBitrate(cfg.bitrate);

      debugPrint('>>> STREAM CONFIG DIAGNOSTIC <<<');
      debugPrint('Resolution: ${cfg.width}x${cfg.height} @ ${cfg.fps}fps');
      debugPrint(
        'Bitrate: $effectiveBitrate Kbps (original: ${cfg.bitrate}, ultraLowLatency: ${cfg.ultraLowLatency})',
      );
      debugPrint('Video Codec: $codecStr (enum: ${cfg.videoCodec})');
      debugPrint('HDR Enabled: ${cfg.enableHdr}, fullRange: ${cfg.fullRange}');
      debugPrint('Frame Pacing: ${cfg.framePacing}');
      debugPrint('Audio Config: $audioStr (enum: ${cfg.audioConfig})');
      debugPrint('Audio Quality: ${cfg.audioQuality.name}');
      debugPrint('Scale Mode: ${cfg.scaleMode}');
      debugPrint('Server: $address:${widget.computer.httpsPort}');
      debugPrint('>>> ');
      BetaTelemetryService.event('stream_start_requested', {
        'host': address,
        'port': widget.computer.httpsPort,
        'appId': widget.app.appId,
        'width': cfg.width,
        'height': cfg.height,
        'fps': cfg.fps,
        'bitrate': effectiveBitrate,
        'codec': codecStr,
        'hdr': cfg.enableHdr,
        'audio': audioStr,
        'directSubmit': cfg.enableDirectSubmit,
      });

      final success =
          await StreamingPlatformChannel.startStream(
            host: address,
            httpsPort: widget.computer.httpsPort,
            appId: widget.app.appId.toString(),
            width: cfg.width,
            height: cfg.height,
            fps: cfg.fps,
            bitrate: effectiveBitrate,
            videoCodec: codecStr,
            enableHdr: cfg.enableHdr,
            fullRange: cfg.fullRange,
            framePacing: cfg.framePacing,
            audioConfig: audioStr,
            audioQuality: cfg.audioQuality,
            enableAudioFx: cfg.enableAudioFx,
            serverCert: widget.computer.serverCert,
            riKey: widget.riKey,
            riKeyId: widget.riKeyId,
            rtspSessionUrl: widget.rtspSessionUrl,
            appVersion: widget.computer.serverVersion,
            gfeVersion: widget.computer.gfeVersion,
            serverCodecModeSupport: widget.computer.serverCodecModeSupport,
            frameQueueDepth: cfg.frameQueueDepth,
            choreographerVsync: cfg.choreographerVsync,
            enableVrr: cfg.enableVrr,
            directSubmit: cfg.enableDirectSubmit,
            lowLatencyFrameBalance: cfg.lowLatencyFrameBalance,
          ).timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              debugPrint(
                'startStream timed out (30s) — cleaning up native side',
              );
              // fire-and-forget native cleanup so nativeStartConnection thread
              // doesn't keep running while we show the error screen
              StreamingPlatformChannel.stopStream();
              return false;
            },
          );

      if (success) {
        final directSubmitActive =
            await StreamingPlatformChannel.isDirectSubmitActive();
        // honor Dart-side config: only skip textureId when user opted into
        // direct-submit AND native confirms it is actually active.
        final textureId = (cfg.enableDirectSubmit && directSubmitActive)
            ? null
            : await StreamingPlatformChannel.getTextureId();

        final physicalCount = await GamepadChannel.setStreamingActive(true);
        if (physicalCount > 0) {
          _config = _config.copyWith(
            controllerCount: physicalCount.clamp(1, 4),
          );
        }

        try {
          await _applyGamepadConfig();
        } catch (_) {}

        if (mounted) {
          context.read<ComputerProvider>().setActiveSession(
            widget.computer,
            widget.app,
          );
        }
        setState(() {
          _usingDirectSubmit = cfg.enableDirectSubmit && directSubmitActive;
          _textureId = textureId;
          _isConnecting = false;
          _isConnected = true;
          _reconnectMessage = null;
        });
        BetaTelemetryService.event('stream_started', {
          'textureId': textureId ?? -1,
          'directSubmit': _usingDirectSubmit,
          'controllerCount': physicalCount,
        });

        _isReconnecting = false;

        // always redetect so the controller is picked up on initial entry AND reconnects
        GamepadChannel.redetectControllers();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _streamFocusNode.requestFocus();
        });
      } else {
        if (_isReconnecting &&
            _presetReconnectRetries < _maxPresetReconnectRetries) {
          _presetReconnectRetries++;
          await Future.delayed(const Duration(milliseconds: 3000));
          if (mounted) _startStreaming();
          return;
        }
        _isReconnecting = false;
        final errorCode = StreamingPlatformChannel.lastStartStreamErrorCode;
        final detail = StreamingPlatformChannel.lastStartStreamError;
        BetaTelemetryService.event('stream_start_failed', {
          'code': errorCode ?? -1,
          'detail': detail ?? '',
        });

        // GS_WRONG_STATE (104) — server has a stale session from a previous
        // client. Auto-cancel it and retry once before showing the error.
        if (errorCode == 104 && !_isReconnecting) {
          if (!mounted) return;
          final isEs = Localizations.localeOf(context).languageCode == 'es';
          debugPrint(
            'GS_WRONG_STATE detected — cancelling stale server session and retrying…',
          );
          setState(() {
            _reconnectMessage =
                isEs
                ? 'Sesión anterior detectada — cancelando…'
                : 'Stale session detected — cancelling…';
          });
          try {
            await context.read<AppListProvider>().quitApp();
          } catch (_) {}
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            _lastDisconnectTime = null; // skip cooldown
            _startStreaming();
          }
          return;
        }

        setState(() {
          _isConnecting = false;
          _showOverlay = false;
          _error = detail == null || detail.isEmpty
              ? AppLocalizations.of(context).streamError
              : '${AppLocalizations.of(context).streamError}: $detail';
        });
        GamepadChannel.setOverlayVisible(false);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _streamFocusNode.requestFocus();
        });
      }
    } catch (e) {
      BetaTelemetryService.error(
        'stream_start_exception',
        e,
        StackTrace.current,
      );
      if (_isReconnecting &&
          _presetReconnectRetries < _maxPresetReconnectRetries) {
        _presetReconnectRetries++;
        await Future.delayed(const Duration(milliseconds: 3000));
        if (mounted) _startStreaming();
        return;
      }
      _isReconnecting = false;
      setState(() {
        _isConnecting = false;
        _showOverlay = false;
        _error = '${AppLocalizations.of(context).connectionError}: $e';
      });
      GamepadChannel.setOverlayVisible(false);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _streamFocusNode.requestFocus();
      });
    }
  }

  void _handleSettingsConfigChanged() {
    if (!mounted || widget.overrideConfig != null) {
      return;
    }

    final nextConfig = _settingsProvider.config;
    setState(() {
      _config = nextConfig;
      _touchMode = nextConfig.mouseMode;
      _showGamepad = nextConfig.showOnscreenControls;
      _showPerfStats = nextConfig.enablePerfOverlay;
      _gamepadOpacity = nextConfig.oscOpacity.clamp(0, 100) / 100.0;
      // if the master switch was turned off mid-session, deactivate
      if (!nextConfig.mouseEmulation) _gamepadMouseActive = false;
    });
    _rebuildDesktopCombo();

    if (_isConnected) {
      unawaited(_applyGamepadConfig());
    }
  }

  Future<void> _stopStreaming({bool clearActiveSession = false}) async {
    if (_stopInFlight || _streamStopped) return;

    _stopInFlight = true;
    _streamStopped = true;
    _clearActiveSessionOnExit = clearActiveSession;
    if (!clearActiveSession) {
      _ignoreTerminationUntil = DateTime.now().add(const Duration(seconds: 3));
    }
    _lastDisconnectTime = DateTime.now();
    final cmp = Completer<void>();
    _pendingStop = cmp;
    try {
      BetaTelemetryService.event('stream_stop_requested', {
        'clearActiveSession': clearActiveSession,
      });
      await GamepadChannel.setStreamingActive(false);
      await StreamingPlatformChannel.stopStream();

      if (!clearActiveSession && mounted) {
        widget.computer.runningGameId = widget.app.appId;
        context.read<AppListProvider>().currentComputer?.runningGameId =
            widget.app.appId;
      }

      if (mounted) {
        setState(() {
          _usingDirectSubmit = false;
          _textureId = null;
        });
      }

      if (mounted) {
        if (clearActiveSession) {
          context.read<ComputerProvider>().clearActiveSession();
        }
      }
    } finally {
      BetaTelemetryService.event('stream_stopped', {
        'clearActiveSession': clearActiveSession,
      });
      _stopInFlight = false;
      if (!cmp.isCompleted) cmp.complete();
    }
  }

  Future<void> _applyGamepadConfig() async {
    final cfg = _config;
    await GamepadChannel.setDeadzone(cfg.deadzone.clamp(0, 100));
    await GamepadChannel.setTouchpadAsMouse(cfg.gamepadTouchpadAsMouse);
    await GamepadChannel.setMotionSensors(
      cfg.gamepadMotionSensors,
      cfg.gamepadMotionFallback,
    );
    await GamepadChannel.setControllerPreferences(
      backButtonAsMeta: cfg.backButtonAsMeta,
      backButtonAsGuide: cfg.backButtonAsGuide,
      controllerDriver: cfg.controllerDriver.index,
    );
    await GamepadChannel.setInputPreferences(
      forceQwertyLayout: cfg.forceQwertyLayout,
      usbDriverEnabled: cfg.usbDriverEnabled,
      usbBindAll: cfg.usbBindAll,
      joyConEnabled: cfg.joyCon,
    );
    await GamepadChannel.setRumbleConfig(
      cfg.enableRumble,
      cfg.vibrateFallback,
      cfg.deviceRumble,
      cfg.vibrateFallbackStrength,
    );

    final remapTable = _resolveButtonRemap(
      cfg.buttonRemapProfile,
      cfg.customRemapTable,
    );
    await GamepadChannel.setButtonRemap(remapTable);
    await GamepadChannel.setMouseEmulationSpeed(cfg.gamepadMouseSpeed);
    await GamepadChannel.setOverlayTriggerConfig(
      cfg.overlayTriggerCombo,
      cfg.overlayTriggerHoldMs,
    );
    await GamepadChannel.setMouseModeConfig(
      cfg.mouseModeCombo,
      cfg.mouseModeHoldMs,
    );
    await GamepadChannel.setPanicComboConfig(cfg.panicCombo, cfg.panicHoldMs);
    await GamepadChannel.setQuickKeysComboConfig(
      cfg.quickKeysCombo,
      cfg.quickKeysHoldMs,
    );

    if (!cfg.mouseEmulation || !_gamepadMouseActive) {
      await GamepadChannel.setMouseEmulation(false);
    } else {
      await GamepadChannel.setMouseEmulation(true);
    }
  }

  String _dropRate = '--';
  String _resolution = '--';
  String _codec = '--';
  String _queueDepth = '--';
  String _pendingAudioMs = '--';
  String _rttVariance = '--';
  String _renderPath = '--';

  static const int _btnA = 0x1000;
  static const int _btnB = 0x2000;
  static const int _btnX = 0x4000;
  static const int _btnY = 0x8000;
  static const int _btnLB = 0x0100;
  static const int _btnRB = 0x0200;
  static const int _btnLS = 0x0040;
  static const int _btnRS = 0x0080;

  static Map<int, int>? _resolveButtonRemap(
    ButtonRemapProfile profile, [
    Map<int, int>? customTable,
  ]) {
    return switch (profile) {
      ButtonRemapProfile.none => null,
      ButtonRemapProfile.nintendo => {
        _btnA: _btnB,
        _btnB: _btnA,
        _btnX: _btnY,
        _btnY: _btnX,
      },
      ButtonRemapProfile.southpaw => {
        _btnLB: _btnRB,
        _btnRB: _btnLB,
        _btnLS: _btnRS,
        _btnRS: _btnLS,
      },
      ButtonRemapProfile.custom =>
        customTable?.isNotEmpty == true ? customTable : null,
    };
  }

  void _listenToStats() {
    _statsSubscription = StreamingPlatformChannel.statsStream.listen((event) {
      if (!mounted) return;
      final type = event['type'] as String?;
      switch (type) {
        case 'connectionStarted':
          BetaTelemetryService.event('native_connection_started');
          _reconnectAttempts = 0;
          _sessionMetrics.clear();
          _sessionMetricsStartedAt = DateTime.now();
          _sessionMetricsDialogShown = false;

        case 'connectionTerminated':
          final errorCode = event['errorCode'] as int? ?? 0;
          BetaTelemetryService.event('native_connection_terminated', {
            'errorCode': errorCode,
          });
          _onConnectionTerminated(errorCode);
        case 'stageStarting':
          final stageName = event['stageName'] as String? ?? '';
          BetaTelemetryService.event('native_stage_starting', {
            'stage': event['stage'] as int? ?? 0,
            'name': stageName,
          });
          setState(() {
            _currentStageName = stageName;
            _currentStageIndex = (event['stage'] as int? ?? 0);
          });
        case 'stageComplete' || 'stageFailed' || 'statusUpdate':
          break;
        case 'reconnectNeeded':
          _reconnectAttempts = 0;
          if (mounted) {
            setState(() {
              _isConnected = false;
              _isConnecting = true;
              _reconnectMessage = AppLocalizations.of(
                context,
              ).reconnectingLabel;
            });
            // Must stop the existing native session before starting a new one;
            // skipping this guarantees GS_WRONG_STATE (104) from the server.
            _stopInFlight = false;
            _streamStopped = false;
            unawaited(_stopStreaming());
            _startStreaming();
          }
        default:
          // Wrap stat parsing in try-catch to handle unexpected types or
          // missing keys from different server versions (Vibepollo, Sunshine,
          // Apollo).  A malformed stats event must never crash the stream.
          try {
            setState(() {
              _fps = '${event['fps'] ?? '--'} FPS';
              final dt = (event['decodeTime'] is num)
                  ? event['decodeTime'] as num
                  : null;
              _latency = dt != null ? '${dt.toStringAsFixed(2)} ms' : '--';
              _bitrate = '${event['bitrate'] ?? '--'} Mbps';
              final dr = event['dropRate'];
              _dropRate = dr != null ? '$dr%' : '--';
              final res = event['resolution']?.toString();
              _resolution = (res != null && res != '0x0' && res.isNotEmpty)
                  ? res
                  : '--';
              final c = event['codec']?.toString();
              _codec = (c != null && c != 'unknown' && c.isNotEmpty) ? c : '--';
              final qd = (event['queueDepth'] is num)
                  ? (event['queueDepth'] as num).toInt()
                  : null;
              _queueDepth = qd != null ? '$qd' : '--';
              final pendingAudio = (event['pendingAudioMs'] is num)
                  ? (event['pendingAudioMs'] as num).toInt()
                  : null;
              _pendingAudioMs = pendingAudio != null
                  ? '$pendingAudio ms'
                  : '--';
              final rttVar = (event['rttVarianceMs'] is num)
                  ? (event['rttVarianceMs'] as num).toInt()
                  : null;
              _rttVariance = (rttVar != null && rttVar >= 0)
                  ? '$rttVar ms'
                  : '--';
              final rp = event['renderPath']?.toString();
              _renderPath = (rp != null && rp.isNotEmpty) ? rp : '--';
            });
          } catch (_) {
            // Silently ignore malformed stats — the HUD keeps its last values.
          }
          _recordSessionMetrics(event);
          _recordStatsTelemetry(event);
          _dynBitrate.evaluate(
            enabled: _config.dynamicBitrateEnabled,
            connected: _isConnected,
            baseBitrate: _config.bitrate,
            fps: _config.fps,
            sensitivity: _config.dynamicBitrateSensitivity,
            event: event,
          );
      }
    });
  }

  void _recordStatsTelemetry(Map<String, dynamic> event) {
    _statsTelemetryTicks++;
    if (_statsTelemetryTicks % 60 != 0) return;
    BetaTelemetryService.event('stream_stats_sample', {
      'fps': event['fps'] ?? 0,
      'decodeTime': event['decodeTime'] ?? 0,
      'dropRate': event['dropRate'] ?? 0,
      'queueDepth': event['queueDepth'] ?? 0,
      'pendingAudioMs': event['pendingAudioMs'] ?? 0,
      'codec': event['codec'] ?? '',
      'renderPath': event['renderPath'] ?? '',
      'isSoftwareDecoder': event['isSoftwareDecoder'] ?? false,
    });
  }

  void _recordSessionMetrics(Map<String, dynamic> event) {
    if (!_config.enableSessionMetrics) return;
    final startedAt = _sessionMetricsStartedAt ??= DateTime.now();
    final second = DateTime.now().difference(startedAt).inSeconds;
    _sessionMetrics.add(
      SessionMetricPoint(
        second: second,
        fps: ((event['fps'] as num?) ?? 0).toInt().clamp(0, 240),
        decodeMs: ((event['decodeTime'] as num?) ?? 0).toInt().clamp(0, 9999),
        bitrateMbps: ((event['bitrate'] as num?) ?? 0).toInt().clamp(0, 1000),
        dropRate: ((event['dropRate'] as num?) ?? 0).toInt().clamp(0, 100),
      ),
    );
    if (_sessionMetrics.length > 7200) {
      _sessionMetrics.removeAt(0);
    }
  }

  /// Callback from DynamicBitrateController when a bitrate reconnect is needed.
  Future<void> _onDynBitrateReconnect(int? newBitrateKbps) async {
    if (_dynBitrate.reconnecting) return;
    _dynBitrate.reconnecting = true;
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isConnecting = true;
        _textureId = null;
        _reconnectMessage = AppLocalizations.of(context).applyingQuality;
      });
    }
    await _stopStreaming();
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _lastDisconnectTime = null;
    _isReconnecting = true;
    _presetReconnectRetries = 0;
    _dynBitrate.reconnecting = false;
    _startStreaming();
  }

  Future<void> _onConnectionTerminated(int errorCode) async {
    if (!mounted) return;

    if (_isReconnecting) return;

    if (_userInitiatedQuit) return;

    if (_ignoreTerminationUntil != null &&
        DateTime.now().isBefore(_ignoreTerminationUntil!)) {
      _ignoreTerminationUntil = null;
      return;
    }
    _ignoreTerminationUntil = null;

    // stream terminated while still connecting — never pop silently;
    // treat it as a startup failure so the user gets an error screen
    if (_isConnecting) {
      debugPrint(
        'connectionTerminated($errorCode) during _isConnecting — treating as startup failure',
      );
      setState(() {
        _isConnecting = false;
        _showOverlay = false;
        _error = errorCode == 0
            ? 'Server closed the connection before the stream was established.'
            : 'Connection lost during startup (code $errorCode).';
      });
      GamepadChannel.setOverlayVisible(false);
      return;
    }

    if (errorCode == 0) {
      await _stopStreaming();
      await _showSessionMetricsIfNeeded();
      if (mounted) Navigator.of(context).pop();
      return;
    }

    if (_reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      final delaySec =
          _reconnectDelaysSeconds[(_reconnectAttempts - 1).clamp(
            0,
            _reconnectDelaysSeconds.length - 1,
          )];
      setState(() {
        _isConnected = false;
        _isConnecting = true;
        _reconnectMessage =
            'Connection lost — reconnecting $_reconnectAttempts/$_maxReconnectAttempts in ${delaySec}s…';
      });
      // Tell the server to tear down the old session before we reconnect.
      // Without this, nativeStartConnection returns 104 (GS_WRONG_STATE)
      // because the server still holds the previous session as active.
      _stopInFlight = false;
      _streamStopped = false;
      unawaited(_stopStreaming());
      Future.delayed(Duration(seconds: delaySec), () {
        if (mounted) _startStreaming();
      });
    } else {
      setState(() {
        _isConnected = false;
        _isConnecting = false;
        _showOverlay = false;
        _error = 'Connection failed after $_maxReconnectAttempts attempts.';
        _reconnectMessage = null;
      });
      GamepadChannel.setOverlayVisible(false);
    }
  }

  void _onNativeComboDetected() {
    if (!mounted) return;
    _setOverlayVisible(true);
  }

  void _onNativeMouseModeToggle() {
    if (!mounted) return;
    _cycleTouchMode();
  }

  void _onControllerConnected(int controllerNumber) {}

  void _onControllerDisconnected(int controllerNumber) {}

  /// Quick Keys combo detected — toggle the quick keys overlay.
  void _onQuickKeysComboDetected() {
    if (!mounted) return;
    if (_showOverlay) return; // don't open quick keys while overlay is visible
    _setQuickKeysVisible(!_showQuickKeys);
  }

  /// Panic combo detected — emergency session kill without confirmation.
  void _onPanicComboDetected() {
    if (!mounted) return;
    debugPrint(
      '[JUJO][panic] Panic combo triggered — executing emergency quit',
    );
    _executeQuit();
  }

  void _onNativeOverlayDpad(String direction) {
    if (!mounted || !_showOverlay) return;

    if (_showSpecialKeys) {
      switch (direction) {
        case 'left':
          setState(
            () => _specialKeyIdx =
                (_specialKeyIdx - 1 + specialKeyCount) % specialKeyCount,
          );
        case 'right':
          setState(
            () => _specialKeyIdx = (_specialKeyIdx + 1) % specialKeyCount,
          );
        case 'down':
          final next = specialKeySections.firstWhere(
            (s) => s > _specialKeyIdx,
            orElse: () => specialKeySections.first,
          );
          setState(() => _specialKeyIdx = next);
        case 'up':
          final prev = specialKeySections.lastWhere(
            (s) => s < _specialKeyIdx,
            orElse: () => specialKeySections.last,
          );
          setState(() => _specialKeyIdx = prev);
      }
      _scrollToFocusedSpecialKey();
      return;
    }

    if (_showQuitConfirm) {
      if (direction == 'left' || direction == 'right') {
        setState(() => _quitConfirmSelection = 1 - _quitConfirmSelection);
      }
      return;
    }
    setState(() {
      switch (direction) {
        case 'down':
          _overlayRow = (_overlayRow + 1).clamp(0, 6);
          if (_overlayRow == 0) {
            _overlayCol = _overlayCol.clamp(0, 3);
          } else if (_overlayRow == 1) {
            _overlayCol = _overlayCol.clamp(0, _toggleCount - 1);
          } else {
            _overlayCol = 0;
          }
        case 'up':
          _overlayRow = (_overlayRow - 1).clamp(0, 6);
          if (_overlayRow == 0) {
            _overlayCol = _overlayCol.clamp(0, 3);
          } else if (_overlayRow == 1) {
            _overlayCol = _overlayCol.clamp(0, _toggleCount - 1);
          } else {
            _overlayCol = 0;
          }
        case 'left':
          if (_overlayRow == 0) {
            _overlayCol = (_overlayCol - 1).clamp(0, 3);
          } else if (_overlayRow == 1) {
            _overlayCol = (_overlayCol - 1).clamp(0, _toggleCount - 1);
          }
        case 'right':
          if (_overlayRow == 0) {
            _overlayCol = (_overlayCol + 1).clamp(0, 3);
          } else if (_overlayRow == 1) {
            _overlayCol = (_overlayCol + 1).clamp(0, _toggleCount - 1);
          }
      }
    });
    _scrollOverlayToFocusedRow();
  }

  void _setOverlayVisible(bool visible) {
    if (_overlayTransitioning) return;
    if (visible == _showOverlay) return;
    _overlayTransitioning = true;
    Timer(const Duration(milliseconds: 500), () {
      _overlayTransitioning = false;
    });

    setState(() {
      _showOverlay = visible;
      _showSpecialKeys = false;
      _showQuitConfirm =
          false; // always reset so quit-confirm doesn't persist across open/close cycles
      if (visible) {
        _overlayRow = 0;
        _overlayCol = 0;
      }
    });

    GamepadChannel.setOverlayVisible(visible);
    if (visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _overlayFocusNode.requestFocus();
        if (_overlayScrollController.hasClients) {
          _overlayScrollController.jumpTo(0);
        }
        _syncOverlayScrollToSelection();
      });
    } else {
      _streamFocusNode.requestFocus();
    }
  }

  void _syncOverlayScrollToSelection() {
    if (_showSpecialKeys) {
      _scrollToFocusedSpecialKey();
      return;
    }
    if (_showOverlay && !_showQuitConfirm) {
      _scrollOverlayToFocusedRow();
    }
  }

  int get _toggleCount => _config.multiControllerEnabled ? 7 : 6;

  void _activateOverlayCurrentItem() {
    switch (_overlayRow) {
      case 0:
        if (!_presetsEnabled) return;
        const presetIds = ['app_controlled', 'fast', 'balanced', 'quality'];
        _applyQualityPreset(presetIds[_overlayCol.clamp(0, 3)]);
      case 1:
        _activateToggle(_overlayCol);
      case 2:
        setState(() => _showSpecialKeys = true);
      case 3:
        _pasteClipboardToPC();
      case 4:
        _closeSessionAndExit();
      case 5:
        setState(() {
          _showQuitConfirm = true;
          _quitConfirmSelection = 0;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _overlayFocusNode.requestFocus();
        });
      case 6:
        _setOverlayVisible(false);
    }
  }

  void _activateToggle(int col) {
    int idx = col;
    if (idx == 0) {
      _cycleTouchMode();
    } else if (idx == 1) {
      setState(() => _showPerfStats = !_showPerfStats);
    } else if (idx == 2) {
      setState(() => _showGamepad = !_showGamepad);
    } else if (idx == 3 && _config.multiControllerEnabled) {
      setState(() {
        final max = _config.controllerCount.clamp(1, 4);
        _activeControllerSlot = (_activeControllerSlot + 1) % max;
      });
    } else {
      final kbIdx = _config.multiControllerEnabled ? 4 : 3;
      final pzIdx = _config.multiControllerEnabled ? 5 : 4;
      if (idx == kbIdx) {
        _toggleKeyboard();
      } else if (idx == pzIdx) {
        _togglePanZoom();
      }
    }
  }

  void _togglePanZoom() {
    setState(() {
      _panZoomActive = !_panZoomActive;
      if (!_panZoomActive) {
        _panZoomCtrl.value = Matrix4.identity();
      }
    });
  }

  // and buildSpecialKeysPanel now live in special_keys.dart.
  late final List<SpecialKeyEntry> _specialKeys = buildSpecialKeysList();

  void _toggleFavoriteSpecialKey(int index) {
    if (index < 0 || index >= _specialKeys.length) return;
    final current = List<int>.from(_config.favoriteSpecialKeys);
    if (current.contains(index)) {
      current.remove(index);
    } else {
      if (current.length >= maxFavoriteSpecialKeys) {
        HapticFeedback.heavyImpact();
        return;
      }
      current.add(index);
    }
    HapticFeedback.lightImpact();
    _config = _config.copyWith(favoriteSpecialKeys: current);
    _settingsProvider.updateConfig(_config);
    setState(() {});
  }

  void _activateSpecialKey(int index) {
    if (index < 0 || index >= _specialKeys.length) return;
    HapticFeedback.lightImpact();
    _specialKeys[index].$3();
  }

  // ── Quick Keys overlay helpers ──────────────────────────────────────

  void _setQuickKeysVisible(bool visible) {
    if (visible == _showQuickKeys) return;
    setState(() => _showQuickKeys = visible);
    if (!visible) {
      _streamFocusNode.requestFocus();
    }
  }

  /// Resolves a localization key (e.g. 'skStartMenu') to a human label.
  String _resolveSpecialKeyLabel(String key) {
    final l = AppLocalizations.of(context);
    return resolveSpecialKeyLocalization(l, key);
  }

  /// Called when the user activates a key from the Quick Keys overlay.
  /// Fires the key action, then auto-dismisses after 300ms.
  void _onQuickKeyActivated(int keyIndex) {
    _activateSpecialKey(keyIndex);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _setQuickKeysVisible(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _setOverlayVisible(!_showOverlay);
      },
      child: Focus(
        focusNode: _streamFocusNode,
        autofocus: true,
        onKeyEvent: _onStreamKeyEvent,
        child: Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              _panZoomActive
                  ? InteractiveViewer(
                      transformationController: _panZoomCtrl,
                      minScale: 1.0,
                      maxScale: 5.0,
                      panEnabled: true,
                      scaleEnabled: true,
                      child: _buildVideoLayer(),
                    )
                  : _buildVideoLayer(),
              _buildInputLayer(),
              if (_config.mouseLocalCursor &&
                  _cursorVisible &&
                  _touchMode == MouseMode.directTouch &&
                  !_showOverlay)
                _buildLocalCursor(),
              if (_isConnecting) _buildConnectingOverlay(),
              if (_error != null) _buildErrorOverlay(),
              if (_showOverlay && _error == null) _buildMenuOverlay(),
              if (_showGamepad && _isConnected)
                VirtualGamepadOverlay(
                  opacity: _gamepadOpacity,
                  controllerNumber: _activeControllerSlot,
                  activeGamepadMask: _activeGamepadMask,
                ),
              if (_showPerfStats && _isConnected) _buildPerfOverlay(),
              if (_showQuickKeys && _isConnected && !_showOverlay)
                QuickKeysOverlay(
                  key: _quickKeysKey,
                  favoriteIndices: _config.favoriteSpecialKeys,
                  specialKeys: _specialKeys,
                  descriptionResolver: _resolveSpecialKeyLabel,
                  onActivate: _onQuickKeyActivated,
                  onClose: () => _setQuickKeysVisible(false),
                ),

              if (_keyboardVisible) _buildHiddenKeyboardField(),
            ],
          ),
        ),
      ),
    );
  }

  // Desktop overlay combo — derived from config. Built in initState/_handleSettingsConfigChanged.
  // Initialized to ['Shift','-'] by default via StreamConfiguration.desktopOverlayKeys.
  Set<LogicalKeyboardKey> _desktopOverlayCombo = {
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.minus,
  };

  static final Set<LogicalKeyboardKey> _desktopOverlaySafetyCombo = {
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.f1,
  };

  // Desktop overlay combo hold timer — mirrors gamepad hold behavior.
  Timer? _desktopComboHoldTimer;
  bool _desktopComboHeld = false;

  /// Converts a human-readable key label ('Shift', '-', 'Ctrl', etc.)
  /// into a LogicalKeyboardKey. Falls back to null if unrecognised.
  static LogicalKeyboardKey? _labelToKey(String label) {
    switch (label.toLowerCase()) {
      case 'shift':
        return LogicalKeyboardKey.shift;
      case 'ctrl':
        return LogicalKeyboardKey.control;
      case 'alt':
        return LogicalKeyboardKey.alt;
      case 'meta':
        return LogicalKeyboardKey.meta;
      case '-':
        return LogicalKeyboardKey.minus;
      case 'f1':
        return LogicalKeyboardKey.f1;
      case 'f2':
        return LogicalKeyboardKey.f2;
      case 'f3':
        return LogicalKeyboardKey.f3;
      case 'f4':
        return LogicalKeyboardKey.f4;
      case 'f5':
        return LogicalKeyboardKey.f5;
      case 'f6':
        return LogicalKeyboardKey.f6;
      case 'f7':
        return LogicalKeyboardKey.f7;
      case 'f8':
        return LogicalKeyboardKey.f8;
      case 'f9':
        return LogicalKeyboardKey.f9;
      case 'f10':
        return LogicalKeyboardKey.f10;
      case 'f11':
        return LogicalKeyboardKey.f11;
      case 'f12':
        return LogicalKeyboardKey.f12;
      case 'tab':
        return LogicalKeyboardKey.tab;
      case 'space':
        return LogicalKeyboardKey.space;
      case '`':
        return LogicalKeyboardKey.backquote;
      default:
        return null;
    }
  }

  static LogicalKeyboardKey _normalizeDesktopComboKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      return LogicalKeyboardKey.shift;
    }
    if (key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight) {
      return LogicalKeyboardKey.control;
    }
    if (key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight) {
      return LogicalKeyboardKey.alt;
    }
    if (key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight) {
      return LogicalKeyboardKey.meta;
    }
    if (key.keyLabel == '_') return LogicalKeyboardKey.minus;
    return key;
  }

  bool _matchesDesktopOverlayCombo() {
    bool containsAll(Set<LogicalKeyboardKey> combo) =>
        combo.isNotEmpty && combo.every(_heldButtons.contains);
    return containsAll(_desktopOverlayCombo) ||
        containsAll(_desktopOverlaySafetyCombo);
  }

  void _releasePressedComboKeysToHost() {
    if (!_isConnected) return;
    final activeCombos = <Set<LogicalKeyboardKey>>[
      _desktopOverlayCombo,
      _desktopOverlaySafetyCombo,
    ];
    for (final rawKey in HardwareKeyboard.instance.logicalKeysPressed) {
      final normalized = _normalizeDesktopComboKey(rawKey);
      final belongsToCombo = activeCombos.any(
        (combo) => combo.contains(normalized),
      );
      if (!belongsToCombo) continue;
      final vk = logicalKeyToVk(rawKey);
      if (vk != null) {
        StreamingPlatformChannel.sendKeyboardInput(vk, false);
      }
    }
  }

  void _rebuildDesktopCombo() {
    final keys = _config.desktopOverlayKeys
        .map(_labelToKey)
        .map((key) => key == null ? null : _normalizeDesktopComboKey(key))
        .whereType<LogicalKeyboardKey>()
        .toSet();
    if (keys.isNotEmpty) _desktopOverlayCombo = keys;
  }

  static final _gamepadComboKeys = {
    LogicalKeyboardKey.gameButtonSelect,
    LogicalKeyboardKey.gameButtonStart,
    LogicalKeyboardKey.gameButtonLeft1,
    LogicalKeyboardKey.gameButtonRight1,
  };

  KeyEventResult _onStreamKeyEvent(FocusNode node, KeyEvent event) {
    if (_error != null) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.handled;
      }
      final k = event.logicalKey;

      if (k == LogicalKeyboardKey.gameButtonB ||
          k == LogicalKeyboardKey.escape ||
          k == LogicalKeyboardKey.goBack) {
        Navigator.pop(context);
        return KeyEventResult.handled;
      }

      if (k == LogicalKeyboardKey.gameButtonA ||
          k == LogicalKeyboardKey.enter) {
        if (_errorSelectedButton == 0) {
          _startStreaming();
        } else {
          Navigator.pop(context);
        }
        return KeyEventResult.handled;
      }

      if (k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight) {
        setState(
          () => _errorSelectedButton = _errorSelectedButton == 0 ? 1 : 0,
        );
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    final key = event.logicalKey;
    final comboKey = _normalizeDesktopComboKey(key);

    if (event is KeyDownEvent) {
      _heldButtons.add(comboKey);

      if (key == LogicalKeyboardKey.gameButtonStart) {
        _startPressedAt = DateTime.now();
      }

      if (_gamepadComboKeys.every((k) => _heldButtons.contains(k))) {
        _heldButtons.clear();
        _startPressedAt = null;
        _setOverlayVisible(true);
        return KeyEventResult.handled;
      }

      // Desktop overlay combo (default Shift+-, configurable in Settings).
      // ESC is intentionally NOT used here — most games use ESC for their own menus.
      // Supports optional hold duration (desktopOverlayHoldMs) — mirrors gamepad hold.
      if (_matchesDesktopOverlayCombo()) {
        if (!_desktopComboHeld) {
          _desktopComboHeld = true;
          final holdMs = _config.desktopOverlayHoldMs;
          if (holdMs <= 0) {
            // No hold required — trigger immediately
            _desktopComboHoldTimer?.cancel();
            _desktopComboHoldTimer = null;
            _releasePressedComboKeysToHost();
            _heldButtons.clear();
            _desktopComboHeld = false;
            _setOverlayVisible(!_showOverlay);
          } else {
            // Start hold timer — fires after holdMs if keys remain held
            _desktopComboHoldTimer?.cancel();
            _desktopComboHoldTimer = Timer(Duration(milliseconds: holdMs), () {
              if (!mounted) return;
              _releasePressedComboKeysToHost();
              _heldButtons.clear();
              _desktopComboHeld = false;
              _desktopComboHoldTimer = null;
              _setOverlayVisible(!_showOverlay);
            });
          }
        }
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.gameButtonB && _showOverlay) {
        if (_showSpecialKeys) {
          setState(() {
            _showSpecialKeys = false;
            _overlayRow = 0;
            _overlayCol = 0;
          });
          _syncOverlayScrollToSelection();
        } else {
          _setOverlayVisible(false);
        }
        return KeyEventResult.handled;
      }

      if (!_showOverlay && _isConnected) {
        final vk = logicalKeyToVk(key);
        if (vk != null) {
          StreamingPlatformChannel.sendKeyboardInput(vk, true);
        }
        // Consume everything while stream has focus to prevent native OS "Bonk" alert sounds
        return KeyEventResult.handled;
      }

      if (_showOverlay && !_showSpecialKeys) {
        if (key == LogicalKeyboardKey.arrowDown) {
          setState(() {
            _overlayRow = (_overlayRow + 1).clamp(0, 6);

            if (_overlayRow == 0) {
              _overlayCol = _overlayCol.clamp(0, 3);
            } else if (_overlayRow == 1) {
              _overlayCol = _overlayCol.clamp(0, _toggleCount - 1);
            } else {
              _overlayCol = 0;
            }
          });
          _scrollOverlayToFocusedRow();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          setState(() {
            _overlayRow = (_overlayRow - 1).clamp(0, 6);
            if (_overlayRow == 0) {
              _overlayCol = _overlayCol.clamp(0, 3);
            } else if (_overlayRow == 1) {
              _overlayCol = _overlayCol.clamp(0, _toggleCount - 1);
            } else {
              _overlayCol = 0;
            }
          });
          _scrollOverlayToFocusedRow();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          if (_overlayRow == 0) {
            setState(() => _overlayCol = (_overlayCol - 1).clamp(0, 3));
          } else if (_overlayRow == 1) {
            setState(
              () => _overlayCol = (_overlayCol - 1).clamp(0, _toggleCount - 1),
            );
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          if (_overlayRow == 0) {
            setState(() => _overlayCol = (_overlayCol + 1).clamp(0, 3));
          } else if (_overlayRow == 1) {
            setState(
              () => _overlayCol = (_overlayCol + 1).clamp(0, _toggleCount - 1),
            );
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.select) {
          _activateOverlayCurrentItem();
          return KeyEventResult.handled;
        }
      }

      // Consume key down to prevent OS Bonk
      return KeyEventResult.handled;
    }

    if (event is KeyUpEvent) {
      _heldButtons.remove(comboKey);

      // Cancel desktop combo hold timer if a combo key was released early
      if (_desktopComboHeld &&
          (_desktopOverlayCombo.contains(comboKey) ||
              _desktopOverlaySafetyCombo.contains(comboKey))) {
        _desktopComboHoldTimer?.cancel();
        _desktopComboHoldTimer = null;
        _desktopComboHeld = false;
      }

      if (key == LogicalKeyboardKey.gameButtonStart &&
          _startPressedAt != null) {
        final held = DateTime.now().difference(_startPressedAt!);
        _startPressedAt = null;
        if (held.inMilliseconds >= 1500) {
          _cycleTouchMode();
          return KeyEventResult.handled;
        }
      }

      if (!_showOverlay && _isConnected) {
        final vk = logicalKeyToVk(key);
        if (vk != null) {
          StreamingPlatformChannel.sendKeyboardInput(vk, false);
        }
        // Consume key up to prevent OS Bonk
        return KeyEventResult.handled;
      }

      // Consume key up to prevent OS Bonk
      return KeyEventResult.handled;
    }

    // Always consume key events targeting the stream view to prevent system alert sounds
    return KeyEventResult.handled;
  }

  void _cycleTouchMode() {
    if (!_config.mouseEmulation) {
      GamepadChannel.setMouseEmulation(false);
      return;
    }

    setState(() {
      _gamepadMouseActive = !_gamepadMouseActive;
      if (_gamepadMouseActive) {
        _touchMode = MouseMode.mouse;
      } else {
        _touchMode = _config.mouseMode;
      }
    });

    GamepadChannel.setMouseEmulation(_gamepadMouseActive);
    _showModeSnackbar();
  }

  void _showModeSnackbar() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();

    final lang = AppLocalizations.of(context).locale.languageCode;
    final label = _gamepadMouseActive
        ? (lang == 'es' ? 'GAMEPAD \u2192 MOUSE' : 'GAMEPAD \u2192 MOUSE')
        : (lang == 'es' ? 'MOUSE \u2192 GAMEPAD' : 'MOUSE \u2192 GAMEPAD');

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(80, 0, 80, 32),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(milliseconds: 1500),
        dismissDirection: DismissDirection.none,
      ),
    );
  }

  String get _touchModeLabel {
    if (_gamepadMouseActive) return 'Mouse: ON';
    return switch (_touchMode) {
      MouseMode.directTouch => AppLocalizations.of(context).pointAndClick,
      MouseMode.trackpad => AppLocalizations.of(context).trackpadLabel,
      MouseMode.mouse => AppLocalizations.of(context).mouseLabel,
    };
  }

  IconData get _touchModeIcon => switch (_touchMode) {
    MouseMode.directTouch => Icons.touch_app,
    MouseMode.trackpad => Icons.gesture,
    MouseMode.mouse => Icons.mouse,
  };

  BoxFit get _videoBoxFit => switch (_config.scaleMode) {
    VideoScaleMode.fit => BoxFit.contain,
    VideoScaleMode.fill => BoxFit.cover,
    VideoScaleMode.stretch => BoxFit.fill,
  };

  Widget _buildVideoLayer() {
    if (_config.enableDirectSubmit && (_isConnecting || _usingDirectSubmit)) {
      final aspectRatio = _config.width / _config.height;
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: const AndroidView(
              viewType: 'com.jujostream/direct_submit_surface',
              creationParamsCodec: StandardMessageCodec(),
            ),
          ),
        ),
      );
    }
    if (_textureId != null) {
      // Black background prevents green flicker from codec alignment padding.
      // MediaCodec may output frames padded to macroblock boundaries (e.g.
      // 1080→1088 for H.264 16-px alignment). The SurfaceTexture contains
      // the full padded buffer; ClipRect hides the uninitialised green edge.
      return ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(
          child: FittedBox(
            fit: _videoBoxFit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: _config.width.toDouble(),
              height: _config.height.toDouble(),
              child: Texture(textureId: _textureId!),
            ),
          ),
        ),
      );
    }
    return Container(
      color: Colors.black,
      child: const Center(
        child: Text(
          'Video stream will render here via native Texture widget.\n\n'
          'The native layer (Platform Channel) provides a TextureId\n'
          'backed by MediaCodec (Android) or VideoToolbox (iOS).',
          style: TextStyle(color: Colors.white38, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildLocalCursor() {
    const sz = 18.0;
    return Positioned(
      left: _cursorX - sz / 2,
      top: _cursorY - sz / 2,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _cursorVisible ? 0.7 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: SizedBox(
            width: sz,
            height: sz,
            child: CustomPaint(painter: _CursorDotPainter()),
          ),
        ),
      ),
    );
  }

  Widget _buildInputLayer() {
    // ── Determine the touch/mouse child widget ──────────────────────────
    //
    // Input mode priority:
    //   1. Gamepad mouse emulation active → trackpad (relative deltas via stick)
    //   2. directTouch mode → TRUE point-and-click emulation (mouse position + click)
    //      Sub-mode: multiTouchGestures ON → absolute multi-touch passthrough
    //                (only when explicitly enabled; default is point-and-click)
    //   3. trackpad / mouse mode → relative trackpad handler
    //
    // IMPORTANT: directTouch mode ALWAYS uses point-and-click (sendMousePosition
    // + sendMouseButton) as the primary behavior. multiTouchGestures is an
    // opt-in sub-mode that switches to raw touch passthrough (sendTouchEvent)
    // for apps that natively support touch input.
    Widget child;
    if (_gamepadMouseActive) {
      // Gamepad stick → mouse: use trackpad handler for relative deltas
      child = _trackpadHandler.buildInputLayer(
        sensitivityX: _config.trackpadSensitivityX.toDouble(),
        sensitivityY: _config.trackpadSensitivityY.toDouble(),
      );
    } else if (_touchMode == MouseMode.directTouch) {
      if (_config.multiTouchGestures) {
        // Explicit multi-touch passthrough: raw touch events for apps that
        // natively support touch input (e.g., Android games on the server).
        child = _directTouchHandler.buildAbsoluteTouchInputLayer();
      } else {
        // TRUE point-and-click: touch position → cursor teleport → click.
        // This is the default and expected behavior for "Point and Click" mode.
        child = _directTouchHandler.buildDirectTouchInputLayer();
      }
    } else {
      child = _trackpadHandler.buildInputLayer(
        sensitivityX: _config.trackpadSensitivityX.toDouble(),
        sensitivityY: _config.trackpadSensitivityY.toDouble(),
      );
    }

    // ── Cursor visibility ───────────────────────────────────────────────
    // Always hide the OS cursor during streaming. The server renders its
    // own cursor inside the video feed — showing the Flutter OS cursor on
    // top creates a visible "dual cursor" artifact. Mouse movement is
    // still forwarded to the server via onHover / native bridge; only the
    // local OS pointer graphic is suppressed.
    const cursorStyle = SystemMouseCursors.none;

    // ── MouseRegion: physical mouse hover → absolute position ───────────
    // Only send absolute mouse position when in directTouch mode AND no
    // touch gesture is currently active. This prevents the dual-source
    // race condition where both MouseRegion.onHover and DirectTouchHandler
    // send competing position updates simultaneously.
    //
    // On mobile: onHover fires during touch-move, so we MUST gate it
    // behind isTouchActive to prevent fighting with the Listener.
    //
    // On desktop: onHover fires from physical mouse movement (no touch),
    // so it correctly drives the cursor when no touch is happening.
    //
    // When gamepad-mouse emulation is active the native GamepadHandler
    // drives the cursor via nativeSendMouseMove — Flutter must NOT also
    // send absolute position or the two fight each other.
    return MouseRegion(
      cursor: cursorStyle,
      onHover: (event) {
        if (!_isConnected) return;
        // Only forward hover as absolute position in directTouch mode
        // (point-and-click) when NO touch gesture is active.
        // This eliminates the race between MouseRegion and DirectTouchHandler.
        if (_touchMode == MouseMode.directTouch &&
            !_gamepadMouseActive &&
            !_directTouchHandler.isTouchActive) {
          final coords = _touchToStreamCoords(event.localPosition);
          StreamingPlatformChannel.sendMousePosition(
            coords.$1,
            coords.$2,
            _config.width,
            _config.height,
          );
          _updateLocalCursor(event.localPosition.dx, event.localPosition.dy);
        }
      },
      child: child,
    );
  }

  (int x, int y) _touchToStreamCoords(Offset touchPos) {
    final screenSize = MediaQuery.sizeOf(context);
    final sw = screenSize.width;
    final sh = screenSize.height;
    final vw = _config.width.toDouble();
    final vh = _config.height.toDouble();

    double videoLeft = 0, videoTop = 0, videoW = sw, videoH = sh;

    // ── Determine the effective BoxFit for the active render path ────────
    //
    // The Texture path uses FittedBox with _videoBoxFit (contain/cover/fill
    // based on user's scaleMode setting).
    //
    // The DirectSubmit path uses Center → AspectRatio → AndroidView, which
    // is structurally equivalent to BoxFit.contain regardless of the user's
    // scaleMode setting. The AspectRatio widget constrains the child to the
    // stream's aspect ratio, and Center places it in the middle — producing
    // letterbox/pillarbox bars identical to BoxFit.contain.
    //
    // Using the wrong BoxFit for coordinate mapping causes touch positions
    // to be offset by the difference in letterboxing between the two layouts.
    final effectiveFit = _usingDirectSubmit ? BoxFit.contain : _videoBoxFit;

    switch (effectiveFit) {
      case BoxFit.contain:
        final scaleX = sw / vw;
        final scaleY = sh / vh;
        final scale = scaleX < scaleY ? scaleX : scaleY;
        videoW = vw * scale;
        videoH = vh * scale;
        videoLeft = (sw - videoW) / 2;
        videoTop = (sh - videoH) / 2;
      case BoxFit.cover:
        final scaleX = sw / vw;
        final scaleY = sh / vh;
        final scale = scaleX > scaleY ? scaleX : scaleY;
        videoW = vw * scale;
        videoH = vh * scale;
        videoLeft = (sw - videoW) / 2;
        videoTop = (sh - videoH) / 2;
      case BoxFit.fill:
        break;
      default:
        break;
    }

    final relX = (touchPos.dx - videoLeft) / videoW;
    final relY = (touchPos.dy - videoTop) / videoH;
    final x = (relX * vw).round().clamp(0, _config.width);
    final y = (relY * vh).round().clamp(0, _config.height);
    return (x, y);
  }

  void _updateLocalCursor(double px, double py) {
    if (!_config.mouseLocalCursor) return;
    setState(() {
      _cursorX = px;
      _cursorY = py;
      _cursorVisible = true;
    });
    final id = ++_cursorHideTimer;
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted || _cursorHideTimer != id) return;
      setState(() => _cursorVisible = false);
    });
  }

  Widget _buildConnectingOverlay() {
    final l = AppLocalizations.of(context);
    final isPro = ProService.kDevMode || context.read<ProService>().isPro;

    if (isPro) {
      return _ImmersiveLoadingOverlay(
        app: widget.app,
        computer: widget.computer,
        stageName: _currentStageName,
        stageIndex: _currentStageIndex,
        reconnectMessage: _reconnectMessage,
      );
    }

    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: context.read<ThemeProvider>().accent,
            ),
            const SizedBox(height: 24),
            Text(
              _reconnectMessage ?? l.connecting(widget.app.appName),
              style: const TextStyle(color: Colors.white, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.computer.name,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  int _errorSelectedButton = 0;

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ErrorButton(
                  label: AppLocalizations.of(context).retry,
                  icon: Icons.refresh,
                  selected: _errorSelectedButton == 0,
                  onPressed: _startStreaming,
                ),
                const SizedBox(width: 16),
                _ErrorButton(
                  label: AppLocalizations.of(context).back,
                  icon: Icons.arrow_back,
                  selected: _errorSelectedButton == 1,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Ⓐ ${AppLocalizations.of(context).retry}  ◀▶  Ⓑ ${AppLocalizations.of(context).back}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _onOverlayKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.gameButtonB ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      if (_showQuitConfirm) {
        setState(() {
          _showQuitConfirm = false;
          _overlayRow = 5;
        });
      } else if (_showSpecialKeys) {
        setState(() {
          _showSpecialKeys = false;
          _overlayRow = 0;
          _overlayCol = 0;
        });
      } else {
        _setOverlayVisible(false);
      }
      return KeyEventResult.handled;
    }

    if (_showQuitConfirm) {
      if (key == LogicalKeyboardKey.gameButtonX) {
        setState(() {
          _showQuitConfirm = false;
          _overlayRow = 5;
        });
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.gameButtonA) {
        if (_quitConfirmSelection == 0) {
          setState(() {
            _showQuitConfirm = false;
            _overlayRow = 5;
          });
        } else {
          _executeQuit();
        }
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.gameButtonY) {
        _executeQuit();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        setState(() => _quitConfirmSelection = 1 - _quitConfirmSelection);
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.select) {
        if (_quitConfirmSelection == 0) {
          setState(() {
            _showQuitConfirm = false;
            _overlayRow = 5;
          });
        } else {
          _executeQuit();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (!_showSpecialKeys) {
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _overlayRow = (_overlayRow + 1).clamp(0, 6);
          if (_overlayRow == 0) {
            _overlayCol = _overlayCol.clamp(0, 3);
          } else if (_overlayRow == 1) {
            _overlayCol = _overlayCol.clamp(0, _toggleCount - 1);
          } else {
            _overlayCol = 0;
          }
        });
        _scrollOverlayToFocusedRow();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _overlayRow = (_overlayRow - 1).clamp(0, 6);
          if (_overlayRow == 0) {
            _overlayCol = _overlayCol.clamp(0, 3);
          } else if (_overlayRow == 1) {
            _overlayCol = _overlayCol.clamp(0, _toggleCount - 1);
          } else {
            _overlayCol = 0;
          }
        });
        _scrollOverlayToFocusedRow();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (_overlayRow == 0) {
          setState(() => _overlayCol = (_overlayCol - 1).clamp(0, 3));
        } else if (_overlayRow == 1) {
          setState(
            () => _overlayCol = (_overlayCol - 1).clamp(0, _toggleCount - 1),
          );
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        if (_overlayRow == 0) {
          setState(() => _overlayCol = (_overlayCol + 1).clamp(0, 3));
        } else if (_overlayRow == 1) {
          setState(
            () => _overlayCol = (_overlayCol + 1).clamp(0, _toggleCount - 1),
          );
        }
        return KeyEventResult.handled;
      }
    } else {
      if (key == LogicalKeyboardKey.arrowLeft) {
        setState(
          () => _specialKeyIdx =
              (_specialKeyIdx - 1 + specialKeyCount) % specialKeyCount,
        );
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        setState(() => _specialKeyIdx = (_specialKeyIdx + 1) % specialKeyCount);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        final next = specialKeySections.firstWhere(
          (s) => s > _specialKeyIdx,
          orElse: () => specialKeySections.first,
        );
        setState(() => _specialKeyIdx = next);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        final prev = specialKeySections.lastWhere(
          (s) => s < _specialKeyIdx,
          orElse: () => specialKeySections.last,
        );
        setState(() => _specialKeyIdx = prev);
        return KeyEventResult.handled;
      }
    }

    // Y button toggles favourite when in special keys view
    if (_showSpecialKeys && key == LogicalKeyboardKey.gameButtonY) {
      _toggleFavoriteSpecialKey(_specialKeyIdx);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.select) {
      if (_showSpecialKeys) {
        _activateSpecialKey(_specialKeyIdx);
      } else {
        _activateOverlayCurrentItem();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.handled;
  }

  void _scrollOverlayToFocusedRow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_overlayScrollController.hasClients) return;

      const headerH = 36.0;
      const qualityH = 88.0;
      const divH = 9.0;
      const togglesH = 68.0;
      const tileH = 48.0;
      final maxScroll = _overlayScrollController.position.maxScrollExtent;
      if (maxScroll <= 0) return;
      final rowTop = switch (_overlayRow) {
        0 => 0.0,
        1 => headerH + qualityH + divH,
        2 => headerH + qualityH + divH + togglesH + divH,
        3 => headerH + qualityH + divH + togglesH + divH + tileH,

        _ => maxScroll,
      };
      _overlayScrollController.animateTo(
        rowTop.clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  void _scrollToFocusedSpecialKey() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_overlayScrollController.hasClients) return;
      final maxScroll = _overlayScrollController.position.maxScrollExtent;
      if (maxScroll <= 0) return;

      const headerH = 56.0;
      const sectionH = 30.0;
      const wrapRowH = 50.0;
      double target;
      if (_specialKeyIdx < 10) {
        target = 0.0;
      } else if (_specialKeyIdx < 16) {
        target = headerH + sectionH + wrapRowH * 2;
      } else if (_specialKeyIdx < 22) {
        target = headerH + sectionH * 2 + wrapRowH * 4;
      } else {
        target = maxScroll;
      }
      _overlayScrollController.animateTo(
        target.clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _buildMenuOverlay() {
    final tp = context.read<ThemeProvider>();
    final bgColor = tp.background;
    final viewport = MediaQuery.sizeOf(context);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return GestureDetector(
      onTap: () => _setOverlayVisible(false),
      child: Container(
        color: Colors.black54,
        child: Center(
          child: Focus(
            focusNode: _overlayFocusNode,
            autofocus: true,
            onKeyEvent: _onOverlayKeyEvent,
            child: Container(
              width: viewport.width > 468 ? 420 : viewport.width - 48,
              constraints: BoxConstraints(
                maxHeight: viewport.height * (isLandscape ? 0.88 : 0.78),
              ),
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SingleChildScrollView(
                  controller: _overlayScrollController,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 8,
                    ),
                    child: _showSpecialKeys
                        ? _buildSpecialKeysPanel()
                        : _showQuitConfirm
                        ? _buildQuitConfirmPanel()
                        : _buildQuickMenuPanel(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuitConfirmPanel() {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.power_settings_new, color: Colors.redAccent, size: 36),
        const SizedBox(height: 12),
        Text(
          l.quitSessionQuestion,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          l.quitSessionDesc,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _quitButton(
                icon: Icons.close_rounded,
                label: l.cancel,
                badgeWidget: GamepadHintIcon('Ⓧ', size: 18),
                focused: _quitConfirmSelection == 0,
                onTap: () {
                  setState(() {
                    _showQuitConfirm = false;
                    _overlayRow = 5;
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _quitButton(
                icon: Icons.check_rounded,
                label: l.quit,
                badgeWidget: GamepadHintIcon('Ⓨ', size: 18),
                focused: _quitConfirmSelection == 1,
                color: Colors.redAccent,
                onTap: _executeQuit,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          AppLocalizations.of(context).navConfirmBack,
          style: TextStyle(color: Colors.white24, fontSize: 10),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _quitButton({
    required IconData icon,
    required String label,
    required Widget badgeWidget,
    required bool focused,
    required VoidCallback onTap,
    Color color = Colors.white70,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: focused
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: focused
              ? Border.all(color: Colors.white54, width: 1.5)
              : Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: focused ? Colors.white : color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: focused ? Colors.white : color,
                fontWeight: focused ? FontWeight.w600 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            badgeWidget,
          ],
        ),
      ),
    );
  }

  Future<void> _executeQuit() async {
    _userInitiatedQuit = true;
    _setOverlayVisible(false);
    try {
      await context.read<AppListProvider>().quitApp();
    } catch (e) {
      debugPrint(
        '[JUJO][quit] quitApp failed: $e — proceeding with disconnect',
      );
    }
    await _stopStreaming(clearActiveSession: true);
    await _showSessionMetricsIfNeeded();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _closeSessionAndExit() async {
    await _stopStreaming(clearActiveSession: false);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pasteClipboardToPC() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = data?.text;
    if (txt == null || txt.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Clipboard is empty',
              style: TextStyle(color: Colors.white),
            ),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.black87,
          ),
        );
      }
      return;
    }
    StreamingPlatformChannel.sendUtf8Text(txt);
    _setOverlayVisible(false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pasted ${txt.length} chars to PC',
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 1),
          backgroundColor: Colors.black87,
        ),
      );
    }
  }

  Future<void> _showSessionMetricsIfNeeded() async {
    if (!_config.enableSessionMetrics ||
        _sessionMetrics.isEmpty ||
        _sessionMetricsDialogShown ||
        !mounted) {
      return;
    }
    _sessionMetricsDialogShown = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => SessionMetricsDialog(
        appName: widget.app.appName,
        points: List<SessionMetricPoint>.unmodifiable(_sessionMetrics),
        config: _config,
        decoder: _codec != '--' ? _codec : null,
      ),
    );
  }

  Widget _buildQuickMenuPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.settings, color: Colors.white54, size: 20),
            const SizedBox(width: 8),
            Text(
              widget.app.appName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        _buildQualityPresetsRow(),
        const SizedBox(height: 4),
        const Divider(color: Colors.white12, height: 1),
        const SizedBox(height: 4),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            buildQuickToggle(
              _touchModeIcon,
              _touchModeLabel,
              _gamepadMouseActive,
              _cycleTouchMode,
              focused: _overlayRow == 1 && _overlayCol == 0,
            ),
            buildQuickToggle(
              Icons.speed,
              AppLocalizations.of(context).stats,
              _showPerfStats,
              () {
                setState(() => _showPerfStats = !_showPerfStats);
              },
              focused: _overlayRow == 1 && _overlayCol == 1,
            ),
            buildQuickToggle(
              Icons.gamepad,
              AppLocalizations.of(context).gamepadLabel,
              _showGamepad,
              () {
                setState(() => _showGamepad = !_showGamepad);
              },
              focused: _overlayRow == 1 && _overlayCol == 2,
            ),
            if (_config.multiControllerEnabled)
              buildQuickToggle(
                Icons.sports_esports,
                'P${_activeControllerSlot + 1}',
                true,
                () => setState(() {
                  final max = _config.controllerCount.clamp(1, 4);
                  _activeControllerSlot = (_activeControllerSlot + 1) % max;
                }),
                focused: _overlayRow == 1 && _overlayCol == 3,
              ),
            buildQuickToggle(
              Icons.keyboard,
              AppLocalizations.of(context).keyboard,
              _keyboardVisible,
              _toggleKeyboard,
              focused:
                  _overlayRow == 1 &&
                  _overlayCol == (_config.multiControllerEnabled ? 4 : 3),
            ),
            buildQuickToggle(
              Icons.zoom_out_map,
              'Pan&Zoom',
              _panZoomActive,
              _togglePanZoom,
              focused:
                  _overlayRow == 1 &&
                  _overlayCol == (_config.multiControllerEnabled ? 5 : 4),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Divider(color: Colors.white12, height: 1),
        const SizedBox(height: 4),

        buildMenuTile(
          Icons.keyboard_command_key,
          AppLocalizations.of(context).specialKeys,
          () {
            setState(() => _showSpecialKeys = true);
          },
          focused: _overlayRow == 2,
        ),
        buildMenuTile(
          Icons.content_paste_go,
          'Paste to PC',
          _pasteClipboardToPC,
          focused: _overlayRow == 3,
        ),
        buildMenuTile(
          Icons.logout_rounded,
          AppLocalizations.of(context).disconnect,
          () {
            _stopStreaming(clearActiveSession: false);
            Navigator.pop(context);
          },
          color: Colors.orangeAccent,
          focused: _overlayRow == 4,
        ),
        buildMenuTile(
          Icons.power_settings_new,
          AppLocalizations.of(context).closeSession,
          () {
            _confirmQuit();
          },
          color: Colors.redAccent,
          focused: _overlayRow == 5,
        ),
        const SizedBox(height: 4),
        buildMenuTile(
          Icons.close,
          AppLocalizations.of(context).closeMenu,
          () {
            _setOverlayVisible(false);
          },
          focused: _overlayRow == 6,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            AppLocalizations.of(context).menuHint,
            style: TextStyle(color: Colors.white24, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  void _applyQualityPreset(String preset) {
    if (preset == 'app_controlled') {
      _activeOverlayPreset = null;
      _config =
          widget.overrideConfig ?? context.read<SettingsProvider>().config;
    } else {
      _activeOverlayPreset = preset;
      switch (preset) {
        case 'fast':
          _config = _config.copyWith(bitrate: 10000, fps: 60);
        case 'balanced':
          _config = _config.copyWith(bitrate: 30000, fps: 60);
        case 'quality':
          _config = _config.copyWith(bitrate: 80000, fps: 60);
      }
    }

    _setOverlayVisible(false);
    _reconnectWithNewConfig();
  }

  Future<void> _reconnectWithNewConfig() async {
    _isReconnecting = true;
    _presetReconnectRetries = 0;
    setState(() {
      _isConnected = false;
      _isConnecting = true;
      _reconnectMessage = AppLocalizations.of(context).applyingPreset;
      _textureId = null;
    });
    await _stopStreaming();

    await Future.delayed(const Duration(milliseconds: 6000));
    if (!mounted) return;

    await GamepadChannel.setStreamingActive(false);

    _lastDisconnectTime = DateTime.now().subtract(const Duration(seconds: 10));
    debugPrint(
      'Preset reconnect: starting stream with ${_config.bitrate} kbps / ${_config.fps} fps',
    );
    _startStreaming();

    Future.delayed(const Duration(seconds: 25), () {
      if (mounted && _isReconnecting) {
        debugPrint(
          'Preset reconnect: safety timeout — clearing _isReconnecting',
        );
        _isReconnecting = false;
      }
    });
  }

  String get _currentQualityPreset {
    return _activeOverlayPreset ?? 'app_controlled';
  }

  static const bool _presetsEnabled = false;

  Widget _buildQualityPresetsRow() {
    final l = AppLocalizations.of(context);
    final presets = [
      (
        id: 'app_controlled',
        label: l.appControlled,
        icon: Icons.settings_suggest,
        subtitle: '${_config.bitrate ~/ 1000} Mbps · ${_config.fps} fps',
      ),
      (id: 'fast', label: l.fast, icon: Icons.bolt, subtitle: '~10 Mbps'),
      (
        id: 'balanced',
        label: l.balanced,
        icon: Icons.tune,
        subtitle: '~30 Mbps',
      ),
      (
        id: 'quality',
        label: l.quality,
        icon: Icons.diamond_outlined,
        subtitle: '~80 Mbps',
      ),
    ];
    final active = _currentQualityPreset;
    return Opacity(
      opacity: _presetsEnabled ? 1.0 : 0.35,
      child: AbsorbPointer(
        absorbing: !_presetsEnabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                children: [
                  Text(
                    AppLocalizations.of(context).streamQualityLabel,
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                    ),
                  ),
                  if (!_presetsEnabled) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Coming Soon',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(presets.length, (i) {
                final p = presets[i];
                final isActive = _presetsEnabled && active == p.id;
                final isFocused =
                    _presetsEnabled && _overlayRow == 0 && _overlayCol == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _applyQualityPreset(p.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white.withValues(alpha: 0.12)
                            : isFocused
                            ? Colors.white.withValues(alpha: 0.10)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isFocused
                              ? Colors.white54
                              : isActive
                              ? Colors.white38
                              : Colors.white12,
                          width: isFocused ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            p.icon,
                            color: isActive || isFocused
                                ? Colors.white
                                : Colors.white54,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              p.label,
                              style: TextStyle(
                                color: isActive || isFocused
                                    ? Colors.white
                                    : Colors.white54,
                                fontSize: 10,
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialKeysPanel() {
    return buildSpecialKeysPanel(
      specialKeys: _specialKeys,
      focusedIndex: _specialKeyIdx,
      descriptionResolver: (key) =>
          AppLocalizations.of(context).specialKeyDesc(key),
      onActivate: _activateSpecialKey,
      onBack: () => setState(() => _showSpecialKeys = false),
      onCloseOverlay: () => _setOverlayVisible(false),
      closeMenuLabel: AppLocalizations.of(context).closeMenu,
      specialKeysLabel: AppLocalizations.of(context).specialKeys,
      favoriteIndices: _config.favoriteSpecialKeys,
      onToggleFavorite: _toggleFavoriteSpecialKey,
    );
  }

  void _confirmQuit() {
    setState(() {
      _showQuitConfirm = true;
      _quitConfirmSelection = 0;
    });
  }

  Widget _buildPerfOverlay() {
    final isPro = ProService.kDevMode || context.read<ProService>().isPro;
    if (isPro) {
      return StreamHud(
        fps: _fps,
        latency: _latency,
        bitrate: _bitrate,
        dropRate: _dropRate,
        resolution: _resolution,
        codec: _codec,
        queueDepth: _queueDepth,
        pendingAudioMs: _pendingAudioMs,
        rttVariance: _rttVariance,
        renderPath: _renderPath,
      );
    }
    return buildBasicPerfOverlay(
      fps: _fps,
      latency: _latency,
      bitrate: _bitrate,
      dropRate: _dropRate,
      resolution: _resolution,
      pendingAudioMs: _pendingAudioMs,
    );
  }

  int get _activeGamepadMask {
    if (!_config.multiControllerEnabled) {
      return 1;
    }
    final count = _config.controllerCount.clamp(1, 4);
    return (1 << count) - 1;
  }

  void _toggleKeyboard() {
    _setOverlayVisible(false);
    setState(() => _keyboardVisible = !_keyboardVisible);
    if (_keyboardVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _keyboardFocusNode.requestFocus();
        SystemChannels.textInput.invokeMethod('TextInput.show');
      });
    } else {
      _keyboardFocusNode.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      _streamFocusNode.requestFocus();
    }
  }

  Widget _buildHiddenKeyboardField() {
    return Positioned(
      left: -500,
      top: -500,
      child: SizedBox(
        width: 1,
        height: 1,
        child: TextField(
          focusNode: _keyboardFocusNode,
          controller: _keyboardController,
          autofocus: false,
          enableSuggestions: false,
          autocorrect: false,
          showCursor: false,
          style: const TextStyle(fontSize: 1, color: Colors.transparent),
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isDense: true,
          ),
          onChanged: (value) {
            if (value.isEmpty) {
              sendKey(0x08);
            } else {
              final lastChar = value[value.length - 1];
              if (lastChar == '\n') {
                sendKey(0x0D);
              } else {
                final vk = _charToVk(lastChar);
                if (vk != null) sendKey(vk);
              }
            }

            _keyboardController.value = const TextEditingValue(
              text: ' ',
              selection: TextSelection.collapsed(offset: 1),
            );
          },
          onSubmitted: (_) {
            sendKey(0x0D);

            _keyboardFocusNode.requestFocus();
          },
        ),
      ),
    );
  }

  static int? _charToVk(String char) {
    final c = char.toUpperCase().codeUnitAt(0);

    if (c >= 0x41 && c <= 0x5A) return c;

    if (c >= 0x30 && c <= 0x39) return c;
    return switch (char) {
      ' ' => 0x20,
      '\t' => 0x09,
      '-' => 0xBD,
      '=' => 0xBB,
      '[' => 0xDB,
      ']' => 0xDD,
      '\\' => 0xDC,
      ';' => 0xBA,
      '\'' => 0xDE,
      ',' => 0xBC,
      '.' => 0xBE,
      '/' => 0xBF,
      '`' => 0xC0,
      _ => null,
    };
  }
}

class _ImmersiveLoadingOverlay extends StatelessWidget {
  final NvApp app;
  final ComputerDetails computer;
  final String stageName;
  final int stageIndex;
  final String? reconnectMessage;

  const _ImmersiveLoadingOverlay({
    required this.app,
    required this.computer,
    required this.stageName,
    required this.stageIndex,
    this.reconnectMessage,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final totalStages = 6;
    final safeStage = stageIndex.clamp(0, totalStages);
    final progress = safeStage / totalStages;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (app.posterUrl != null && app.posterUrl!.isNotEmpty)
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.65),
              BlendMode.darken,
            ),
            child: Hero(
              tag: 'game-poster-${app.appId}',
              child: Image.network(
                app.posterUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: Color(0xFF0D0818)),
              ),
            ),
          )
        else
          const ColoredBox(color: Color(0xFF0D0818)),

        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.2,
              colors: [Colors.transparent, Colors.black87],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                app.appName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                computer.name,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 24),

              Text(
                reconnectMessage ??
                    (stageName.isNotEmpty ? stageName : l.starting),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 10),

              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: stageName.isEmpty ? null : progress,
                  minHeight: 3,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF9B72CF)),
                ),
              ),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  const _ErrorButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: selected
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? Colors.white54 : Colors.white24,
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: selected ? Colors.white : Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CursorDotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    // outer ring
    canvas.drawCircle(
      c,
      size.width / 2,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // inner dot
    canvas.drawCircle(
      c,
      3.0,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
