import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local, single-record connection diagnostics. Deliberately excludes host,
/// app, credentials and any identifier used to correlate separate attempts.
class ConnectionAttemptDiagnostic {
  const ConnectionAttemptDiagnostic({
    required this.startedAt,
    this.stage,
    this.stageName,
    this.stageState,
    this.errorCode,
    this.connectionStarted = false,
    this.outcome,
    this.framesReceived,
    this.framesRendered,
    this.framesPresented,
    this.presentationTrackingAvailable = false,
  });

  static const storageKey = 'last_connection_attempt_diagnostic_v1';

  final DateTime startedAt;
  final int? stage;
  final String? stageName;
  final String? stageState;
  final int? errorCode;
  final bool connectionStarted;
  final String? outcome;
  final int? framesReceived;
  final int? framesRendered;
  final int? framesPresented;
  final bool presentationTrackingAvailable;

  factory ConnectionAttemptDiagnostic.begin({DateTime? now}) =>
      ConnectionAttemptDiagnostic(startedAt: now ?? DateTime.now().toUtc());

  ConnectionAttemptDiagnostic applyEvent(
    Map<String, dynamic> event, {
    DateTime? now,
  }) {
    final type = event['type'];
    switch (type) {
      case 'stageStarting':
      case 'stageComplete':
      case 'stageFailed':
        final stageValue = event['stage'];
        final name = event['stageName'];
        return copyWith(
          stage: stageValue is num ? stageValue.toInt() : stage,
          stageName: name is String ? _safeStageName(name) : stageName,
          stageState: switch (type) {
            'stageStarting' => 'starting',
            'stageComplete' => 'complete',
            _ => 'failed',
          },
          errorCode: type == 'stageFailed' && event['errorCode'] is num
              ? (event['errorCode'] as num).toInt()
              : errorCode,
        );
      case 'connectionStarted':
        return copyWith(connectionStarted: true, stageState: 'connected');
      case 'connectionTerminated':
        final code = event['errorCode'];
        return copyWith(
          stageState: 'terminated',
          errorCode: code is num ? code.toInt() : errorCode,
        );
      default:
        final received = event['framesReceived'];
        final rendered = event['totalRendered'] ?? event['framesRendered'];
        final presented = event['totalPresented'] ?? event['framesPresented'];
        final tracking = event['presentationTrackingAvailable'];
        if (received is! num && rendered is! num && presented is! num) {
          return this;
        }
        return copyWith(
          framesReceived: received is num ? received.toInt() : framesReceived,
          framesRendered: rendered is num ? rendered.toInt() : framesRendered,
          framesPresented: presented is num
              ? presented.toInt()
              : framesPresented,
          presentationTrackingAvailable: tracking is bool
              ? tracking
              : presentationTrackingAvailable,
        );
    }
  }

  ConnectionAttemptDiagnostic copyWith({
    int? stage,
    String? stageName,
    String? stageState,
    int? errorCode,
    bool? connectionStarted,
    String? outcome,
    int? framesReceived,
    int? framesRendered,
    int? framesPresented,
    bool? presentationTrackingAvailable,
  }) => ConnectionAttemptDiagnostic(
    startedAt: startedAt,
    stage: stage ?? this.stage,
    stageName: stageName ?? this.stageName,
    stageState: stageState ?? this.stageState,
    errorCode: errorCode ?? this.errorCode,
    connectionStarted: connectionStarted ?? this.connectionStarted,
    outcome: outcome ?? this.outcome,
    framesReceived: framesReceived ?? this.framesReceived,
    framesRendered: framesRendered ?? this.framesRendered,
    framesPresented: framesPresented ?? this.framesPresented,
    presentationTrackingAvailable:
        presentationTrackingAvailable ?? this.presentationTrackingAvailable,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'startedAt': startedAt.toUtc().toIso8601String(),
    if (stage != null) 'stage': stage,
    if (stageName != null) 'stageName': stageName,
    if (stageState != null) 'stageState': stageState,
    if (errorCode != null) 'errorCode': errorCode,
    'connectionStarted': connectionStarted,
    if (outcome != null) 'outcome': outcome,
    if (framesReceived != null) 'framesReceived': framesReceived,
    if (framesRendered != null) 'framesRendered': framesRendered,
    if (framesPresented != null) 'framesPresented': framesPresented,
    'presentationTrackingAvailable': presentationTrackingAvailable,
  };

