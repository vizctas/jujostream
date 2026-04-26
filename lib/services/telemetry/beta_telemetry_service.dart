import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class BetaTelemetryService {
  BetaTelemetryService._();

  static const _filePrefix = 'jujo_beta_';
  static const _sensitiveKeys = {
    'cert',
    'certificate',
    'key',
    'password',
    'rikey',
    'secret',
    'servercert',
    'token',
  };

  static File? _activeLogFile;
  static DateTime Function() _now = DateTime.now;
  static DebugPrintCallback? _previousDebugPrint;
  static FlutterExceptionHandler? _previousFlutterError;
  static ErrorCallback? _previousPlatformError;
  static bool _initialized = false;
  static bool _debugPrintInstalled = false;
  static bool _globalHandlersInstalled = false;

  static File? get activeLogFile => _activeLogFile;

  static Future<void> initialize({
    Directory? logDirectory,
    DateTime Function()? now,
    int maxLogFiles = 8,
  }) async {
    _now = now ?? DateTime.now;
    final dir = logDirectory ?? await _defaultLogDirectory();
    await dir.create(recursive: true);

    final fileName = '$_filePrefix${_timestampForFile(_now())}.log';
    _activeLogFile = File('${dir.path}${Platform.pathSeparator}$fileName');
    await _activeLogFile!.writeAsString(
      '[session] ${_now().toIso8601String()} JujoStream beta telemetry\n',
      mode: FileMode.writeOnly,
      flush: true,
    );
    _initialized = true;
    await _rotateLogs(dir, maxLogFiles);
    event('telemetry_ready', {'path': _activeLogFile!.path});
  }

  static void installDebugPrintCapture() {
    if (_debugPrintInstalled) return;
    _previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.isNotEmpty) {
        logLine('debug', message);
      }
      _previousDebugPrint?.call(message, wrapWidth: wrapWidth);
    };
    _debugPrintInstalled = true;
  }

  static void installGlobalHandlers() {
    if (_globalHandlersInstalled) return;
    _previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      error('FlutterError', details.exception, details.stack);
      _previousFlutterError?.call(details);
    };

    _previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      BetaTelemetryService.error('UnhandledPlatformError', error, stack);
      final previous = _previousPlatformError;
      if (previous != null) {
        return previous(error, stack);
      }
      return true;
    };
    _globalHandlersInstalled = true;
  }

  static void event(String name, [Map<String, Object?> fields = const {}]) {
    final encoded = fields.entries
        .map((entry) => '${entry.key}=${_redact(entry.key, entry.value)}')
        .join(' ');
    logLine('event', encoded.isEmpty ? name : '$name $encoded');
  }

  static void error(String type, Object error, StackTrace? stack) {
    logLine('error', '$type ${_redact('error', error)}');
    if (stack != null) {
      logLine('stack', stack.toString());
    }
  }

  static void logLine(String level, String message) {
    if (!_initialized || _activeLogFile == null) return;
    final ts = _now().toIso8601String();
    final clean = _sanitizeMessage(message);
    try {
      _activeLogFile!.writeAsStringSync(
        '[$ts][$level] $clean\n',
        mode: FileMode.append,
        flush: false,
      );
    } catch (_) {}
  }

  static Future<void> resetForTest() async {
    if (_debugPrintInstalled && _previousDebugPrint != null) {
      debugPrint = _previousDebugPrint!;
    }
    if (_globalHandlersInstalled) {
      FlutterError.onError = _previousFlutterError;
      PlatformDispatcher.instance.onError = _previousPlatformError;
    }
    _activeLogFile = null;
    _previousDebugPrint = null;
    _previousFlutterError = null;
    _previousPlatformError = null;
    _initialized = false;
    _debugPrintInstalled = false;
    _globalHandlersInstalled = false;
    _now = DateTime.now;
  }

  static Future<Directory> _defaultLogDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}logs');
  }

  static Future<void> _rotateLogs(Directory dir, int maxLogFiles) async {
    final logs = await dir
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) => file.uri.pathSegments.last.startsWith(_filePrefix))
        .where((file) => file.uri.pathSegments.last.endsWith('.log'))
        .toList();
    logs.sort(
      (a, b) => a.uri.pathSegments.last.compareTo(b.uri.pathSegments.last),
    );
    final extra = logs.length - maxLogFiles;
    if (extra <= 0) return;
    for (final file in logs.take(extra)) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  static String _timestampForFile(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}_'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }

  static Object _redact(String key, Object? value) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final sensitive = _sensitiveKeys.any(normalized.contains);
    if (sensitive) return '<redacted>';
    return value ?? '<null>';
  }

  static String _sanitizeMessage(String message) {
    var out = message;
    out = out.replaceAllMapped(
      RegExp(
        r'\b(riKey|serverCert|token|password|secret)\s*[:=]\s*[^,\s}]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=<redacted>',
    );
    return out;
  }
}
