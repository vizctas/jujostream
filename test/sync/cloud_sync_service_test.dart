import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:jujostream/services/sync/cloud_sync_service.dart';
import 'package:jujostream/models/computer_details.dart';
import 'package:jujostream/providers/auth_provider.dart';
import 'package:jujostream/services/crypto/client_identity.dart';

class MockCloudPairingHttpClient extends http.BaseClient {
  final Completer<Map<String, dynamic>> requestBody = Completer();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonDecode((request as http.Request).body) as Map;
    if (!requestBody.isCompleted) {
      requestBody.complete(body.cast<String, dynamic>());
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"status":true,"clientUuid":"cloud-test"}')),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

class ControlledCloudPairingHttpClient extends http.BaseClient {
  final Completer<Map<String, dynamic>> requestBody = Completer();
  final Completer<http.StreamedResponse> response = Completer();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonDecode((request as http.Request).body) as Map;
    if (!requestBody.isCompleted) {
      requestBody.complete(body.cast<String, dynamic>());
    }
    return response.future;
  }

  void succeed() {
    response.complete(
      http.StreamedResponse(
        Stream.value(utf8.encode('{"status":true,"clientUuid":"cloud-test"}')),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
  }
}

class CountingCloudPairingClient extends http.BaseClient {
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    return http.StreamedResponse(Stream<List<int>>.empty(), 500);
  }
}

class MockSupabaseSyncHttpClient extends http.BaseClient {
  List<Map<String, dynamic>> dbRows = [];
  bool upsertCalled = false;
  List<Map<String, dynamic>> lastUpsertedRows = [];
  bool patchCalled = false;
  Map<String, dynamic> lastPatchedFields = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final method = request.method;

    String responseBody = '{}';
    int statusCode = 200;

    if (path.contains('/auth/v1/token')) {
      responseBody = jsonEncode({
        'access_token': 'mock-access-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'refresh_token': 'mock-refresh-token',
        'user': {
          'id': 'mock-user-uuid',
          'email': 'user@test.com',
          'email_confirmed_at': '2026-05-31T07:32:56.000Z',
        },
      });
    } else if (path.contains('/rest/v1/user_server_profiles')) {
      if (method == 'GET') {
        responseBody = jsonEncode(dbRows);
      } else if (method == 'POST') {
        upsertCalled = true;
        final requestBody = (request as http.Request).body;
        final parsed = jsonDecode(requestBody);
        if (parsed is List) {
          lastUpsertedRows = parsed
              .map((item) => item as Map<String, dynamic>)
              .toList();
        } else if (parsed is Map) {
          lastUpsertedRows = [parsed.cast<String, dynamic>()];
        }
        responseBody = jsonEncode(lastUpsertedRows);
      } else if (method == 'PATCH') {
        patchCalled = true;
        lastPatchedFields = (jsonDecode((request as http.Request).body) as Map)
            .cast<String, dynamic>();
        responseBody = jsonEncode(lastPatchedFields);
      }
    }

