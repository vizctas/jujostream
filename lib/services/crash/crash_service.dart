import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CrashService {
  CrashService._();

  static const _kLogFileName = 'jujo_crash.log';
  static File? _logFile;

  static FlutterExceptionHandler? _prevFlutterError;

  static Future<void> initialize({
    void Function(String report)? onCrashDetected,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/$_kLogFileName');

      if (onCrashDetected != null && await _logFile!.exists()) {
        final report = await _logFile!.readAsString();
        if (report.isNotEmpty) {
          onCrashDetected(report);
        }
      }
    } catch (_) {

      return;
    }

    _prevFlutterError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _writeCrashLog(
        'FlutterError',
        details.exceptionAsString(),
        details.stack?.toString(),
      );

      _prevFlutterError?.call(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      _writeCrashLog('UnhandledError', error.toString(), stack.toString());
      return false;
    };
  }

  static Future<void> clearCrashLog() async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        await _logFile!.delete();
      }
    } catch (_) {}
  }

  static void _writeCrashLog(String type, String error, String? stack) {
    if (_logFile == null) return;
    try {
      final ts = DateTime.now().toIso8601String();
      final content = '[$type] $ts\n$error\n\n${stack ?? ''}\n';
      _logFile!.writeAsStringSync(content, mode: FileMode.writeOnly, flush: true);
    } catch (_) {}
  }
}
