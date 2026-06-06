import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:jujostream/services/sync/cloud_sync_service.dart';
import 'package:jujostream/models/computer_details.dart';
import 'package:jujostream/providers/auth_provider.dart';

class MockSupabaseSyncHttpClient extends http.BaseClient {
  List<Map<String, dynamic>> dbRows = [];
  bool upsertCalled = false;
  List<Map<String, dynamic>> lastUpsertedRows = [];

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
        }
      });
    } else if (path.contains('/rest/v1/user_server_profiles')) {
      if (method == 'GET') {
        responseBody = jsonEncode(dbRows);
      } else if (method == 'POST') {
        upsertCalled = true;
        final requestBody = (request as http.Request).body;
        final parsed = jsonDecode(requestBody);
        if (parsed is List) {
          lastUpsertedRows = parsed.map((item) => item as Map<String, dynamic>).toList();
        } else if (parsed is Map) {
          lastUpsertedRows = [parsed.cast<String, dynamic>()];
        }
        responseBody = jsonEncode(lastUpsertedRows);
      }
    }

    final response = http.Response(responseBody, statusCode, headers: {
      'content-type': 'application/json; charset=utf-8',
    });

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
      anonKey: 'mockKey',
      httpClient: mockHttpClient,
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockHttpClient.dbRows.clear();
    mockHttpClient.upsertCalled = false;
    mockHttpClient.lastUpsertedRows.clear();
  });

  group('Supabase Cloud Server Profile Sync Tests', () {
    test('pushConfigToSupabase formats and upserts local computers to user_server_profiles', () async {
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

      await prefs.setStringList('saved_computers', [jsonEncode(localComputer.toJson())]);
      await prefs.setString('primary_server_uuid', 'test-uuid-1');

      // 3. Call pushConfigToSupabase
      final success = await CloudSyncService.instance.pushConfigToSupabase();
      expect(success, true);
      expect(mockHttpClient.upsertCalled, true);
      expect(mockHttpClient.lastUpsertedRows.length, 1);

      final row = mockHttpClient.lastUpsertedRows.first;
      expect(row['server_url'], 'https://192.168.1.100:47984');
      expect(row['server_name'], 'Gaming Rig');
      expect(row['cert_fingerprint'], 'ABCDEF123456');
      expect(row['is_default'], true);
      expect(row['external_address'], '73.42.15.200');
    });

    test('pullConfigFromSupabase pulls cloud rows, merges them, and saves to SharedPreferences', () async {
      // 1. Sign in the mock Supabase user
      await Supabase.instance.client.auth.signInWithPassword(
        email: 'user@test.com',
        password: 'password123',
      );

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
        }
      ];

      // 3. Perform pullConfigFromSupabase
      final success = await CloudSyncService.instance.pullConfigFromSupabase();
      expect(success, true);

      // 4. Verify local SharedPreferences are populated correctly
      final prefs = await SharedPreferences.getInstance();
      final savedComputersList = prefs.getStringList('saved_computers') ?? [];
      expect(savedComputersList.length, 1);

      final computer = ComputerDetails.fromJson(jsonDecode(savedComputersList.first));
      expect(computer.name, 'Cloud Rig');
      expect(computer.localAddress, '192.168.1.150');
      expect(computer.manualAddress, 'my-gaming-host.local');
      expect(computer.serverCert, 'FINGERPRINT999');
      expect(computer.remoteAddress, '73.42.15.300');
      expect(computer.pairState, PairState.paired);
      expect(prefs.getString('primary_server_uuid'), computer.uuid);
    });

    test('pullConfigFromSupabase bidirectional sync pushes local-only computers to Supabase', () async {
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
      await prefs.setStringList('saved_computers', [jsonEncode(localComputer.toJson())]);

      // 3. Mock empty cloud database
      mockHttpClient.dbRows = [];

      // 4. Perform pullConfigFromSupabase (this should trigger upsert of local-only to cloud)
      final success = await CloudSyncService.instance.pullConfigFromSupabase();
      expect(success, true);
      expect(mockHttpClient.upsertCalled, true);
      expect(mockHttpClient.lastUpsertedRows.length, 1);

      final row = mockHttpClient.lastUpsertedRows.first;
      expect(row['server_url'], 'https://192.168.1.200:47984');
      expect(row['server_name'], 'Local Only PC');
      expect(row['cert_fingerprint'], 'LOCALCERT');
    });

    test('AuthProvider pullFromCloud/pushToCloud dynamically routes to Supabase when signed in', () async {
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
      await prefs.setStringList('saved_computers', [jsonEncode(localComputer.toJson())]);

      final pushOk = await authProvider.pushToCloud();
      expect(pushOk, true);
      expect(mockHttpClient.upsertCalled, true);
      expect(mockHttpClient.lastUpsertedRows.first['server_url'], 'https://192.168.1.111:47984');
    });
  });
}
