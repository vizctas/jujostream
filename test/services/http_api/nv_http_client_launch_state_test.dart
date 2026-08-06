import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jujostream/services/http_api/nv_http_client.dart';

void main() {
  test('launch parses the authenticated game-readiness contract', () async {
    final mock = MockClient((request) async {
      expect(request.url.path, '/launch');
      return http.Response('''
        <root status_code="200">
          <gamesession>1</gamesession>
          <rikey>abcd</rikey>
          <rikeyid>42</rikeyid>
          <sessionUrl0>rtsp://host/session</sessionUrl0>
          <GameLaunchReadinessVersion>1</GameLaunchReadinessVersion>
          <GameLaunchReadinessRequired>1</GameLaunchReadinessRequired>
          <GameLaunchStateToken>opaque-token</GameLaunchStateToken>
          <GameLaunchState>waitingWindow</GameLaunchState>
          <GameLaunchStateGeneration>3</GameLaunchStateGeneration>
        </root>
      ''', 200);
    });
    final client = NvHttpClient(httpsClientFactory: (_) => mock);

    final result = await client.launchApp(
      '192.168.1.2',
      7,
      width: 1920,
      height: 1080,
    );

    expect(result.success, isTrue);
    expect(result.readinessVersion, 1);
    expect(result.readinessRequired, isTrue);
    expect(result.readinessToken, 'opaque-token');
    expect(result.readinessInitialState, 'waitingWindow');
    expect(result.readinessGeneration, 3);
  });

  test('launch remains parse-compatible with a legacy host response', () async {
    final mock = MockClient(
      (_) async => http.Response(
        '<root status_code="200"><gamesession>1</gamesession></root>',
        200,
      ),
    );
    final client = NvHttpClient(httpsClientFactory: (_) => mock);

    final result = await client.launchApp(
      '192.168.1.2',
      7,
      width: 1920,
      height: 1080,
    );

    expect(result.success, isTrue);
    expect(result.readinessVersion, 0);
    expect(result.readinessRequired, isFalse);
    expect(result.readinessToken, isEmpty);
  });

  test('launch-state status and retry remain token-bound requests', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      expect(request.url.path, '/launchstate');
      expect(request.url.queryParameters['token'], 'opaque-token');
      expect(
        request.url.queryParameters['action'],
        calls == 1 ? 'status' : 'retry',
      );
      return http.Response('''
        <root status_code="200">
          <GameLaunchState>ready</GameLaunchState>
          <GameLaunchReady>1</GameLaunchReady>
          <GameLaunchFailed>0</GameLaunchFailed>
          <GameLaunchDetail>Game is foreground and ready</GameLaunchDetail>
          <GameLaunchFailureCode></GameLaunchFailureCode>
          <GameLaunchStateGeneration>8</GameLaunchStateGeneration>
          <GameLaunchAttempt>2</GameLaunchAttempt>
          <GameLaunchSelectedPid>4242</GameLaunchSelectedPid>
        </root>
      ''', 200);
    });
    final client = NvHttpClient(httpsClientFactory: (_) => mock);

    final state = await client.getGameLaunchState(
      '192.168.1.2',
      'opaque-token',
    );
    final retried = await client.getGameLaunchState(
      '192.168.1.2',
      'opaque-token',
      retryFocus: true,
    );

    expect(state.requestSucceeded, isTrue);
    expect(state.ready, isTrue);
    expect(state.generation, 8);
    expect(state.attempt, 2);
    expect(state.selectedPid, 4242);
    expect(retried.requestSucceeded, isTrue);
    expect(calls, 2);
  });

  test('launch-state XML rejection never falls through as ready', () async {
    final mock = MockClient(
      (_) async => http.Response(
        '<root status_code="404" status_message="Launch state not found"/>',
        200,
      ),
    );
    final client = NvHttpClient(httpsClientFactory: (_) => mock);

    final state = await client.getGameLaunchState(
      '192.168.1.2',
      'expired-token',
    );

    expect(state.requestSucceeded, isFalse);
    expect(state.statusCode, 404);
    expect(state.ready, isFalse);
    expect(state.error, 'Launch state not found');
  });
}
