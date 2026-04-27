import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/services/telemetry/beta_telemetry_service.dart';

void main() {
  group('BetaTelemetryService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('jujo_telemetry_test_');
    });

    tearDown(() async {
      await BetaTelemetryService.resetForTest();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('writes redacted event lines to the active log file', () async {
      await BetaTelemetryService.initialize(
        logDirectory: tempDir,
        now: () => DateTime.utc(2026, 4, 25, 12, 0),
      );

      BetaTelemetryService.event('stream_start', {
        'host': '192.168.1.50',
        'riKey': '00112233445566778899',
        'serverCert': 'abcdef',
      });

      final log = await BetaTelemetryService.activeLogFile!.readAsString();
      expect(log, contains('[event] stream_start'));
      expect(log, contains('host=192.168.1.50'));
      expect(log, contains('riKey=<redacted>'));
      expect(log, contains('serverCert=<redacted>'));
      expect(log, isNot(contains('00112233445566778899')));
      expect(log, isNot(contains('abcdef')));
    });

    test('rotates old session logs and keeps the newest files', () async {
      for (var i = 0; i < 8; i++) {
        await File(
          '${tempDir.path}/jujo_beta_20260425_120$i.log',
        ).writeAsString('old-$i');
      }

      await BetaTelemetryService.initialize(
        logDirectory: tempDir,
        maxLogFiles: 5,
        now: () => DateTime.utc(2026, 4, 25, 13, 0),
      );

      final logs = await tempDir
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .where((file) => file.path.endsWith('.log'))
          .toList();

      expect(logs.length, 5);
      expect(
        logs.map((file) => file.uri.pathSegments.last),
        contains('jujo_beta_20260425_130000.log'),
      );
    });
  });
}
