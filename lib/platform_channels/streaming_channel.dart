import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

import '../models/stream_configuration.dart';

class StreamingPlatformChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.limelight.jujostream/streaming',
  );

  static const EventChannel _statsChannel = EventChannel(
    'com.limelight.jujostream/streaming_stats',
  );

  static final Logger _log = Logger();
  static String? _lastStartStreamError;
  static int? _lastStartStreamErrorCode;

  static String? get lastStartStreamError => _lastStartStreamError;
  // Numeric GS_ status code from nativeStartConnection (0=ok, 104=GS_WRONG_STATE, etc.)
  static int? get lastStartStreamErrorCode => _lastStartStreamErrorCode;

  static Future<bool> startStream({
    required String host,
    required int httpsPort,
    required String appId,
    required int width,
    required int height,
    required int fps,
    required int bitrate,
    required String videoCodec,
    required bool enableHdr,
    required bool fullRange,
    required FramePacing framePacing,
    required String audioConfig,
    required AudioQuality audioQuality,
    bool enableAudioFx = false,
    required String serverCert,
    required String riKey,
    required int riKeyId,
    String? rtspSessionUrl,
    required String appVersion,
    required String gfeVersion,
    required int serverCodecModeSupport,
    int frameQueueDepth = 0,
    bool choreographerVsync = false,
    bool enableVrr = false,
    bool directSubmit = false,
    bool lowLatencyFrameBalance = false,
  }) async {
    try {
      _lastStartStreamError = null;
      _lastStartStreamErrorCode = null;
      final result = await _channel.invokeMethod<bool>('startStream', {
        'host': host,
        'httpsPort': httpsPort,
        'appId': appId,
        'width': width,
        'height': height,
        'fps': fps,
        'bitrate': bitrate,
        'videoCodec': videoCodec,
        'enableHdr': enableHdr,
        'fullRange': fullRange,
        'framePacing': framePacing.name,
        'audioConfig': audioConfig,
        'audioQuality': audioQuality == AudioQuality.high ? 'high' : 'normal',
        'enableAudioFx': enableAudioFx,
        'serverCert': serverCert,
        'riKey': riKey,
        'riKeyId': riKeyId,
        'rtspSessionUrl': rtspSessionUrl,
        'appVersion': appVersion,
        'gfeVersion': gfeVersion,
        'serverCodecModeSupport': serverCodecModeSupport,
        'frameQueueDepth': frameQueueDepth,
        'choreographerVsync': choreographerVsync,
        'enableVrr': enableVrr,
        'directSubmit': directSubmit,
        'lowLatencyFrameBalance': lowLatencyFrameBalance,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      _lastStartStreamError =
          '${e.code}${e.message != null ? ': ${e.message}' : ''}';
      // extract numeric GS_ code from the error details or message
      _lastStartStreamErrorCode = e.details is int
          ? e.details as int
          : _parseErrorCode(e.message);
      _log.e(
        'Failed to start stream: $_lastStartStreamError (code=$_lastStartStreamErrorCode)',
      );
      return false;
    }
  }

  static int? _parseErrorCode(String? message) {
    if (message == null) return null;
    final m = RegExp(r'code\s+(\d+)').firstMatch(message);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  static Future<Map<String, dynamic>> probeCodec({
    int width = 1920,
    int height = 1080,
    int fps = 60,
    bool hdr = false,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('probeCodec', {
        'width': width,
        'height': height,
        'fps': fps,
        'hdr': hdr,
      });
      return Map<String, dynamic>.from(result ?? {});
    } on PlatformException catch (e) {
      _log.e('Codec probe failed: ${e.message}');
      return {'bestCodec': 'H264', 'rankings': []};
    }
  }

  static Future<void> stopStream() async {
    try {
      await _channel.invokeMethod('stopStream');
    } on PlatformException catch (e) {
      _log.e('Failed to stop stream: ${e.message}');
    }
  }

  static Future<bool> enterPiP() async {
    try {
      final result = await _channel.invokeMethod<bool>('enterPiP');
      return result ?? false;
    } on PlatformException catch (e) {
      _log.e('Failed to enter PiP: ${e.message}');
      return false;
    } catch (e) {
      // Platform channel is not implemented on macOS yet.
      // Ignore MissingPluginException to prevent crashes.
      return false;
    }
  }

  static void sendGamepadInput({
    required int buttonFlags,
    required int leftTrigger,
    required int rightTrigger,
    required int leftStickX,
    required int leftStickY,
    required int rightStickX,
    required int rightStickY,
    int controllerNumber = 0,
    int activeGamepadMask = 1,
  }) {
    _channel
        .invokeMethod('sendGamepadInput', {
          'buttonFlags': buttonFlags,
          'leftTrigger': leftTrigger,
          'rightTrigger': rightTrigger,
          'leftStickX': leftStickX,
          'leftStickY': leftStickY,
          'rightStickX': rightStickX,
          'rightStickY': rightStickY,
          'controllerNumber': controllerNumber,
          'activeGamepadMask': activeGamepadMask,
        })
        .catchError((e) {
          _log.e('Failed to send gamepad input: $e');
        });
  }

  static Future<bool> sendControllerArrival({
    required int controllerNumber,
    required int activeGamepadMask,
    required int controllerType,
    int capabilities = 0,
    int supportedButtonFlags = 0,
  }) async {
    try {
      final result = await _channel
          .invokeMethod<bool>('sendControllerArrival', {
            'controllerNumber': controllerNumber,
            'activeGamepadMask': activeGamepadMask,
            'controllerType': controllerType,
            'capabilities': capabilities,
            'supportedButtonFlags': supportedButtonFlags,
          });
      return result ?? false;
    } on PlatformException catch (e) {
      _log.e('Failed to send controller arrival: ${e.message}');
      return false;
    }
  }

  static void sendMousePosition(int x, int y, int refWidth, int refHeight) {
    _channel
        .invokeMethod('sendMousePosition', {
          'x': x,
          'y': y,
          'refWidth': refWidth,
          'refHeight': refHeight,
        })
        .catchError((e) {
          _log.e('Failed to send mouse position: $e');
        });
  }

  static void sendMouseMove(int deltaX, int deltaY) {
    _channel
        .invokeMethod('sendMouseMove', {'deltaX': deltaX, 'deltaY': deltaY})
        .catchError((e) {
          _log.e('Failed to send mouse move: $e');
        });
  }

  static void sendMouseButton(int button, bool pressed) {
    _channel
        .invokeMethod('sendMouseButton', {'button': button, 'pressed': pressed})
        .catchError((e) {
          _log.e('Failed to send mouse button: $e');
        });
  }

  static void sendKeyboardInput(int keyCode, bool pressed) {
    _channel
        .invokeMethod('sendKeyboardInput', {
          'keyCode': keyCode,
          'pressed': pressed,
        })
        .catchError((e) {
          _log.e('Failed to send keyboard input: $e');
        });
  }

  static void sendUtf8Text(String text) {
    _channel.invokeMethod('sendUtf8Text', {'text': text}).catchError((e) {
      _log.e('Failed to send utf8 text: $e');
    });
  }

  static void sendScroll(int scrollAmount) {
    _channel
        .invokeMethod('sendScroll', {'scrollAmount': scrollAmount})
        .catchError((e) {
          _log.e('Failed to send scroll: $e');
        });
  }

  static void sendHighResHScroll(int scrollAmount) {
    _channel
        .invokeMethod('sendHighResHScroll', {'scrollAmount': scrollAmount})
        .catchError((e) {
          _log.e('Failed to send h-scroll: $e');
        });
  }

  static void sendTouchEvent({
    required int eventType,
    required int pointerId,
    required double x,
    required double y,
    double pressure = 1.0,
    double contactMajor = 0.0,
    double contactMinor = 0.0,
    int orientation = 0,
    required double refWidth,
    required double refHeight,
  }) {
    // Normalizing absolute pixels against stream reference size
    // Note: The native JNI expects normalized coords or absolute based on moonlight
    // For Moonlight Android absolute Touch screen it sends absolute view pixels.
    // So we just send absolute relative pixels (scaled up/down based on reference dimensions)
    _channel
        .invokeMethod('sendTouchEvent', {
          'eventType': eventType,
          'pointerId': pointerId,
          'x': x,
          'y': y,
          'pressure': pressure,
          'contactMajor': contactMajor,
          'contactMinor': contactMinor,
          'orientation': orientation,
        })
        .catchError((e) {
          _log.e('Failed to send touch event: $e');
        });
  }

  static Future<int?> getTextureId() async {
    try {
      return await _channel.invokeMethod<int>('getTextureId');
    } on PlatformException catch (e) {
      _log.e('Failed to get texture ID: ${e.message}');
      return null;
    }
  }

  static Future<bool> isDirectSubmitActive() async {
    try {
      final result = await _channel.invokeMethod<bool>('isDirectSubmitActive');
      return result ?? false;
    } on PlatformException catch (e) {
      _log.e('Failed to get render path: ${e.message}');
      return false;
    }
  }

  static Stream<Map<String, dynamic>> get statsStream {
    return _statsChannel.receiveBroadcastStream().map((event) {
      return Map<String, dynamic>.from(event as Map);
    });
  }
}