  factory ConnectionAttemptDiagnostic.fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['startedAt'] as String? ?? '');
    if (json['version'] != 1 || date == null) {
      throw const FormatException('Unsupported connection diagnostic');
    }
    int? integer(String key) => (json[key] as num?)?.toInt();
    return ConnectionAttemptDiagnostic(
      startedAt: date.toUtc(),
      stage: integer('stage'),
      stageName: json['stageName'] as String?,
      stageState: json['stageState'] as String?,
      errorCode: integer('errorCode'),
      connectionStarted: json['connectionStarted'] == true,
      outcome: json['outcome'] as String?,
      framesReceived: integer('framesReceived'),
      framesRendered: integer('framesRendered'),
      framesPresented: integer('framesPresented'),
      presentationTrackingAvailable:
          json['presentationTrackingAvailable'] == true,
    );
  }

  String format({required bool isSpanish}) {
    final lines = <String>[
      isSpanish ? 'Diagnóstico del intento' : 'Connection attempt diagnosis',
      if (stage != null || stageName != null)
        '${isSpanish ? 'Etapa' : 'Stage'}: ${stageName ?? '#$stage'}${stageState == null ? '' : ' ($stageState)'}',
      '${isSpanish ? 'Conexión nativa' : 'Native connection'}: ${connectionStarted ? (isSpanish ? 'iniciada' : 'started') : (isSpanish ? 'no confirmada' : 'not confirmed')}',
      if (errorCode != null) '${isSpanish ? 'Código' : 'Code'}: $errorCode',
      if (framesReceived != null)
        '${isSpanish ? 'Cuadros recibidos' : 'Frames received'}: $framesReceived',
      if (framesRendered != null)
        '${isSpanish ? 'Cuadros disponibles para renderizar' : 'Frames available/rendered'}: $framesRendered',
      if (presentationTrackingAvailable && framesPresented != null)
        '${isSpanish ? 'Presentaciones físicas observadas' : 'Physical presentations observed'}: $framesPresented'
      else
        (isSpanish
            ? 'Presentación física: no disponible en esta plataforma'
            : 'Physical presentation: unavailable on this platform'),
    ];
    return lines.join('\n');
  }

  static String _safeStageName(String value) {
    final normalized = value.replaceAll(RegExp(r'[\r\n\t]'), ' ').trim();
    return normalized.substring(0, normalized.length.clamp(0, 80));
  }
}

/// Persists only the most recent attempt, independently of played-session data.
class ConnectionAttemptDiagnosticStore {
  static const enabledKey = 'connection_attempt_diagnostics_enabled';

  /// Feature flag; OFF by default. When off nothing is captured or written.
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, value);
  }

  static Future<void> save(ConnectionAttemptDiagnostic diagnostic) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      ConnectionAttemptDiagnostic.storageKey,
      jsonEncode(diagnostic.toJson()),
    );
  }

  static Future<ConnectionAttemptDiagnostic?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(ConnectionAttemptDiagnostic.storageKey);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;
      return ConnectionAttemptDiagnostic.fromJson(decoded);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

typedef ConnectionAttemptWriter =
    Future<void> Function(ConnectionAttemptDiagnostic diagnostic);

/// Captures one attempt at a time and persists it only on stage transitions
/// and the final result (never per stats sample). At most one write is in
/// flight; while it runs only the latest pending record is kept. A generation
/// counter drops writes that belong to superseded attempts.
class ConnectionAttemptRecorder {
  ConnectionAttemptRecorder({
    required this.writer,
    this.enabled = false,
    void Function(Object error)? onWriteError,
  }) : _onWriteError = onWriteError;

  final ConnectionAttemptWriter writer;
  final void Function(Object error)? _onWriteError;
  bool enabled;

  int _generation = 0;
  bool _inFlight = false;
  ConnectionAttemptDiagnostic? _current;
  ({int generation, ConnectionAttemptDiagnostic record})? _pending;

  ConnectionAttemptDiagnostic? get current => _current;
  int get generation => _generation;

  static const _transitionEvents = {
    'stageStarting',
    'stageComplete',
    'stageFailed',
    'connectionStarted',
    'connectionTerminated',
  };

  void begin({DateTime? now}) {
    _generation++;
    _pending = null;
    if (!enabled) {
      _current = null;
      return;
    }
    _current = ConnectionAttemptDiagnostic.begin(now: now);
    _enqueue(_generation, _current!);
  }

  void record(Map<String, dynamic> event) {
    final current = _current;
    if (current == null) return;
    final updated = current.applyEvent(event);
    if (identical(updated, current)) return;
    _current = updated;
    if (_transitionEvents.contains(event['type'])) {
      _enqueue(_generation, updated);
    }
  }

  /// Finalizes the current attempt as failed (any startup exception/abort).
  void finishFailed() {
    final current = _current;
    if (current == null) return;
    _current = current.copyWith(outcome: 'failed');
    _enqueue(_generation, _current!);
  }

  void _enqueue(int generation, ConnectionAttemptDiagnostic record) {
    if (!enabled || generation != _generation) return;
    if (_inFlight) {
      _pending = (generation: generation, record: record);
      return;
    }
    _inFlight = true;
    _drain(generation, record);
  }

  Future<void> _drain(int generation, ConnectionAttemptDiagnostic first) async {
    var gen = generation;
    ConnectionAttemptDiagnostic? record = first;
    while (record != null) {
      if (gen == _generation) {
        try {
          await writer(record);
        } catch (error) {
          _onWriteError?.call(error);
        }
      }
      final next = _pending;
      _pending = null;
      gen = next?.generation ?? 0;
      record = next?.record;
    }
    _inFlight = false;
  }
}
