import 'dart:io' show Platform;

class StreamConfiguration {
  final int width;
  final int height;
  final int fps;
  final int bitrate;
  final bool enableHdr;
  final VideoCodec videoCodec;
  final VideoScaleMode scaleMode;
  final FramePacing framePacing;
  final bool fullRange;

  final AudioConfig audioConfig;
  final AudioQuality audioQuality;
  final bool playLocalAudio;
  final bool enableAudioFx;

  final bool enableSops;

  final MouseMode mouseMode;
  final bool mouseEmulation;
  final bool gamepadMouseEmulation;
  final bool mouseLocalCursor;
  final bool multiTouchGestures;
  final bool absoluteMouseMode;
  final int trackpadSensitivityX;
  final int trackpadSensitivityY;

  final bool forceQwertyLayout;
  final bool backButtonAsMeta;
  final bool backButtonAsGuide;

  final int deadzone;
  final bool flipFaceButtons;
  final bool multiControllerEnabled;
  final int controllerCount;
  final ControllerDriver controllerDriver;
  final bool usbDriverEnabled;
  final bool usbBindAll;
  final bool joyCon;
  final bool gamepadBatteryReport;
  final bool gamepadMotionSensors;
  final bool gamepadMotionFallback;
  final bool gamepadTouchpadAsMouse;
  final ButtonRemapProfile buttonRemapProfile;
  final Map<int, int> customRemapTable;
  final double gamepadMouseSpeed;

  final bool ultraLowLatency;
  final bool lowLatencyFrameBalance;

  final bool enableRumble;
  final bool vibrateFallback;
  final bool deviceRumble;
  final int vibrateFallbackStrength;

  final bool showOnscreenControls;
  final bool hideOscWithGamepad;
  final int oscOpacity;

  final bool smartBitrateEnabled;
  final int smartBitrateMin;
  final int smartBitrateMax;

  final bool enablePerfOverlay;
  final bool pipEnabled;
  final bool enableSessionMetrics;

  final bool dynamicBitrateEnabled;
  final int dynamicBitrateSensitivity;

  final bool hapticOverlay;
  final bool streamNotification;
  final bool screenshotEnabled;
  final int screenshotCombo;
  final int screenshotHoldMs;

  final int overlayTriggerCombo;
  final int overlayTriggerHoldMs;

  /// Desktop keyboard combo to open the in-stream overlay (macOS/Windows).
  /// Stored as a List of key labels, e.g. ['Shift', '-'].
  /// Default matches the hard-coded Shift+- shortcut.
  final List<String> desktopOverlayKeys;
  final int desktopOverlayHoldMs;

  final int panicCombo;
  final int panicHoldMs;

  final int mouseModeCombo;
  final int mouseModeHoldMs;

  final int frameQueueDepth;
  final bool choreographerVsync;
  final bool enableVrr;
  final bool enableDirectSubmit;
  final bool hostPresetOverrideEnabled;
  final String hostPresetOverrideId;

