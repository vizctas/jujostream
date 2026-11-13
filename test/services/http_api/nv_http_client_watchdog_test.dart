import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jujostream/services/http_api/nv_http_client.dart';

void main() {
  test(
    'parseServerInfo parses Watchdog tags and keeps defaults when absent',
    () {
      final client = NvHttpClient();

      final enabled = client.parseServerInfo('''
        <root status_code="200">
          <hostname>HostPC</hostname>
          <uniqueid>uuid-1</uniqueid>
          <WatchdogSupported>1</WatchdogSupported>
          <WatchdogEnabled>0</WatchdogEnabled>
        </root>
      ''', '192.168.1.10', 47989);
      expect(enabled.watchdogSupported, isTrue);
      expect(enabled.watchdogEnabled, isFalse);

      final legacy = client.parseServerInfo('''
        <root status_code="200">
          <hostname>LegacyPC</hostname>
          <uniqueid>uuid-2</uniqueid>
        </root>
      ''', '192.168.1.10', 47989);
      expect(legacy.watchdogSupported, isFalse);
      expect(legacy.watchdogEnabled, isTrue);
    },
  );

  test(
    'resumeApp marks sessionClosedOnHost on 410 GameClosed or legacy no running app',
    () async {
      final deadMock = MockClient((request) async {
        expect(request.url.path, '/resume');
        return http.Response(
          '<root status_code="410" status_message="The game was closed on the host">'
          '<resume>0</resume><GameClosed>1</GameClosed></root>',
          200,
        );
      });
      final deadClient = NvHttpClient(httpsClientFactory: (_) => deadMock);
      final deadRes = await deadClient.resumeApp(
        '192.168.1.10',
        42,
        width: 1920,
        height: 1080,
      );
      expect(deadRes.success, isFalse);
      expect(deadRes.sessionClosedOnHost, isTrue);

      final legacyDeadMock = MockClient((_) async {
        return http.Response(
          '<root status_code="400" status_message="No running app to resume">'
          '<resume>0</resume></root>',
          200,
        );
      });
      final legacyDeadClient = NvHttpClient(
        httpsClientFactory: (_) => legacyDeadMock,
      );
      final legacyRes = await legacyDeadClient.resumeApp(
        '192.168.1.10',
        42,
        width: 1920,
        height: 1080,
      );
      expect(legacyRes.success, isFalse);
      expect(legacyRes.sessionClosedOnHost, isTrue);

      final genericFailMock = MockClient((_) async {
        return http.Response(
          '<root status_code="500" status_message="Internal error"></root>',
          200,
        );
      });
      final genericClient = NvHttpClient(
        httpsClientFactory: (_) => genericFailMock,
      );
      final genericRes = await genericClient.resumeApp(
        '192.168.1.10',
        42,
        width: 1920,
        height: 1080,
      );
      expect(genericRes.success, isFalse);
      expect(genericRes.sessionClosedOnHost, isFalse);
    },
  );

  test('fetchWatchdogStatus parses status and fails open on errors', () async {
    final okMock = MockClient((request) async {
      expect(request.url.path, '/watchdog-status');
      return http.Response(
        jsonEncode({
          'supported': true,
          'enabled': true,
          'sensitivity': 50,
          'ready': false,
          'rawReady': false,
          'cpuPressure': false,
          'ramPressure': true,
          'cpu': {'usagePercent': 35.0, 'maxPercent': 67.5},
          'memory': {
            'loadPercent': 88,
            'maxLoadPercent': 83.0,
            'totalBytes': 17179869184,
            'availBytes': 2147483648,
            'minAvailBytes': 3758096384,
          },
          'candidates': [
            {
              'id': 'chrome.exe',
              'name': 'Google Chrome',
              'category': 'browser',
              'recommended': true,
              'processCount': 8,
              'ramBytes': 1610612736,
              'cpuPercent': 11.2,
            },
          ],
        }),
        200,
      );
    });
    final okClient = NvHttpClient(httpsClientFactory: (_) => okMock);
    final status = await okClient.fetchWatchdogStatus('192.168.1.10');
    expect(status, isNotNull);
    expect(status!.ready, isFalse);
    expect(status.ramPressure, isTrue);
    expect(status.candidates, hasLength(1));
    expect(status.candidates.first.id, 'chrome.exe');

    final errClient = NvHttpClient(
      httpsClientFactory: (_) => MockClient((_) async => http.Response('', 404)),
    );
    expect(await errClient.fetchWatchdogStatus('192.168.1.10'), isNull);
  });

  test('cleanupWatchdog posts targets JSON and parses updated status', () async {
    final mock = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/watchdog-cleanup');
      expect(jsonDecode(request.body), {
        'targets': ['chrome.exe', 'slack.exe'],
      });
      return http.Response(
        jsonEncode({
          'supported': true,
          'enabled': true,
          'sensitivity': 50,
          'ready': true,
          'rawReady': true,
          'cpuPressure': false,
          'ramPressure': false,
          'cpu': {'usagePercent': 22.0, 'maxPercent': 67.5},
          'memory': {
            'loadPercent': 54,
            'maxLoadPercent': 83.0,
            'totalBytes': 17179869184,
            'availBytes': 7516192768,
            'minAvailBytes': 3758096384,
          },
          'candidates': const [],
        }),
        200,
      );
    });
    final client = NvHttpClient(httpsClientFactory: (_) => mock);
    final updated = await client.cleanupWatchdog('192.168.1.10', [
      'chrome.exe',
      'slack.exe',
    ]);
    expect(updated, isNotNull);
    expect(updated!.ready, isTrue);
    expect(updated.candidates, isEmpty);
  });
}

