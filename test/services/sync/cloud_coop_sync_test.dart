import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jujostream/l10n/app_localizations.dart';
import 'package:jujostream/models/computer_details.dart';
import 'package:jujostream/providers/computer_provider.dart';
import 'package:jujostream/screens/pc_view/pending_invites_section.dart';
import 'package:jujostream/services/crypto/client_identity.dart';
import 'package:jujostream/services/secure/secure_secret_store.dart';
import 'package:jujostream/services/sync/guest_link.dart';
import 'package:jujostream/services/sync/cloud_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MemorySecretStore implements SecureSecretStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _CountingPairingClient extends http.BaseClient {
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"status":true,"clientUuid":"coop-guest"}')),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

class _MockCoopSupabaseHttpClient extends http.BaseClient {
  List<Map<String, dynamic>> ownedRows = [];
  List<Map<String, dynamic>> sharedRows = [];
  List<Map<String, dynamic>> coopSharedRows = [];
  List<Map<String, dynamic>> coopInvites = [];
  List<Map<String, dynamic>> serverInvites = [];
  bool failServerInvitesRpc = false;
  bool failCoopSharedRpc = false;
  Map<String, dynamic> respondResult = {'success': true};
  String? lastRpcName;
  Map<String, dynamic>? lastRpcBody;
  Object guestRpcResult = {'success': true};
  List<Map<String, dynamic>> pendingGuestRows = [];
  List<Map<String, dynamic>> guestRequestRows = [];
  String? lastRestMethod;
  String? lastRestQuery;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    String responseBody = '[]';
    int statusCode = 200;

