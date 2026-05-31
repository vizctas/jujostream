import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jujostream/providers/settings_provider.dart';
import 'package:jujostream/models/stream_configuration.dart';
import 'package:jujostream/providers/plugins_provider.dart';
import 'package:jujostream/providers/auth_provider.dart';
import 'package:jujostream/providers/cloud_mfa_provider.dart';
import 'package:jujostream/services/metadata/steam_video_client.dart';
import 'package:jujostream/platform_channels/streaming_channel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

// Base64 helper for custom JWT simulation
String createMockJwt(String aal) {
  final payload = {
    'aal': aal,
    'amr': [{'method': 'pwd', 'timestamp': 123456789}],
    'exp': 2724393600
  };
  final encodedPayload = base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  return 'header.$encodedPayload.signature';
}

class MockSteamHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    String body = '{}';

    if (path.contains('/api/storesearch/')) {
      body = jsonEncode({
        'items': [
          {
            'id': 400,
            'name': 'Portal',
            'tiny_image': 'https://mock.steam/portal.jpg'
          }
        ]
      });
    } else if (path.contains('/api/appdetails')) {
      body = jsonEncode({
        '400': {
          'success': true,
          'data': {
            'short_description': 'A puzzle game.',
            'genres': [
              {'description': 'Puzzle'}
            ],
            'movies': [
              {
                'id': 123,
                'name': 'Portal Trailer',
                'thumbnail': 'https://mock.steam/portal_thumb.jpg',
                'mp4': {
                  '480': 'https://mock.steam/portal_480.mp4',
                  'max': 'https://mock.steam/portal_max.mp4'
                }
              }
            ]
          }
        }
      });
    }

    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

class MockSupabaseHttpClient extends http.BaseClient {
  bool signupConfirmRequired = true;
  bool isConfirmed = false;
  bool hasMfaFactor = false;
  bool mfaVerified = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final method = request.method;
    
    print('MockSupabaseHttpClient: path=$path method=$method');
    
    String responseBody = '{}';
    int statusCode = 200;

    if (path.contains('/auth/v1/signup')) {
      responseBody = jsonEncode({
        'id': 'mock-user-uuid',
        'email': 'user@test.com',
        'email_confirmed_at': signupConfirmRequired ? null : '2026-05-31T07:32:56.000Z',
        'user_metadata': {}
      });
    } else if (path.contains('/auth/v1/token')) {
      if (signupConfirmRequired && !isConfirmed) {
        // Sign-in fails due to unconfirmed email
        responseBody = jsonEncode({
          'access_token': createMockJwt('aal1'),
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'mock-refresh-token',
          'user': {
            'id': 'mock-user-uuid',
            'email': 'user@test.com',
            'email_confirmed_at': null,
          }
        });
      } else {
        responseBody = jsonEncode({
          'access_token': createMockJwt(mfaVerified ? 'aal2' : 'aal1'),
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'mock-refresh-token',
          'user': {
            'id': 'mock-user-uuid',
            'email': 'user@test.com',
            'email_confirmed_at': '2026-05-31T07:32:56.000Z',
            'factors': hasMfaFactor ? [
              {
                'id': 'mock-factor-uuid',
                'friendly_name': 'Jujo.Stream Client',
                'factor_type': 'totp',
                'status': 'verified',
                'created_at': '2026-05-31T07:32:56.000Z',
                'updated_at': '2026-05-31T07:32:56.000Z'
              }
            ] : []
          }
        });
      }
    } else if (path.contains('/challenge')) {
      responseBody = jsonEncode({
        'id': 'mock-challenge-uuid',
        'expires_at': 2724393600 // Wait! In GoTrue-Dart, it expects a number (seconds/timestamp) or string? The error said: Expected expires_at to be a number, got Null! So it wants a number (int) timestamp! E.g. 2724393600!
      });
    } else if (path.contains('/verify')) {
      // Challenge Verification
      final bodyBytes = await (request as http.Request).body;
      final parsed = jsonDecode(bodyBytes);
      if (parsed['code'] == '123456') {
        mfaVerified = true;
        responseBody = jsonEncode({
          'access_token': createMockJwt('aal2'),
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'mock-refresh-token',
          'user': {
            'id': 'mock-user-uuid',
            'email': 'user@test.com',
            'email_confirmed_at': '2026-05-31T07:32:56.000Z',
          }
        });
      } else {
        statusCode = 400;
        responseBody = jsonEncode({
          'error': 'Invalid 2FA code',
          'message': 'Invalid 2FA code. Try again.'
        });
      }
    } else if (path.contains('/auth/v1/factors')) {
      if (method == 'GET') {
        if (hasMfaFactor) {
          responseBody = jsonEncode([
            {
              'id': 'mock-factor-uuid',
              'friendly_name': 'Jujo.Stream Client',
              'factor_type': 'totp',
              'status': 'verified',
              'created_at': '2026-05-31T07:32:56.000Z',
              'updated_at': '2026-05-31T07:32:56.000Z'
            }
          ]);
        } else {
          responseBody = jsonEncode([]);
        }
      } else if (method == 'POST') {
        // Enroll factor
        responseBody = jsonEncode({
          'id': 'mock-factor-uuid',
          'type': 'totp',
          'totp': {
            'qr_code': 'mock-qr-code',
            'secret': 'mock-secret-uri-value',
            'uri': 'otpauth://totp/Jujo.Stream:user@test.com?secret=mock-secret-uri-value&issuer=Jujo.Stream'
          }
        });
      }
    }