  const StreamConfiguration({
    this.width = 1920,
    this.height = 1080,
    this.fps = 60,
    this.bitrate = 20000,
    this.enableHdr = false,
    this.videoCodec = VideoCodec.auto,
    this.scaleMode = VideoScaleMode.fit,
    this.framePacing = FramePacing.adaptive,
    this.fullRange = false,
    this.audioConfig = AudioConfig.stereo,
    this.audioQuality = AudioQuality.high,
    this.playLocalAudio = false,
    this.enableAudioFx = false,
    this.enableSops = true,
    this.mouseMode = MouseMode.directTouch,
    this.mouseEmulation = true,
    this.gamepadMouseEmulation = true,
    this.mouseLocalCursor = false,
    this.multiTouchGestures = true,
    this.absoluteMouseMode = false,
    this.trackpadSensitivityX = 100,
    this.trackpadSensitivityY = 100,
    this.forceQwertyLayout = true,
    this.backButtonAsMeta = false,
    this.backButtonAsGuide = false,
    this.deadzone = 5,
    this.flipFaceButtons = false,
    this.multiControllerEnabled = true,
    this.controllerCount = 0,
    this.controllerDriver = ControllerDriver.auto,
    this.usbDriverEnabled = true,
    this.usbBindAll = false,
    this.joyCon = false,
    this.gamepadBatteryReport = true,
    this.gamepadMotionSensors = true,
    this.gamepadMotionFallback = false,
    this.gamepadTouchpadAsMouse = false,
    this.buttonRemapProfile = ButtonRemapProfile.none,
    this.customRemapTable = const {},
    this.gamepadMouseSpeed = 1.75,
    this.ultraLowLatency = false,
    this.lowLatencyFrameBalance = false,
    this.enableRumble = true,
    this.vibrateFallback = true,
    this.deviceRumble = false,
    this.vibrateFallbackStrength = 100,
    this.showOnscreenControls = false,
    this.hideOscWithGamepad = true,
    this.oscOpacity = 90,
    this.smartBitrateEnabled = false,
    this.smartBitrateMin = 10000,
    this.smartBitrateMax = 35000,
    this.enablePerfOverlay = false,
    this.pipEnabled = true,
    this.enableSessionMetrics = true,
    this.dynamicBitrateEnabled = false,
    this.dynamicBitrateSensitivity = 2,
    this.hapticOverlay = true,
    this.streamNotification = true,
    this.screenshotEnabled = true,
    this.screenshotCombo = 0x0220,
    this.screenshotHoldMs = 2500,
    this.overlayTriggerCombo = 0x00C0,
    this.overlayTriggerHoldMs = 2000,
    this.desktopOverlayKeys = const ['Shift', '-'],
    this.desktopOverlayHoldMs = 0,
    this.panicCombo = 0,
    this.panicHoldMs = 2000,
    this.mouseModeCombo = 0x0020,
    this.mouseModeHoldMs = 2000,
    this.frameQueueDepth = 0,
    this.choreographerVsync = false,
    this.enableVrr = false,
    this.enableDirectSubmit = false,
    this.hostPresetOverrideEnabled = false,
    this.hostPresetOverrideId = '',
  });