    if (path.contains('/auth/v1/token')) {
      responseBody = jsonEncode({
        'access_token': 'mock-access-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'refresh_token': 'mock-refresh-token',
        'user': {
          'id': 'mock-guest-uuid',
          'email': 'guest@test.com',
          'email_confirmed_at': '2026-11-14T00:00:00.000Z',
        },
      });
    } else if (path.contains('/rest/v1/user_server_profiles')) {
      responseBody = jsonEncode(ownedRows);
    } else if (path.contains('/rest/v1/rpc/shared_server_profiles')) {
      responseBody = jsonEncode(sharedRows);
    } else if (path.contains('/rest/v1/rpc/active_coop_shared_servers')) {
      if (failCoopSharedRpc) {
        statusCode = 500;
        responseBody = jsonEncode({'message': 'rpc unavailable'});
      } else {
        responseBody = jsonEncode(coopSharedRows);
      }
    } else if (path.contains('/rest/v1/rpc/my_coop_invites')) {
      responseBody = jsonEncode(coopInvites);
    } else if (path.contains('/rest/v1/rpc/my_server_invites')) {
      if (failServerInvitesRpc) {
        statusCode = 500;
        responseBody = jsonEncode({'message': 'server invites down'});
      } else {
        responseBody = jsonEncode(serverInvites);
      }
    } else if (path.contains('/rest/v1/rpc/pending_guest_requests')) {
      responseBody = jsonEncode(pendingGuestRows);
    } else if (path.contains('/rest/v1/rpc/redeem_guest_link') ||
        path.contains('/rest/v1/rpc/create_guest_link') ||
        path.contains('/rest/v1/rpc/respond_guest_request') ||
        path.contains('/rest/v1/rpc/set_auto_accept_guests')) {
      lastRpcName = path.split('/').last;
      lastRpcBody = (jsonDecode((request as http.Request).body) as Map)
          .cast<String, dynamic>();
      responseBody = jsonEncode(guestRpcResult);
    } else if (path.contains('/rest/v1/coop_session_invites')) {
      lastRestMethod = request.method;
      lastRestQuery = request.url.query;
      responseBody = jsonEncode(guestRequestRows);
    } else if (path.contains('/rest/v1/rpc/respond_coop_invite') ||
        path.contains('/rest/v1/rpc/respond_server_invite')) {
      lastRpcName = path.split('/').last;
      final body = (request as http.Request).body;
      lastRpcBody = body.isNotEmpty
          ? (jsonDecode(body) as Map).cast<String, dynamic>()
          : null;
      responseBody = jsonEncode(respondResult);
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

  late _MockCoopSupabaseHttpClient mockHttpClient;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    mockHttpClient = _MockCoopSupabaseHttpClient();
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      publishableKey: 'mockKey',
      httpClient: mockHttpClient,
    );
    await ClientIdentity.init(secureStore: _MemorySecretStore());
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'guest@test.com',
      password: 'password123',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockHttpClient
      ..ownedRows = []
      ..sharedRows = []
      ..coopSharedRows = []
      ..coopInvites = []
      ..serverInvites = []
      ..failServerInvitesRpc = false
      ..failCoopSharedRpc = false
      ..respondResult = {'success': true}
      ..lastRpcName = null
      ..lastRpcBody = null
      ..guestRpcResult = {'success': true}
      ..pendingGuestRows = []
      ..guestRequestRows = []
      ..lastRestMethod = null
      ..lastRestQuery = null;
  });

  group('ComputerDetails Co-Op serialization', () {
    test('remains backward-compatible when coop fields are absent', () {
      final restored = ComputerDetails.fromJson({
        'uuid': 'legacy-1',
        'name': 'Legacy PC',
        'localAddress': '192.168.1.20',
      });

      expect(restored.coopRole, isNull);
      expect(restored.coopExpiresAt, isNull);
      expect(restored.isCoopTemporary, isFalse);
      expect(restored.isCoopExpired, isFalse);

      final encoded = restored.toJson();
      expect(encoded.containsKey('coopRole'), isFalse);
      expect(encoded.containsKey('coopExpiresAt'), isFalse);
    });

    test('round-trips coopRole and coopExpiresAt and detects expiry', () {
      final future = DateTime.now().toUtc().add(const Duration(hours: 3));
      final active = ComputerDetails(
        uuid: 'coop-1',
        name: 'Host Rig',
        coopRole: 'coop_pad',
        coopExpiresAt: future,
      );

      final restored = ComputerDetails.fromJson(active.toJson());
      expect(restored.coopRole, 'coop_pad');
      expect(restored.coopExpiresAt?.toUtc(), future);
      expect(restored.isCoopTemporary, isTrue);
      expect(restored.isCoopExpired, isFalse);

      final expired = ComputerDetails(
        uuid: 'coop-2',
        coopRole: 'viewer',
        coopExpiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      );
      expect(expired.isCoopTemporary, isTrue);
      expect(expired.isCoopExpired, isTrue);
      expect(
        isComputerVisible(
          computer: expired,
          cloudSignedIn: true,
          lanDiscovered: true,
        ),
        isFalse,
      );
    });
  });

  group('CloudPendingInvite parsing', () {
    test('parses coop & server invites and handles fallback name and expiry', () {
      final futureIso = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 2))
          .toIso8601String();
      final pastIso = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();

      final coop = CloudPendingInvite.fromJson({
        'id': 'inv-coop',
        'server_url': 'https://host.local:47990',
        'server_name': 'Amiga Rig',
        'role': 'coop_kbm',
        'owner_email': 'host@test.com',
        'expires_at': futureIso,
      }, isCoop: true);

      expect(coop.isCoop, isTrue);
      expect(coop.inviteId, 'inv-coop');
      expect(coop.serverName, 'Amiga Rig');
      expect(coop.role, 'coop_kbm');
      expect(coop.isExpired, isFalse);

      final fallback = CloudPendingInvite.fromJson({
        'id': 'inv-perm',
        'server_url': 'https://192.168.1.99:47990',
        'server_name': null,
        'role': 'viewer',
        'owner_email': 'owner@test.com',
        'expires_at': pastIso,
      }, isCoop: false);

      expect(fallback.isCoop, isFalse);
      expect(fallback.serverName, 'https://192.168.1.99:47990');
      expect(fallback.isExpired, isTrue);
    });
  });

  group('CloudSyncService Co-Op invites & pull sync', () {
    test('fetchPendingInvites tolerates partial RPC failure and filters expired', () async {
      final futureIso = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 3))
          .toIso8601String();
      final pastIso = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 1))
          .toIso8601String();

      mockHttpClient.coopInvites = [
        {
          'id': 'coop-active',
          'server_url': 'https://192.168.1.40:47990',
          'server_name': 'Co-Op Host',
          'role': 'coop_pad',
          'owner_email': 'friend@test.com',
          'expires_at': futureIso,
        },
        {
          'id': 'coop-expired',
          'server_url': 'https://192.168.1.41:47990',
          'server_name': 'Old Host',
          'role': 'viewer',
          'owner_email': 'friend@test.com',
          'expires_at': pastIso,
        },
      ];
      mockHttpClient.failServerInvitesRpc = true;

      final invites = await CloudSyncService.instance.fetchPendingInvites();
      expect(invites, hasLength(1));
      expect(invites.single.inviteId, 'coop-active');
      expect(invites.single.isCoop, isTrue);
    });

    test('respondToInvite uses p_invite_id and p_accept and syncs on accept', () async {
      final futureIso = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 4))
          .toIso8601String();
      final pairingClient = _CountingPairingClient();
      CloudSyncService.instance.pairingClientFactoryForTest = (_) =>
          pairingClient;

      mockHttpClient.coopSharedRows = [
        {
          'server_url': 'https://192.168.1.50:47990',
          'server_name': 'Coop PC',
          'server_uuid': 'coop-pc-uuid',
          'cert_fingerprint': 'COOP-CERT',
          'local_addresses': ['192.168.1.50'],
          'role': 'coop_pad',
          'owner_email': 'friend@test.com',
          'expires_at': futureIso,
        },
      ];

      final coopInvite = CloudPendingInvite(
        isCoop: true,
        inviteId: 'uuid-coop-1',
        ownerEmail: 'friend@test.com',
        serverName: 'Coop PC',
        serverUrl: 'https://192.168.1.50:47990',
        role: 'coop_pad',
        expiresAt: DateTime.parse(futureIso),
      );

      final accepted = await CloudSyncService.instance.respondToInvite(
        coopInvite,
        accept: true,
      );
      expect(accepted, isTrue);
      expect(mockHttpClient.lastRpcName, 'respond_coop_invite');
      expect(mockHttpClient.lastRpcBody, {
        'p_invite_id': 'uuid-coop-1',
        'p_accept': true,
      });

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('saved_computers')!;
      expect(saved, hasLength(1));
      final computer = ComputerDetails.fromJson(jsonDecode(saved.single));
      expect(computer.uuid, 'coop-pc-uuid');
      expect(computer.coopRole, 'coop_pad');
      expect(computer.isCoopTemporary, isTrue);
      expect(computer.isCloud, isTrue);

      await Future<void>.delayed(Duration.zero);
      expect(pairingClient.requests, 1);

      final serverInvite = CloudPendingInvite(
        isCoop: false,
        inviteId: 'uuid-srv-1',
        ownerEmail: 'friend@test.com',
        serverName: 'Perm PC',
        serverUrl: 'https://192.168.1.51:47990',
        role: 'viewer',
      );
      final declined = await CloudSyncService.instance.respondToInvite(
        serverInvite,
        accept: false,
      );
      expect(declined, isTrue);
      expect(mockHttpClient.lastRpcName, 'respond_server_invite');
      expect(mockHttpClient.lastRpcBody, {
        'p_invite_id': 'uuid-srv-1',
        'p_accept': false,
      });
    });

    test('permanent share takes precedence over coop and expired coop is removed', () async {
      final futureIso = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 2))
          .toIso8601String();
      final pastIso = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 2))
          .toIso8601String();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('saved_computers', [
        jsonEncode(
          ComputerDetails(
            uuid: 'stale-coop-uuid',
            name: 'Revoked Coop PC',
            localAddress: '192.168.1.88',
            serverCert: 'STALE-FP',
            isCloud: true,
            coopRole: 'coop_pad',
            coopExpiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          ).toJson(),
        ),
      ]);

      mockHttpClient.sharedRows = [
        {
          'server_url': 'https://192.168.1.60:47990',
          'server_name': 'Perm + Coop PC',
          'server_uuid': 'perm-uuid',
          'cert_fingerprint': 'PERM-FP',
          'local_addresses': ['192.168.1.60'],
          'role': 'operator',
          'owner_email': 'host@test.com',
        },
      ];
      mockHttpClient.coopSharedRows = [
        {
          'server_url': 'https://192.168.1.60:47990',
          'server_name': 'Perm + Coop PC',
          'server_uuid': 'perm-uuid',
          'cert_fingerprint': 'PERM-FP',
          'local_addresses': ['192.168.1.60'],
          'role': 'viewer',
          'owner_email': 'host@test.com',
          'expires_at': futureIso,
        },
        {
          'server_url': 'https://192.168.1.61:47990',
          'server_name': 'Expired Coop',
          'server_uuid': 'expired-coop',
          'cert_fingerprint': 'EXP-FP',
          'local_addresses': ['192.168.1.61'],
          'role': 'coop_pad',
          'owner_email': 'host@test.com',
          'expires_at': pastIso,
        },
      ];

      CloudSyncService.instance.pairingClientFactoryForTest = (_) =>
          _CountingPairingClient();

      expect(await CloudSyncService.instance.pullConfigFromSupabase(), isTrue);

      final saved = prefs.getStringList('saved_computers')!;
      expect(saved, hasLength(1));
      final kept = ComputerDetails.fromJson(jsonDecode(saved.single));
      expect(kept.uuid, 'perm-uuid');
      expect(kept.coopRole, isNull);
      expect(kept.coopExpiresAt, isNull);
      expect(kept.isCoopTemporary, isFalse);
    });

    test('derives nvhttp ports from a non-default server_url port base', () async {
      final prefs = await SharedPreferences.getInstance();
      // Existing entry still holds the default ports learned on the LAN.
      await prefs.setStringList('saved_computers', [
        jsonEncode(
          ComputerDetails(
            uuid: 'existing-uuid',
            name: 'Moved PC',
            localAddress: '192.168.1.70',
            serverCert: 'MOVED-FP',
            httpsPort: 47984,
            externalPort: 47989,
          ).toJson(),
        ),
      ]);
      mockHttpClient.sharedRows = [
        {
          'server_url': 'https://192.168.1.70:49990',
          'server_name': 'Moved PC',
          'server_uuid': 'existing-uuid',
          'cert_fingerprint': 'MOVED-FP',
          'local_addresses': ['192.168.1.70'],
          'external_address': '203.0.113.9:49990',
          'role': 'admin',
          'owner_email': 'host@test.com',
        },
        {
          'server_url': 'https://192.168.1.71:50990',
          'server_name': 'New PC',
          'server_uuid': 'new-uuid',
          'cert_fingerprint': 'NEW-FP',
          'local_addresses': ['192.168.1.71'],
          'role': 'admin',
          'owner_email': 'host@test.com',
        },
      ];
      CloudSyncService.instance.pairingClientFactoryForTest = (_) =>
          _CountingPairingClient();

      expect(await CloudSyncService.instance.pullConfigFromSupabase(), isTrue);

      final byUuid = {
        for (final raw in prefs.getStringList('saved_computers')!)
          (ComputerDetails.fromJson(jsonDecode(raw))).uuid:
              ComputerDetails.fromJson(jsonDecode(raw)),
      };
      expect(byUuid['existing-uuid']!.httpsPort, 49984);
      expect(byUuid['existing-uuid']!.externalPort, 49989);
      expect(byUuid['existing-uuid']!.configHttpsPort, 49990);
      expect(byUuid['new-uuid']!.httpsPort, 50984);
      expect(byUuid['new-uuid']!.externalPort, 50989);
    });
  });

  group('Guest links RPCs', () {
    test('redeemGuestLink sends p_code and maps every outcome', () async {
      mockHttpClient.guestRpcResult = {
        'success': true,
        'id': 'inv-1',
        'status': 'requested',
        'server_url': 'https://host.local:47990',
        'server_name': 'Host Rig',
        'role': 'coop_pad',
        'expires_at': '2026-11-27T20:00:00Z',
      };
      final requested = await CloudSyncService.instance.redeemGuestLink(
        'ABCDE-FGHJK',
      );
      expect(mockHttpClient.lastRpcName, 'redeem_guest_link');
      expect(mockHttpClient.lastRpcBody, {'p_code': 'ABCDE-FGHJK'});
      expect(requested.outcome, GuestRedeemOutcome.requested);
      expect(requested.inviteId, 'inv-1');
      expect(requested.serverName, 'Host Rig');

      mockHttpClient.guestRpcResult = {'success': true, 'status': 'active'};
      expect(
        (await CloudSyncService.instance.redeemGuestLink('ABCDE-FGHJK')).outcome,
        GuestRedeemOutcome.active,
      );

      for (final (error, outcome) in [
        ('verify_email', GuestRedeemOutcome.verifyEmail),
        ('invalid_or_expired', GuestRedeemOutcome.invalidOrExpired),
        ('already_has_access', GuestRedeemOutcome.alreadyHasAccess),
        ('boom', GuestRedeemOutcome.error),
      ]) {
        mockHttpClient.guestRpcResult = {'success': false, 'error': error};
        expect(
          (await CloudSyncService.instance.redeemGuestLink('ABCDE-FGHJK')).outcome,
          outcome,
        );
      }
    });

    test('guest request status read and cancel target the invite row', () async {
      mockHttpClient.guestRequestRows = [
        {'status': 'declined'},
      ];
      expect(
        await CloudSyncService.instance.guestRequestStatus('inv-1'),
        'declined',
      );
      expect(mockHttpClient.lastRestQuery, contains('id=eq.inv-1'));

      mockHttpClient.guestRequestRows = [];
      expect(await CloudSyncService.instance.guestRequestStatus('inv-1'), isNull);

      await CloudSyncService.instance.cancelGuestRequest('inv-1');
      expect(mockHttpClient.lastRestMethod, 'DELETE');
      expect(mockHttpClient.lastRestQuery, contains('id=eq.inv-1'));
    });

    test('manager RPCs send the documented parameters', () async {
      mockHttpClient.pendingGuestRows = [
        {
          'id': 'req-1',
          'server_url': 'https://host.local:47990',
          'server_name': 'Host Rig',
          'role': 'coop_pad',
          'guest_email': 'amigo@test.com',
          'expires_at': '2099-01-01T00:00:00Z',
        },
      ];
      final pending = await CloudSyncService.instance.pendingGuestRequests();
      expect(pending.single.id, 'req-1');
      expect(pending.single.guestEmail, 'amigo@test.com');

      expect(
        await CloudSyncService.instance.respondGuestRequest('req-1', approve: true),
        isTrue,
      );
      expect(mockHttpClient.lastRpcName, 'respond_guest_request');
      expect(mockHttpClient.lastRpcBody, {
        'p_invite_id': 'req-1',
        'p_approve': true,
      });

      expect(
        await CloudSyncService.instance.setAutoAcceptGuests('https://h:1', true),
        isTrue,
      );
      expect(mockHttpClient.lastRpcName, 'set_auto_accept_guests');
      expect(mockHttpClient.lastRpcBody, {
        'p_server_url': 'https://h:1',
        'p_enabled': true,
      });

      mockHttpClient.guestRpcResult = {
        'success': true,
        'id': 'link-1',
        'code': 'ABCDE-FGHJK',
        'expires_at': '2026-11-27T20:00:00Z',
      };
      final link = await CloudSyncService.instance.createGuestLink('https://h:1');
      expect(mockHttpClient.lastRpcName, 'create_guest_link');
      expect(mockHttpClient.lastRpcBody, {
        'p_server_url': 'https://h:1',
        'p_role': 'coop_pad',
      });
      expect(link!.code, 'ABCDE-FGHJK');

      mockHttpClient.guestRpcResult = {'success': false, 'error': 'not_allowed'};
      expect(await CloudSyncService.instance.createGuestLink('https://h:1'), isNull);
      expect(
        await CloudSyncService.instance.respondGuestRequest('req-1', approve: false),
        isFalse,
      );
    });

    test('pull marks own servers and co-owned servers as guest-managed', () async {
      mockHttpClient.ownedRows = [
        {
          'id': 'row-own',
          'user_id': 'mock-guest-uuid',
          'server_url': 'https://192.168.1.80:47990',
          'server_name': 'My PC',
          'server_uuid': 'own-uuid',
          'cert_fingerprint': 'OWN-FP',
          'local_addresses': ['192.168.1.80'],
          'auto_accept_guests': true,
        },
      ];
      mockHttpClient.sharedRows = [
        {
          'server_url': 'https://192.168.1.81:47990',
          'server_name': 'Co-owned PC',
          'server_uuid': 'co-uuid',
          'cert_fingerprint': 'CO-FP',
          'local_addresses': ['192.168.1.81'],
          'permissions': ['launch', 'guests'],
          'auto_accept_guests': false,
        },
        {
          'server_url': 'https://192.168.1.82:47990',
          'server_name': 'Launch-only PC',
          'server_uuid': 'launch-uuid',
          'cert_fingerprint': 'LAUNCH-FP',
          'local_addresses': ['192.168.1.82'],
          'permissions': ['launch'],
        },
      ];
      CloudSyncService.instance.pairingClientFactoryForTest = (_) =>
          _CountingPairingClient();

      expect(await CloudSyncService.instance.pullConfigFromSupabase(), isTrue);

      final prefs = await SharedPreferences.getInstance();
      final byUuid = {
        for (final raw in prefs.getStringList('saved_computers')!)
          ComputerDetails.fromJson(jsonDecode(raw)).uuid:
              ComputerDetails.fromJson(jsonDecode(raw)),
      };
      final own = byUuid['own-uuid']!;
      expect(own.managesGuests, isTrue);
      expect(own.isCloudOwner, isTrue);
      expect(own.autoAcceptGuests, isTrue);
      expect(own.cloudServerUrl, 'https://192.168.1.80:47990');
      final co = byUuid['co-uuid']!;
      expect(co.managesGuests, isTrue);
      expect(co.isCloudOwner, isFalse);
      expect(co.permissions, ['launch', 'guests']);
      expect(byUuid['launch-uuid']!.managesGuests, isFalse);
    });
  });

  group('PendingInvitesSection widget', () {
    testWidgets('renders invites and dispatches accept and decline callbacks', (
      tester,
    ) async {
      final calls = <(String, bool)>[];
      final results = <(String, bool, bool)>[];

      final invites = [
        CloudPendingInvite(
          isCoop: true,
          inviteId: 'coop-1',
          ownerEmail: 'host@test.com',
          serverName: 'Host Rig',
          serverUrl: 'https://192.168.1.50:47990',
          role: 'coop_pad',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 3)),
        ),
        const CloudPendingInvite(
          isCoop: false,
          inviteId: 'perm-1',
          ownerEmail: 'alice@test.com',
          serverName: 'Alice PC',
          serverUrl: 'https://192.168.1.51:47990',
          role: 'viewer',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('es')],
          home: Scaffold(
            body: PendingInvitesSection(
              invites: invites,
              isLoading: false,
              accent: Colors.deepPurpleAccent,
              isLight: false,
              onRespond: (invite, {required accept}) async {
                calls.add((invite.inviteId, accept));
                return true;
              },
              onResult: (invite, accepted, ok) {
                results.add((invite.inviteId, accepted, ok));
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Co-Op & Server Invites'), findsOneWidget);
      expect(find.text('Host Rig'), findsOneWidget);
      expect(find.text('Alice PC'), findsOneWidget);
      expect(find.text('4h Co-Op'), findsOneWidget);
      expect(find.text('Server Share'), findsOneWidget);

      await tester.tap(find.text('Accept').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Decline').last);
      await tester.pumpAndSettle();

      expect(calls, [('coop-1', true), ('perm-1', false)]);
      expect(results, [('coop-1', true, true), ('perm-1', false, true)]);
    });
  });
}
