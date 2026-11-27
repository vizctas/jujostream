import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jujostream/services/stream/connection_attempt_diagnostic.dart';

void main() {
  final startedAt = DateTime.utc(2026, 11, 25, 12, 30);

  test('records bridge negotiation signals and startup failure', () {
    var diagnostic = ConnectionAttemptDiagnostic.begin(now: startedAt);
    diagnostic = diagnostic.applyEvent({
      'type': 'stageStarting',
      'stage': 3,
      'stageName': 'RTSP handshake',
    });
    diagnostic = diagnostic.applyEvent({
      'type': 'stageFailed',
      'stage': 3,
      'errorCode': 503,
    });

    expect(diagnostic.stage, 3);
    expect(diagnostic.stageName, 'RTSP handshake');
    expect(diagnostic.stageState, 'failed');
    expect(diagnostic.errorCode, 503);
    expect(diagnostic.connectionStarted, isFalse);
  });

  test('tracks received frames separately from physical presentation', () {
    var diagnostic = ConnectionAttemptDiagnostic.begin(now: startedAt);
    diagnostic = diagnostic.applyEvent({'type': 'connectionStarted'});
    diagnostic = diagnostic.applyEvent({
      'framesReceived': 120,
      'totalRendered': 80,
      'totalPresented': 0,
      'presentationTrackingAvailable': false,
    });

    final report = diagnostic.format(isSpanish: true);
    expect(diagnostic.connectionStarted, isTrue);
    expect(diagnostic.framesReceived, 120);
    expect(diagnostic.framesRendered, 80);
    expect(diagnostic.framesPresented, 0);
    expect(report, contains('Cuadros recibidos: 120'));
    expect(report, contains('Presentación física: no disponible'));
    expect(report, isNot(contains('Presentaciones físicas observadas')));
  });

  test(
    'persists one private-data-free last attempt, not session history',
    () async {
      final diagnostic = ConnectionAttemptDiagnostic.begin(
        now: startedAt,
      ).applyEvent({'type': 'stageStarting', 'stage': 2, 'stageName': 'TLS'});
      final json = jsonEncode(diagnostic.toJson());
      expect(json, isNot(contains('host')));
      expect(json, isNot(contains('appId')));

      final restored = ConnectionAttemptDiagnostic.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      expect(restored.startedAt, startedAt);
      expect(restored.stage, 2);
      expect(restored.stageName, 'TLS');
      expect(restored.toJson().keys, isNot(contains('host')));

      SharedPreferences.setMockInitialValues({});
      await ConnectionAttemptDiagnosticStore.save(diagnostic);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {ConnectionAttemptDiagnostic.storageKey});
      expect((await ConnectionAttemptDiagnosticStore.load())?.stage, 2);
    },
  );

  test(
    'formats localized stage and error detail, sanitizing bridge labels',
    () {
      final diagnostic = ConnectionAttemptDiagnostic.begin(now: startedAt)
          .applyEvent({
            'type': 'stageFailed',
            'stage': 4,
            'stageName': 'Video setup\nInjected line',
            'errorCode': 7,
          });

      final english = diagnostic.format(isSpanish: false);
      final spanish = diagnostic.format(isSpanish: true);
      expect(english, contains('Stage: Video setup Injected line (failed)'));
      expect(english, contains('Code: 7'));
      expect(english, contains('Physical presentation: unavailable'));
      expect(spanish, contains('Etapa: Video setup Injected line (failed)'));
      expect(spanish, contains('Código: 7'));
      expect(english, isNot(contains('\nInjected')));
    },
  );
  group('ConnectionAttemptRecorder', () {
    late List<ConnectionAttemptDiagnostic> writes;
    late List<Completer<void>> gates;
    ConnectionAttemptRecorder make({required bool enabled, bool gated = false}) {
      writes = [];
      gates = [];
      return ConnectionAttemptRecorder(
        enabled: enabled,
        writer: (d) {
          writes.add(d);
          if (!gated) return Future.value();
          final c = Completer<void>();
          gates.add(c);
          return c.future;
        },
      );
    }

    test('flag off => zero writes', () async {
      final r = make(enabled: false);
      r.begin(now: startedAt);
      r.record({'type': 'stageStarting', 'stage': 1});
      r.record({'framesReceived': 5});
      r.finishFailed();
      await Future<void>.delayed(Duration.zero);
      expect(writes, isEmpty);
      expect(r.current, isNull);
    });

    test('stats samples do not persist; N samples => <=2 writes', () async {
      final r = make(enabled: true, gated: true);
      r.begin(now: startedAt);
      for (var i = 1; i <= 100; i++) {
        r.record({'framesReceived': i});
      }
      expect(writes.length, 1);
      r.record({'type': 'stageStarting', 'stage': 2});
      r.record({'type': 'stageComplete', 'stage': 2});
      r.record({'type': 'connectionStarted'});
      gates.first.complete();
      await Future<void>.delayed(Duration.zero);
      gates.last.complete();
      await Future<void>.delayed(Duration.zero);
      expect(writes.length, 2);
      expect(writes.last.connectionStarted, isTrue);
      expect(writes.last.framesReceived, 100);
    });

    test('old generation write is discarded', () async {
      final r = make(enabled: true, gated: true);
      r.begin(now: startedAt);
      r.record({'type': 'stageStarting', 'stage': 1});
      r.begin(now: startedAt);
      gates.first.complete();
      await Future<void>.delayed(Duration.zero);
      // stale pending (gen 1) dropped; only the new attempt's begin is written
      expect(writes.length, 2);
      expect(writes.last.stage, isNull);
      gates.last.complete();
      await Future<void>.delayed(Duration.zero);
      expect(writes.length, 2);
    });

    test('startup failure finalizes the record as failed', () async {
      final r = make(enabled: true);
      r.begin(now: startedAt);
      await Future<void>.delayed(Duration.zero);
      r.finishFailed();
      await Future<void>.delayed(Duration.zero);
      expect(writes.last.outcome, 'failed');
      expect(ConnectionAttemptDiagnostic.fromJson(writes.last.toJson()).outcome,
          'failed');
    });

    test('flag defaults to false', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await ConnectionAttemptDiagnosticStore.isEnabled(), isFalse);
    });
  });
}