  StreamConfiguration copyWith({
    int? width,
    int? height,
    int? fps,
    int? bitrate,
    bool? enableHdr,
    VideoCodec? videoCodec,
    VideoScaleMode? scaleMode,
    FramePacing? framePacing,
    bool? fullRange,
    AudioConfig? audioConfig,
    AudioQuality? audioQuality,
    bool? playLocalAudio,
    bool? enableAudioFx,
    bool? enableSops,
    MouseMode? mouseMode,
    bool? mouseEmulation,
    bool? gamepadMouseEmulation,
    bool? mouseLocalCursor,
    bool? multiTouchGestures,
    bool? absoluteMouseMode,
    int? trackpadSensitivityX,
    int? trackpadSensitivityY,
    bool? forceQwertyLayout,
    bool? backButtonAsMeta,
    bool? backButtonAsGuide,
    int? deadzone,
    bool? flipFaceButtons,
    bool? multiControllerEnabled,
    int? controllerCount,
    ControllerDriver? controllerDriver,
    bool? usbDriverEnabled,
    bool? usbBindAll,
    bool? joyCon,
    bool? gamepadBatteryReport,
    bool? gamepadMotionSensors,
    bool? gamepadMotionFallback,
    bool? gamepadTouchpadAsMouse,
    ButtonRemapProfile? buttonRemapProfile,
    Map<int, int>? customRemapTable,
    double? gamepadMouseSpeed,
    bool? ultraLowLatency,
    bool? lowLatencyFrameBalance,
    bool? enableRumble,
    bool? vibrateFallback,
    bool? deviceRumble,
    int? vibrateFallbackStrength,
    bool? showOnscreenControls,
    bool? hideOscWithGamepad,
    int? oscOpacity,
    bool? smartBitrateEnabled,
    int? smartBitrateMin,
    int? smartBitrateMax,
    bool? enablePerfOverlay,
    bool? pipEnabled,
    bool? enableSessionMetrics,
    bool? dynamicBitrateEnabled,
    int? dynamicBitrateSensitivity,
    bool? hapticOverlay,
    bool? streamNotification,
    bool? screenshotEnabled,
    int? screenshotCombo,
    int? screenshotHoldMs,
    int? overlayTriggerCombo,
    int? overlayTriggerHoldMs,
    List<String>? desktopOverlayKeys,
    int? desktopOverlayHoldMs,
    int? panicCombo,
    int? panicHoldMs,
    int? mouseModeCombo,
    int? mouseModeHoldMs,
    int? frameQueueDepth,
    bool? choreographerVsync,
    bool? enableVrr,
    bool? enableDirectSubmit,
    bool? hostPresetOverrideEnabled,
    String? hostPresetOverrideId,
  }) {
    return StreamConfiguration(
      width: width ?? this.width,
      height: height ?? this.height,
      fps: fps ?? this.fps,
      bitrate: bitrate ?? this.bitrate,
      enableHdr: enableHdr ?? this.enableHdr,
      videoCodec: videoCodec ?? this.videoCodec,
      scaleMode: scaleMode ?? this.scaleMode,
      framePacing: framePacing ?? this.framePacing,
      fullRange: fullRange ?? this.fullRange,
      audioConfig: audioConfig ?? this.audioConfig,
      audioQuality: audioQuality ?? this.audioQuality,
      playLocalAudio: playLocalAudio ?? this.playLocalAudio,
      enableAudioFx: enableAudioFx ?? this.enableAudioFx,
      enableSops: enableSops ?? this.enableSops,
      mouseMode: mouseMode ?? this.mouseMode,
      mouseEmulation: mouseEmulation ?? this.mouseEmulation,
      gamepadMouseEmulation:
          gamepadMouseEmulation ?? this.gamepadMouseEmulation,
      mouseLocalCursor: mouseLocalCursor ?? this.mouseLocalCursor,
      multiTouchGestures: multiTouchGestures ?? this.multiTouchGestures,
      absoluteMouseMode: absoluteMouseMode ?? this.absoluteMouseMode,
      trackpadSensitivityX: trackpadSensitivityX ?? this.trackpadSensitivityX,
      trackpadSensitivityY: trackpadSensitivityY ?? this.trackpadSensitivityY,
      forceQwertyLayout: forceQwertyLayout ?? this.forceQwertyLayout,
      backButtonAsMeta: backButtonAsMeta ?? this.backButtonAsMeta,
      backButtonAsGuide: backButtonAsGuide ?? this.backButtonAsGuide,
      deadzone: deadzone ?? this.deadzone,
      flipFaceButtons: flipFaceButtons ?? this.flipFaceButtons,
      multiControllerEnabled:
          multiControllerEnabled ?? this.multiControllerEnabled,
      controllerCount: controllerCount ?? this.controllerCount,
      controllerDriver: controllerDriver ?? this.controllerDriver,
      usbDriverEnabled: usbDriverEnabled ?? this.usbDriverEnabled,
      usbBindAll: usbBindAll ?? this.usbBindAll,
      joyCon: joyCon ?? this.joyCon,
      gamepadBatteryReport: gamepadBatteryReport ?? this.gamepadBatteryReport,
      gamepadMotionSensors: gamepadMotionSensors ?? this.gamepadMotionSensors,
      gamepadMotionFallback:
          gamepadMotionFallback ?? this.gamepadMotionFallback,
      gamepadTouchpadAsMouse:
          gamepadTouchpadAsMouse ?? this.gamepadTouchpadAsMouse,
      buttonRemapProfile: buttonRemapProfile ?? this.buttonRemapProfile,
      customRemapTable: customRemapTable ?? this.customRemapTable,
      gamepadMouseSpeed: gamepadMouseSpeed ?? this.gamepadMouseSpeed,
      ultraLowLatency: ultraLowLatency ?? this.ultraLowLatency,
      lowLatencyFrameBalance:
          lowLatencyFrameBalance ?? this.lowLatencyFrameBalance,
      enableRumble: enableRumble ?? this.enableRumble,
      vibrateFallback: vibrateFallback ?? this.vibrateFallback,
      deviceRumble: deviceRumble ?? this.deviceRumble,
      vibrateFallbackStrength:
          vibrateFallbackStrength ?? this.vibrateFallbackStrength,
      showOnscreenControls: showOnscreenControls ?? this.showOnscreenControls,
      hideOscWithGamepad: hideOscWithGamepad ?? this.hideOscWithGamepad,
      oscOpacity: oscOpacity ?? this.oscOpacity,
      smartBitrateEnabled: smartBitrateEnabled ?? this.smartBitrateEnabled,
      smartBitrateMin: smartBitrateMin ?? this.smartBitrateMin,
      smartBitrateMax: smartBitrateMax ?? this.smartBitrateMax,
      enablePerfOverlay: enablePerfOverlay ?? this.enablePerfOverlay,
      pipEnabled: pipEnabled ?? this.pipEnabled,
      enableSessionMetrics: enableSessionMetrics ?? this.enableSessionMetrics,
      dynamicBitrateEnabled:
          dynamicBitrateEnabled ?? this.dynamicBitrateEnabled,
      dynamicBitrateSensitivity:
          dynamicBitrateSensitivity ?? this.dynamicBitrateSensitivity,
      hapticOverlay: hapticOverlay ?? this.hapticOverlay,
      streamNotification: streamNotification ?? this.streamNotification,
      screenshotEnabled: screenshotEnabled ?? this.screenshotEnabled,
      screenshotCombo: screenshotCombo ?? this.screenshotCombo,
      screenshotHoldMs: screenshotHoldMs ?? this.screenshotHoldMs,
      overlayTriggerCombo: overlayTriggerCombo ?? this.overlayTriggerCombo,
      overlayTriggerHoldMs: overlayTriggerHoldMs ?? this.overlayTriggerHoldMs,
      desktopOverlayKeys: desktopOverlayKeys ?? this.desktopOverlayKeys,
      desktopOverlayHoldMs: desktopOverlayHoldMs ?? this.desktopOverlayHoldMs,
      panicCombo: panicCombo ?? this.panicCombo,
      panicHoldMs: panicHoldMs ?? this.panicHoldMs,
      mouseModeCombo: mouseModeCombo ?? this.mouseModeCombo,
      mouseModeHoldMs: mouseModeHoldMs ?? this.mouseModeHoldMs,
      frameQueueDepth: frameQueueDepth ?? this.frameQueueDepth,
      choreographerVsync: choreographerVsync ?? this.choreographerVsync,
      enableVrr: enableVrr ?? this.enableVrr,
      enableDirectSubmit: enableDirectSubmit ?? this.enableDirectSubmit,
      hostPresetOverrideEnabled:
          hostPresetOverrideEnabled ?? this.hostPresetOverrideEnabled,
      hostPresetOverrideId: hostPresetOverrideId ?? this.hostPresetOverrideId,
    );
  }

  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    'fps': fps,
    'bitrate': bitrate,
    'enableHdr': enableHdr,
    'videoCodec': videoCodec.index,
    'scaleMode': scaleMode.index,
    'framePacing': framePacing.index,
    'fullRange': fullRange,
    'audioConfig': audioConfig.index,
    'audioQuality': audioQuality.index,
    'playLocalAudio': playLocalAudio,
    'enableAudioFx': enableAudioFx,
    'enableSops': enableSops,
    'mouseMode': mouseMode.index,
    'mouseEmulation': mouseEmulation,
    'gamepadMouseEmulation': gamepadMouseEmulation,
    'mouseLocalCursor': mouseLocalCursor,
    'multiTouchGestures': multiTouchGestures,
    'absoluteMouseMode': absoluteMouseMode,
    'trackpadSensitivityX': trackpadSensitivityX,
    'trackpadSensitivityY': trackpadSensitivityY,
    'forceQwertyLayout': forceQwertyLayout,
    'backButtonAsMeta': backButtonAsMeta,
    'backButtonAsGuide': backButtonAsGuide,
    'deadzone': deadzone,
    'flipFaceButtons': flipFaceButtons,
    'multiControllerEnabled': multiControllerEnabled,
    'controllerCount': controllerCount,
    'controllerDriver': controllerDriver.index,
    'usbDriverEnabled': usbDriverEnabled,
    'usbBindAll': usbBindAll,
    'joyCon': joyCon,
    'gamepadBatteryReport': gamepadBatteryReport,
    'gamepadMotionSensors': gamepadMotionSensors,
    'gamepadMotionFallback': gamepadMotionFallback,
    'gamepadTouchpadAsMouse': gamepadTouchpadAsMouse,
    'buttonRemapProfile': buttonRemapProfile.index,
    'customRemapTable': customRemapTable.map(
      (k, v) => MapEntry(k.toString(), v),
    ),
    'gamepadMouseSpeed': gamepadMouseSpeed,
    'ultraLowLatency': ultraLowLatency,
    'lowLatencyFrameBalance': lowLatencyFrameBalance,
    'enableRumble': enableRumble,
    'vibrateFallback': vibrateFallback,
    'deviceRumble': deviceRumble,
    'vibrateFallbackStrength': vibrateFallbackStrength,
    'showOnscreenControls': showOnscreenControls,
    'hideOscWithGamepad': hideOscWithGamepad,
    'oscOpacity': oscOpacity,
    'smartBitrateEnabled': smartBitrateEnabled,
    'smartBitrateMin': smartBitrateMin,
    'smartBitrateMax': smartBitrateMax,
    'enablePerfOverlay': enablePerfOverlay,
    'pipEnabled': pipEnabled,
    'enableSessionMetrics': enableSessionMetrics,
    'dynamicBitrateEnabled': dynamicBitrateEnabled,
    'dynamicBitrateSensitivity': dynamicBitrateSensitivity,
    'hapticOverlay': hapticOverlay,
    'streamNotification': streamNotification,
    'screenshotEnabled': screenshotEnabled,
    'screenshotCombo': screenshotCombo,
    'screenshotHoldMs': screenshotHoldMs,
    'overlayTriggerCombo': overlayTriggerCombo,
    'overlayTriggerHoldMs': overlayTriggerHoldMs,
    'desktopOverlayKeys': desktopOverlayKeys,
    'desktopOverlayHoldMs': desktopOverlayHoldMs,
    'panicCombo': panicCombo,
    'panicHoldMs': panicHoldMs,
    'mouseModeCombo': mouseModeCombo,
    'mouseModeHoldMs': mouseModeHoldMs,
    'frameQueueDepth': frameQueueDepth,
    'choreographerVsync': choreographerVsync,
    'enableVrr': enableVrr,
    'enableDirectSubmit': enableDirectSubmit,
    'hostPresetOverrideEnabled': hostPresetOverrideEnabled,
    'hostPresetOverrideId': hostPresetOverrideId,
  };

  factory StreamConfiguration.fromJson(Map<String, dynamic> json) {
    return StreamConfiguration(
      width: json['width'] ?? 1920,
      height: json['height'] ?? 1080,
      fps: json['fps'] ?? 60,
      bitrate: json['bitrate'] ?? 20000,
      enableHdr: json['enableHdr'] ?? false,
      videoCodec:
          VideoCodec.values[(json['videoCodec'] ?? VideoCodec.auto.index).clamp(
            0,
            VideoCodec.values.length - 1,
          )],
      scaleMode: VideoScaleMode.values[json['scaleMode'] ?? 0],
      framePacing:
          FramePacing.values[json['framePacing'] ?? FramePacing.adaptive.index],
      fullRange: json['fullRange'] ?? false,
      audioConfig: AudioConfig.values[json['audioConfig'] ?? 0],
      audioQuality:
          AudioQuality.values[(json['audioQuality'] ?? 0).clamp(
            0,
            AudioQuality.values.length - 1,
          )],
      playLocalAudio: json['playLocalAudio'] ?? false,
      enableAudioFx: json['enableAudioFx'] ?? false,
      enableSops: json['enableSops'] ?? true,
      // On desktop platforms (macOS, Windows), default to trackpad (relative)
      // mode so the server hides its cursor. On mobile, default to directTouch.
      mouseMode:
          MouseMode.values[json['mouseMode'] ??
              ((Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                  ? MouseMode.trackpad.index
                  : MouseMode.directTouch.index)],
      mouseEmulation: json['mouseEmulation'] ?? true,
      gamepadMouseEmulation: json['gamepadMouseEmulation'] ?? true,
      mouseLocalCursor: json['mouseLocalCursor'] ?? false,
      multiTouchGestures: json['multiTouchGestures'] ?? true,
      absoluteMouseMode: json['absoluteMouseMode'] ?? false,
      trackpadSensitivityX: json['trackpadSensitivityX'] ?? 100,
      trackpadSensitivityY: json['trackpadSensitivityY'] ?? 100,
      forceQwertyLayout: json['forceQwertyLayout'] ?? true,
      backButtonAsMeta: json['backButtonAsMeta'] ?? false,
      backButtonAsGuide: json['backButtonAsGuide'] ?? false,
      deadzone: json['deadzone'] ?? 5,
      flipFaceButtons: json['flipFaceButtons'] ?? false,
      multiControllerEnabled: json['multiControllerEnabled'] ?? true,
      controllerCount: json['controllerCount'] ?? 0,
      controllerDriver: ControllerDriver.values[json['controllerDriver'] ?? 0],
      usbDriverEnabled: json['usbDriverEnabled'] ?? true,
      usbBindAll: json['usbBindAll'] ?? false,
      joyCon: json['joyCon'] ?? false,
      gamepadBatteryReport: json['gamepadBatteryReport'] ?? true,
      gamepadMotionSensors: json['gamepadMotionSensors'] ?? true,
      gamepadMotionFallback: json['gamepadMotionFallback'] ?? false,
      gamepadTouchpadAsMouse: json['gamepadTouchpadAsMouse'] ?? false,
      buttonRemapProfile:
          ButtonRemapProfile.values[(json['buttonRemapProfile'] ?? 0).clamp(
            0,
            ButtonRemapProfile.values.length - 1,
          )],
      customRemapTable: _parseRemapTable(json['customRemapTable']),
      gamepadMouseSpeed:
          (json['gamepadMouseSpeed'] as num?)?.toDouble() ?? 1.75,
      ultraLowLatency: json['ultraLowLatency'] ?? false,
      lowLatencyFrameBalance: json['lowLatencyFrameBalance'] ?? false,
      enableRumble: json['enableRumble'] ?? true,
      vibrateFallback: json['vibrateFallback'] ?? true,
      deviceRumble: json['deviceRumble'] ?? false,
      vibrateFallbackStrength: json['vibrateFallbackStrength'] ?? 100,
      showOnscreenControls: json['showOnscreenControls'] ?? false,
      hideOscWithGamepad: json['hideOscWithGamepad'] ?? true,
      oscOpacity: json['oscOpacity'] ?? 90,
      smartBitrateEnabled: json['smartBitrateEnabled'] ?? false,
      smartBitrateMin: json['smartBitrateMin'] ?? 10000,
      smartBitrateMax: json['smartBitrateMax'] ?? 35000,
      enablePerfOverlay: json['enablePerfOverlay'] ?? false,
      pipEnabled: json['pipEnabled'] ?? false,
      enableSessionMetrics: json['enableSessionMetrics'] ?? true,
      dynamicBitrateEnabled: json['dynamicBitrateEnabled'] ?? false,
      dynamicBitrateSensitivity: json['dynamicBitrateSensitivity'] ?? 2,
      hapticOverlay: json['hapticOverlay'] ?? true,
      streamNotification: json['streamNotification'] ?? true,
      screenshotEnabled: json['screenshotEnabled'] ?? true,
      // Default: RB (0x0200) + START (0x0020) = 0x0220
      screenshotCombo: json['screenshotCombo'] ?? 0x0220,
      screenshotHoldMs: json['screenshotHoldMs'] ?? 2500,
      overlayTriggerCombo: json['overlayTriggerCombo'] ?? 0x00C0,
      overlayTriggerHoldMs: json['overlayTriggerHoldMs'] ?? 2000,
      desktopOverlayKeys: (json['desktopOverlayKeys'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['Shift', '-'],
      desktopOverlayHoldMs: json['desktopOverlayHoldMs'] ?? 0,
      panicCombo: json['panicCombo'] ?? 0,
      panicHoldMs: json['panicHoldMs'] ?? 2000,
      mouseModeCombo: json['mouseModeCombo'] ?? 0x0020,
      mouseModeHoldMs: json['mouseModeHoldMs'] ?? 2000,
      frameQueueDepth: json['frameQueueDepth'] ?? 0,
      choreographerVsync: json['choreographerVsync'] ?? false,
      enableVrr: json['enableVrr'] ?? false,
      enableDirectSubmit: json['enableDirectSubmit'] ?? false,
      hostPresetOverrideEnabled: json['hostPresetOverrideEnabled'] ?? false,
      hostPresetOverrideId: json['hostPresetOverrideId'] ?? '',
    );
  }

  static Map<int, int> _parseRemapTable(dynamic raw) {
    if (raw is! Map) return {};
    final out = <int, int>{};
    for (final e in raw.entries) {
      final k = int.tryParse(e.key.toString());
      final v = e.value is int
          ? e.value as int
          : int.tryParse(e.value.toString());
      if (k != null && v != null) out[k] = v;
    }
    return out;
  }
}

enum VideoCodec { h264, h265, av1, auto }

enum AudioConfig { stereo, surround51, surround71 }

enum VideoScaleMode { fit, fill, stretch }

enum FramePacing { latency, balanced, capFps, smoothness, adaptive }

enum MouseMode { directTouch, trackpad, mouse }

enum ControllerDriver { auto, xbox360, dualshock, dualsense }

enum ButtonRemapProfile { none, nintendo, southpaw, custom }

enum AudioQuality { high, normal }