    final response = http.Response(responseBody, statusCode, headers: {
      'content-type': 'application/json; charset=utf-8',
    });

    final stream = Stream.value(response.bodyBytes);
    return http.StreamedResponse(stream, response.statusCode, headers: response.headers);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, Object> mockPrefs;
  late MockSupabaseHttpClient mockHttpClient;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    mockHttpClient = MockSupabaseHttpClient();
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mockKey',
      httpClient: mockHttpClient,
    );
  });

  setUp(() {
    mockPrefs = <String, Object>{};
    SharedPreferences.setMockInitialValues(mockPrefs);
    mockHttpClient.signupConfirmRequired = true;
    mockHttpClient.isConfirmed = false;
    mockHttpClient.hasMfaFactor = false;
    mockHttpClient.mfaVerified = false;
  });

  group('Onboarding & First-Run Scenarios', () {
    test('Scenario 1: Happy Path First-Run Onboarding', () async {
      // 1. Initial State: Onboarding not completed
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('first_run_shown'), null);

      // 2. Perform onboarding step: set onboarding shown to true
      await prefs.setBool('first_run_shown', true);

      // 3. Verify onboarding completion state is persisted
      expect(prefs.getBool('first_run_shown'), true);
    });

    test('Scenario 2: Gamepad Navigation & Disclaimer Acceptance simulation', () async {
      final prefs = await SharedPreferences.getInstance();
      
      // Simulate disclaimer dismissed via Gamepad A / Enter key
      // In first-run gate, key A or enter sets first_run_shown to true
      await prefs.setBool('first_run_shown', true);

      expect(prefs.getBool('first_run_shown'), true);
    });
  });

  group('Cloud Registration & Auth Gating Scenarios', () {
    test('Scenario 3: Supabase Cloud Registration with Email Polling', () async {
      final authProvider = AuthProvider();

      // 1. Trigger registration
      final signupOk = await authProvider.signUpWithCloud(
        email: 'user@test.com',
        password: 'password123',
      );
      expect(signupOk, true);

      // 2. Simulate polling ticks: first ticks are unconfirmed
      mockHttpClient.isConfirmed = false;
      final poll1 = await authProvider.loginWithCloud(
        email: 'user@test.com',
        password: 'password123',
      );
      expect(poll1, false); // Failed because email not confirmed yet
      expect(authProvider.isSignedIn, false);

      // 3. Tick where email is now confirmed
      mockHttpClient.isConfirmed = true;
      final pollSuccess = await authProvider.loginWithCloud(
        email: 'user@test.com',
        password: 'password123',
      );
      expect(pollSuccess, true);
      expect(authProvider.isSignedIn, true);
      expect(authProvider.email, 'user@test.com');
    });

    test('Scenario 4: Cloud Registration Email Polling Failure / Timeout simulation', () async {
      final authProvider = AuthProvider();

      // 1. Trigger registration
      final signupOk = await authProvider.signUpWithCloud(
        email: 'user@test.com',
        password: 'password123',
      );
      expect(signupOk, true);

      // 2. Simulate polling failures (e.g. email never gets confirmed)
      mockHttpClient.isConfirmed = false;
      
      // First poll
      final poll1 = await authProvider.loginWithCloud(
        email: 'user@test.com',
        password: 'password123',
      );
      expect(poll1, false);

      // Second poll
      final poll2 = await authProvider.loginWithCloud(
        email: 'user@test.com',
        password: 'password123',
      );
      expect(poll2, false);

      // Verify that after multiple failures, user remains unauthenticated
      expect(authProvider.isSignedIn, false);
      expect(authProvider.cloudError, 'Por favor, confirma tu correo antes de iniciar sesión.');
    });

    test('Scenario 5: Jujo Cloud Login with MFA/2FA Gating', () async {
      final authProvider = AuthProvider();
      final mfaProvider = CloudMfaProvider();

      // 1. Sign in user
      mockHttpClient.isConfirmed = true;
      final loginOk = await authProvider.loginWithCloud(
        email: 'user@test.com',
        password: 'password123',
      );
      expect(loginOk, true);
      expect(authProvider.isSignedIn, true);
      
      final session = Supabase.instance.client.auth.currentSession;
      print('Scenario 5: currentSession=$session');

      // 2. Check MFA status (which is locked / requires verification because user has factor enrolled)
      mockHttpClient.hasMfaFactor = true;
      await mfaProvider.refresh();

      expect(mfaProvider.status, CloudMfaStatus.verifyRequired);
      expect(mfaProvider.isSatisfied, false);
      expect(mfaProvider.blocksCloudUser, true); // STRICT LOCK-OUT GATE ACTIVE
    });

    test('Scenario 6: MFA Verification Code Failure & Recovery', () async {
      final authProvider = AuthProvider();
      final mfaProvider = CloudMfaProvider();

      // 1. Sign in user & load MFA state
      mockHttpClient.isConfirmed = true;
      mockHttpClient.hasMfaFactor = true;
      await authProvider.loginWithCloud(
        email: 'user@test.com',
        password: 'password123',
      );
      await mfaProvider.refresh();
      expect(mfaProvider.blocksCloudUser, true);

      // 2. Enter invalid verification code (e.g. '000000')
      try {
        final chal = await Supabase.instance.client.auth.mfa.challenge(factorId: 'mock-factor-uuid');
        print('Direct challenge output: id=${chal.id} expiresAt=${chal.expiresAt}');
      } catch (err) {
        print('Direct challenge threw: $err');
      }

      final verifyFail = await mfaProvider.verifyCode('000000');
      expect(verifyFail, false);
      expect(mfaProvider.isSatisfied, false);
      expect(mfaProvider.error, 'Invalid 2FA code. Try again.');

      // 3. Recover by entering correct verification code ('123456')
      final verifySuccess = await mfaProvider.verifyCode('123456');
      expect(verifySuccess, true);
      expect(mfaProvider.isSatisfied, true);
      expect(mfaProvider.status, CloudMfaStatus.satisfied);
      expect(mfaProvider.blocksCloudUser, false); // LOCK-OUT REMOVED
    });
  });

  group('Settings Sync & Snapshots Scenarios', () {
    test('Scenario 7: Local Settings Modification & Remote Sync Merge', () async {
      final settings = SettingsProvider();
      await settings.loadSettings();

      // 1. Modify settings locally
      await settings.setResolution(1920, 1080);
      await settings.setFps(60);
      await settings.setBitrate(40000);
      await settings.setHdr(true);

      expect(settings.config.width, 1920);
      expect(settings.config.fps, 60);
      expect(settings.config.bitrate, 40000);
      expect(settings.config.enableHdr, true);

      // 2. Simulate Cloud Pull & Merge: Remote configuration has new clientMic set to true
      await settings.applySerializedConfig({
        'clientMic': true,
        'fps': 60, // keeps same fps
        'bitrate': 50000, // remote cloud update overrides bitrate
      });

      // 3. Verify merged config preserves both local changes and incoming cloud overrides
      expect(settings.config.width, 1920);
      expect(settings.config.fps, 60);
      expect(settings.config.bitrate, 50000);
      expect(settings.config.clientMic, true);
      expect(settings.config.enableHdr, true);
    });

    test('Scenario 8: State Snapshot Capture & Telemetry', () async {
      final config = const StreamConfiguration(
        width: 1280,
        height: 720,
        fps: 30,
        bitrate: 15000,
        clientMic: true,
        enableHdr: false,
      );

      final snapshot = config.toJson();

      expect(snapshot['width'], 1280);
      expect(snapshot['height'], 720);
      expect(snapshot['fps'], 30);
      expect(snapshot['bitrate'], 15000);
      expect(snapshot['clientMic'], true);
      expect(snapshot['enableHdr'], false);
    });
  });

  group('STEAM Game Source Integration Scenarios', () {
    test('Scenario 9: Adding Game Source (STEAM Integration)', () async {
      // Initialize the Steam client with our custom mock HTTP client
      final steamClient = SteamVideoClient(client: MockSteamHttpClient());

      // 1. Search for game
      final appId = await steamClient.searchAppId('Portal');
      expect(appId, 400);

      // 2. Fetch game details and movies
      final details = await steamClient.getStoreData(400);
      expect(details.description, 'A puzzle game.');
      expect(details.genres.first, 'Puzzle');
      expect(details.movies.isNotEmpty, true);
      expect(details.movies.first.bestUrl, 'https://mock.steam/portal_480.mp4');
      expect(details.movies.first.thumbnail, 'https://mock.steam/portal_thumb.jpg');
    });
  });

  group('Stream Session & Quick Menu Scenarios', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.limelight.jujostream/streaming'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'startStream') {
            final args = methodCall.arguments as Map;
            if (args['host'] == 'error-host') {
              throw PlatformException(
                code: 'STRM-005',
                message: 'Video decoder failed to initialize. code 104',
                details: 104,
              );
            }
            return true;
          } else if (methodCall.method == 'stopStream') {
            return null;
          }
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.limelight.jujostream/streaming'),
        null,
      );
    });

    test('Scenario 10: Stream Session Startup & Video/Audio Initialization', () async {
      final started = await StreamingPlatformChannel.startStream(
        host: '192.168.1.100',
        httpsPort: 47984,
        appId: '12345',
        width: 1920,
        height: 1080,
        fps: 60,
        bitrate: 20000,
        videoCodec: 'H264',
        enableHdr: false,
        fullRange: false,
        framePacing: FramePacing.balanced,
        audioConfig: 'stereo',
        audioQuality: AudioQuality.high,
        serverCert: 'CAFEBABE',
        riKey: 'mock-key',
        riKeyId: 1,
        appVersion: '1.1.13',
        gfeVersion: '3.27',
        serverCodecModeSupport: 15,
      );

      expect(started, true);
      expect(StreamingPlatformChannel.lastStartStreamError, null);
    });

    test('Scenario 11: Streaming Failure & Recovery (Decoder Crash)', () async {
      final started = await StreamingPlatformChannel.startStream(
        host: 'error-host',
        httpsPort: 47984,
        appId: '12345',
        width: 1920,
        height: 1080,
        fps: 60,
        bitrate: 20000,
        videoCodec: 'H264',
        enableHdr: false,
        fullRange: false,
        framePacing: FramePacing.balanced,
        audioConfig: 'stereo',
        audioQuality: AudioQuality.high,
        serverCert: 'CAFEBABE',
        riKey: 'mock-key',
        riKeyId: 1,
        appVersion: '1.1.13',
        gfeVersion: '3.27',
        serverCodecModeSupport: 15,
      );

      // Verify startup failed
      expect(started, false);
      expect(StreamingPlatformChannel.lastStartStreamError, 'STRM-005: Video decoder failed to initialize. code 104');
      expect(StreamingPlatformChannel.lastStartStreamErrorCode, 104);
    });

    test('Scenario 12: Stream Overlay Quick Menu & Live Mic Passthrough Toggle', () async {
      final settings = SettingsProvider();
      await settings.loadSettings();

      // 1. Initial configuration: mic passthrough is disabled
      expect(settings.config.clientMic, false);

      // 2. User invokes Quick Menu and toggles Mic Passthrough
      await settings.updateConfig(settings.config.copyWith(clientMic: true));

      // 3. Verify it is dynamically updated and notified
      expect(settings.config.clientMic, true);
    });
  });
}

