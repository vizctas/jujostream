import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jujostream/services/http_api/nv_http_client.dart';

void main() {
  test('NvHttpClient fetches and controls /coopsessions and /coopcontrol', () async {
    String? lastMethod;
    String? lastPath;
    Map<String, dynamic>? lastBody;

    final mock = MockClient((req) async {
      lastMethod = req.method;
      lastPath = req.url.path;
      lastBody = req.body.isNotEmpty
          ? jsonDecode(req.body) as Map<String, dynamic>
          : null;
      return http.Response(
        jsonEncode({
          'status': true,
          'sessions': [
            {
              'session_id': 'rtsp:2',
              'client_uuid': 'uuid-mx',
              'display_name': 'AmigaMX',
              'role': req.method == 'POST' ? 'coop_kbm' : 'coop_pad',
              'transport': 'rtsp',
              'assigned_slot': 1,
              'is_owner': false,
              'paused': req.method == 'POST',
              'connected': true,
              'grace_remaining_ms': 0,
            },
          ],
        }),
        200,
      );
    });

    final client = NvHttpClient(httpsClientFactory: (_) => mock);
    final sessions = await client.getCoopSessions('192.168.1.10');
    expect(lastMethod, 'GET');
    expect(lastPath, '/coopsessions');
    expect(sessions.single.assignedSlot, 1);
    expect(sessions.single.role, 'coop_pad');

    final updated = await client.controlCoopSession(
      '192.168.1.10',
      sessionId: 'rtsp:2',
      role: 'coop_kbm',
      paused: true,
    );
    expect(lastMethod, 'POST');
    expect(lastPath, '/coopcontrol');
    expect(lastBody, {
      'session_id': 'rtsp:2',
      'role': 'coop_kbm',
      'paused': true,
    });
    expect(updated, hasLength(1));
    expect(updated!.single.role, 'coop_kbm');
    expect(updated.single.paused, isTrue);
  });

  test('NvHttpClient forwards coop_role extraLaunchParams on launch/resume', () async {
    final paths = <String, String?>{};
    final mock = MockClient((req) async {
      paths[req.url.path] = req.url.queryParameters['coop_role'];
      return http.Response(
        '<root status_code="200"><gamesession>1</gamesession><resume>1</resume></root>',
        200,
      );
    });

    final client = NvHttpClient(httpsClientFactory: (_) => mock);
    final launchRes = await client.launchApp(
      '192.168.1.10',
      10,
      width: 1920,
      height: 1080,
      extraLaunchParams: const {'coop_role': 'coop_pad'},
    );
    expect(launchRes.success, isTrue);
    expect(paths['/launch'], 'coop_pad');

    final resumeRes = await client.resumeApp(
      '192.168.1.10',
      10,
      width: 1920,
      height: 1080,
      extraLaunchParams: const {'coop_role': 'coop_pad'},
    );
    expect(resumeRes.success, isTrue);
    expect(paths['/resume'], 'coop_pad');
  });
}