    final response = http.Response(
      responseBody,
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSupabaseSyncHttpClient mockHttpClient;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    mockHttpClient = MockSupabaseSyncHttpClient();
    // Re-initialize Supabase client with the mock HTTP client
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      publishableKey: 'mockKey',
      httpClient: mockHttpClient,
    );
    await ClientIdentity.init();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockHttpClient.dbRows.clear();
    mockHttpClient.upsertCalled = false;
    mockHttpClient.lastUpsertedRows.clear();
    mockHttpClient.patchCalled = false;
    mockHttpClient.lastPatchedFields.clear();
    CloudSyncService.instance.pairingClientFactoryForTest = (_) =>
        MockCloudPairingHttpClient();
  });

  group('Supabase Cloud Server Profile Sync Tests', () {
    test(
      'pushConfigToSupabase updates preferences on a server-owned cloud profile',
      () async {
        // 1. Sign in the mock Supabase user
        await Supabase.instance.client.auth.signInWithPassword(
          email: 'user@test.com',
          password: 'password123',
        );

        // 2. Set up local saved computers in SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final localComputer = ComputerDetails(
          uuid: 'test-uuid-1',
          name: 'Gaming Rig',
          localAddress: '192.168.1.100',
          httpsPort: 47984,
          remoteAddress: '73.42.15.200',
          serverCert: 'ABCDEF123456',
          state: ComputerState.online,
          pairState: PairState.paired,
        );

        await prefs.setStringList('saved_computers', [
          jsonEncode(localComputer.toJson()),
        ]);
        await prefs.setString('primary_server_uuid', 'test-uuid-1');
        await prefs.setStringList('computer_custom_order', ['test-uuid-1']);
        mockHttpClient.dbRows = [
          {
            'id': 'cloud-row-1',
            'server_url': 'https://192.168.1.100:47984',
            'cert_fingerprint': 'ABCDEF123456',
            'local_addresses': ['192.168.1.100'],
            'server_uuid': 'test-uuid-1',
          },
        ];

        // 3. Call pushConfigToSupabase
        final success = await CloudSyncService.instance.pushConfigToSupabase();
        expect(success, true);
        expect(mockHttpClient.patchCalled, true);
        expect(mockHttpClient.upsertCalled, false);
        expect(mockHttpClient.lastPatchedFields['is_default'], true);
        expect(mockHttpClient.lastPatchedFields['display_order'], 0);
        expect(mockHttpClient.lastPatchedFields, isNot(contains('server_url')));
      },
    );

    test(
      'pullConfigFromSupabase pulls cloud rows, merges them, and saves to SharedPreferences',
      () async {
        // 1. Sign in the mock Supabase user
        await Supabase.instance.client.auth.signInWithPassword(
          email: 'user@test.com',
          password: 'password123',
        );

        final pairingClient = ControlledCloudPairingHttpClient();
        CloudSyncService.instance.pairingClientFactoryForTest = (_) =>
            pairingClient;

        // 2. Set up cloud server profiles in mock client db
        mockHttpClient.dbRows = [
          {
            'id': 'cloud-uuid-1',
            'user_id': 'mock-user-uuid',
            'server_url': 'https://my-gaming-host.local:47984',
            'server_name': 'Cloud Rig',
            'cert_fingerprint': 'FINGERPRINT999',
            'local_addresses': ['192.168.1.150'],
            'is_default': true,
            'external_address': '73.42.15.300',
            'server_version': '1.0.0',
          },
        ];

        // 3. Perform pullConfigFromSupabase
        final success = await CloudSyncService.instance
            .pullConfigFromSupabase();
        expect(success, true);

        // 4. Verify local SharedPreferences are populated correctly
        final prefs = await SharedPreferences.getInstance();
        final savedComputersList = prefs.getStringList('saved_computers') ?? [];
        expect(savedComputersList.length, 1);

        final computer = ComputerDetails.fromJson(
          jsonDecode(savedComputersList.first),
        );
        expect(computer.name, 'Cloud Rig');
        expect(computer.localAddress, '192.168.1.150');
        expect(computer.manualAddress, 'my-gaming-host.local');
        expect(computer.serverCert, 'FINGERPRINT999');
        expect(computer.remoteAddress, '73.42.15.300');
        expect(computer.pairState, PairState.notPaired);
        expect(prefs.getString('primary_server_uuid'), computer.uuid);

        await pairingClient.requestBody.future.timeout(
          const Duration(seconds: 5),
        );
        pairingClient.succeed();

        ComputerDetails? pairedComputer;
        for (var attempt = 0; attempt < 20; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          final updated = prefs.getStringList('saved_computers') ?? const [];
          if (updated.isEmpty) continue;
          pairedComputer = ComputerDetails.fromJson(jsonDecode(updated.first));
          if (pairedComputer.pairState == PairState.paired) break;
        }
        expect(pairedComputer?.pairState, PairState.paired);
      },
    );

    test(
      'cloud profile automatically pairs through its pinned self-signed certificate',
      () async {
        await Supabase.instance.client.auth.signInWithPassword(
          email: 'user@test.com',
          password: 'password123',
        );

        final pairingClient = MockCloudPairingHttpClient();
        CloudSyncService.instance.pairingClientFactoryForTest = (_) =>
            pairingClient;
        mockHttpClient.dbRows = [
          {
            'id': 'cloud-pinned-server',
            'user_id': 'mock-user-uuid',
            'server_uuid': 'cloud-pinned-server',
            'server_url': 'https://cloud-rig.example:47990',
            'server_name': 'Pinned Cloud Rig',
            'cert_fingerprint': List.filled(64, 'a').join(),
            'local_addresses': ['192.168.1.20'],
            'is_default': true,
          },
        ];

        expect(
          await CloudSyncService.instance.pullConfigFromSupabase(),
          isTrue,
        );
        final payload = await pairingClient.requestBody.future.timeout(
          const Duration(seconds: 5),
        );
        expect(payload['token'], 'mock-access-token');
        expect(payload['clientCert'], ClientIdentity.certPem);
        expect(payload['deviceName'], isNotEmpty);
      },
    );

    test(
      'repairs a rotated server identity only from the authenticated cloud profile',
      () async {
        await Supabase.instance.client.auth.signInWithPassword(
          email: 'user@test.com',
          password: 'password123',
        );

        final computer = ComputerDetails(
          uuid: 'rotated-server',
          name: 'Gaming Rig',
          localAddress: '192.168.3.6',
          httpsPort: 47984,
          configHttpsPort: 47990,
          serverCert: 'OLD-FINGERPRINT',
          isCloud: true,
          pairState: PairState.paired,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('saved_computers', [
          jsonEncode(computer.toJson()),
        ]);

        mockHttpClient.dbRows = [
          {
            'id': 'cloud-row',
            'user_id': 'mock-user-uuid',
            'server_uuid': 'rotated-server',
            'server_url': 'https://192.168.3.6:47990',
            'server_name': 'Gaming Rig',
            'cert_fingerprint': 'NEW-FINGERPRINT',
            'local_addresses': ['192.168.3.6'],
          },
        ];

        String? pairingPin;
        CloudSyncService.instance.pairingClientFactoryForTest = (candidate) {
          pairingPin = candidate.serverCert;
          return MockCloudPairingHttpClient();
        };

        expect(
          await CloudSyncService.instance
              .recoverCloudPairingAfterServerIdentityChange(computer),
          isTrue,
        );
        expect(computer.serverCert, 'NEW-FINGERPRINT');
        expect(pairingPin, 'NEW-FINGERPRINT');

        final saved = prefs.getStringList('saved_computers')!;
        final restored = ComputerDetails.fromJson(jsonDecode(saved.single));
        expect(restored.serverCert, 'NEW-FINGERPRINT');
        expect(restored.pairState, PairState.paired);
      },
    );

    test('does not replace a server pin while signed out', () async {
      await Supabase.instance.client.auth.signOut();
      final computer = ComputerDetails(
        uuid: 'rotated-server',
        localAddress: '192.168.3.6',
        serverCert: 'OLD-FINGERPRINT',
        pairState: PairState.paired,
      );
      var pairingAttempted = false;
      CloudSyncService.instance.pairingClientFactoryForTest = (_) {
        pairingAttempted = true;
        return MockCloudPairingHttpClient();
      };

      expect(
        await CloudSyncService.instance
            .recoverCloudPairingAfterServerIdentityChange(computer),
        isFalse,
      );
      expect(computer.serverCert, 'OLD-FINGERPRINT');
      expect(computer.pairState, PairState.paired);
      expect(pairingAttempted, isFalse);
    });

    test(
      'pullConfigFromSupabase keeps local-only computers out of cloud profiles',
      () async {
        // 1. Sign in the mock Supabase user
        await Supabase.instance.client.auth.signInWithPassword(
          email: 'user@test.com',
          password: 'password123',
        );

        // 2. Set up local saved computers (local-only)
        final prefs = await SharedPreferences.getInstance();
        final localComputer = ComputerDetails(
          uuid: 'local-only-uuid',
          name: 'Local Only PC',
          localAddress: '192.168.1.200',
          httpsPort: 47984,
          serverCert: 'LOCALCERT',
        );
        await prefs.setStringList('saved_computers', [
          jsonEncode(localComputer.toJson()),
        ]);

        // 3. Mock empty cloud database
        mockHttpClient.dbRows = [];

        final pairingClient = CountingCloudPairingClient();
        CloudSyncService.instance.pairingClientFactoryForTest = (_) =>
            pairingClient;

        // 4. Pulling must not create a cloud row. The server cloud agent owns it.
        final success = await CloudSyncService.instance
            .pullConfigFromSupabase();
        expect(success, true);
        expect(mockHttpClient.upsertCalled, false);
        final saved = prefs.getStringList('saved_computers')!;
        final restored = ComputerDetails.fromJson(jsonDecode(saved.single));
        expect(restored.isCloud, false);
        await Future<void>.delayed(Duration.zero);
        expect(pairingClient.requestCount, 0);
      },
    );

    test(
      'AuthProvider cloud routing preserves server-owned profile boundaries',
      () async {
        final authProvider = AuthProvider();

        // 1. Sign in mock user
        await Supabase.instance.client.auth.signInWithPassword(
          email: 'user@test.com',
          password: 'password123',
        );
        expect(authProvider.isSupabaseSignedIn, true);

        // 2. Call pullFromCloud and verify it completes successfully via Supabase
        mockHttpClient.dbRows = [];
        final pullOk = await authProvider.pullFromCloud();
        expect(pullOk, true);

        // 3. Set local computer to verify push routes correctly to Supabase
        final prefs = await SharedPreferences.getInstance();
        final localComputer = ComputerDetails(
          uuid: 'test-uuid-x',
          name: 'Test Rig',
          localAddress: '192.168.1.111',
        );
        await prefs.setStringList('saved_computers', [
          jsonEncode(localComputer.toJson()),
        ]);

        final pushOk = await authProvider.pushToCloud();
        expect(pushOk, true);
        expect(mockHttpClient.upsertCalled, false);
      },
    );
  });
}
