import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jujostream/models/computer_details.dart';
import 'package:jujostream/providers/computer_provider.dart';
import 'package:jujostream/services/discovery/discovery_service.dart';
import 'package:jujostream/services/http_api/nv_http_client.dart';
import 'package:nsd/nsd.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RouterSharedWanHttpClient extends http.BaseClient {
  final Set<String> onlineIps;
  final Map<String, String> serverXmlByIp;

  _RouterSharedWanHttpClient({
    required this.onlineIps,
    required this.serverXmlByIp,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final host = request.url.host;
    if (!onlineIps.contains(host) || !serverXmlByIp.containsKey(host)) {
      throw Exception('Connection refused: $host');
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(serverXmlByIp[host]!)),
      200,
      request: request,
    );
  }
}

String _serverXml({
  required String name,
  required String uuid,
  required String localIp,
  required String externalIp,
  int pairStatus = 1,
}) => '''
<root status_code="200">
  <hostname>$name</hostname>
  <uniqueid>$uuid</uniqueid>
  <mac>D8:BB:C1:12:34:56</mac>
  <LocalIP>$localIp</LocalIP>
  <ExternalIP>$externalIp</ExternalIP>
  <HttpsPort>47984</HttpsPort>
  <ExternalPort>47989</ExternalPort>
  <PairStatus>$pairStatus</PairStatus>
</root>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ComputerProvider createProvider(
    _RouterSharedWanHttpClient fakeClient,
  ) {
    final discovery = DiscoveryService(
      discoveryStarter:
          (serviceType, {required autoResolve, required ipLookupType}) async =>
              Discovery('shared-wan-test'),
    );
    final nvHttp = NvHttpClient(
      httpClient: fakeClient,
      httpsClientFactory: (_) => fakeClient,
    );
    return ComputerProvider(
      discoveryService: discovery,
      httpClient: nvHttp,
    );
  }

  testWidgets(
    'deduplicates persisted entries, clears contaminated activeAddress, and rejects shared WAN identity swap',
    (tester) async {
      final julyUnpairedDup = ComputerDetails(
        uuid: 'UUID-JULY',
        name: 'JulyTower',
        localAddress: '192.168.3.30',
        remoteAddress: '190.32.76.233',
      );
      final julyPaired =
          ComputerDetails(
              uuid: 'UUID-JULY',
              name: 'JulyTower',
              localAddress: '192.168.3.30',
              remoteAddress: '190.32.76.233',
              activeAddress: '192.168.3.6', // contaminated with peer LAN IP
              macAddress: 'AA:BB:CC:DD:EE:01',
            )
            ..pairState = PairState.paired
            ..serverCert = 'CERT-JULY';
      final jujoPaired =
          ComputerDetails(
              uuid: 'UUID-JUJO',
              name: 'JUJOPC',
              localAddress: '192.168.3.6',
              remoteAddress: '190.32.76.233',
              activeAddress: '192.168.3.6',
              macAddress: 'AA:BB:CC:DD:EE:02',
            )
            ..pairState = PairState.paired
            ..serverCert = 'CERT-JUJO';

      SharedPreferences.setMockInitialValues({
        'saved_computers': [
          jsonEncode(julyUnpairedDup.toJson()),
          jsonEncode(julyPaired.toJson()),
          jsonEncode(jujoPaired.toJson()),
        ],
      });

      final fakeClient = _RouterSharedWanHttpClient(
        onlineIps: {'192.168.3.6', '190.32.76.233'},
        serverXmlByIp: {
          '192.168.3.6': _serverXml(
            name: 'JUJOPC',
            uuid: 'UUID-JUJO',
            localIp: '192.168.3.6',
            externalIp: '190.32.76.233',
          ),
          // Router UPnP currently forwards shared WAN IP to JUJOPC while JulyTower is off
          '190.32.76.233': _serverXml(
            name: 'JUJOPC',
            uuid: 'UUID-JUJO',
            localIp: '192.168.3.6',
            externalIp: '190.32.76.233',
          ),
        },
      );

      final provider = createProvider(fakeClient);
      await tester.pump();
      await tester.pump();

      expect(provider.computers, hasLength(2));
      final loadedJuly = provider.computers.firstWhere(
        (c) => c.uuid == 'UUID-JULY',
      );
      expect(loadedJuly.isPaired, isTrue);
      expect(loadedJuly.activeAddress, '192.168.3.30');

      final firstPollState = await provider.pollComputer(loadedJuly);
      expect(firstPollState, isNot(ComputerState.online));
      final secondPollState = await provider.pollComputer(loadedJuly);
      expect(secondPollState, ComputerState.offline);
      expect(loadedJuly.activeAddress, '192.168.3.30');
      expect(
        provider.computers.where((c) => c.uuid == 'UUID-JULY').single.name,
        'JulyTower',
      );
      expect(provider.computers.where((c) => c.uuid == 'UUID-JUJO'), hasLength(1));

      provider.dispose();
    },
  );

  testWidgets(
    'allows JulyTower LAN poll even if a stale conflicting record holds same localAddress and resolves WAN per-UUID',
    (tester) async {
      final july =
          ComputerDetails(
              uuid: 'UUID-JULY',
              name: 'JulyTower',
              localAddress: '192.168.3.30',
              remoteAddress: '190.32.76.233',
              activeAddress: '192.168.3.30',
            )
            ..pairState = PairState.paired
            ..serverCert = 'CERT-JULY';
      final poisonedJujo =
          ComputerDetails(
              uuid: 'UUID-JUJO',
              name: 'JUJOPC',
              localAddress: '192.168.3.30', // stale contaminated local IP
              remoteAddress: '190.32.76.233',
            )
            ..pairState = PairState.paired
            ..serverCert = 'CERT-JUJO';

      SharedPreferences.setMockInitialValues({
        'saved_computers': [
          jsonEncode(july.toJson()),
          jsonEncode(poisonedJujo.toJson()),
        ],
      });

      // Simulate mobile data: LAN unreachable, UPnP points shared WAN to JulyTower
      final fakeClient = _RouterSharedWanHttpClient(
        onlineIps: {'190.32.76.233'},
        serverXmlByIp: {
          '190.32.76.233': _serverXml(
            name: 'JulyTower',
            uuid: 'UUID-JULY',
            localIp: '192.168.3.30',
            externalIp: '190.32.76.233',
          ),
        },
      );

      final provider = createProvider(fakeClient);
      await tester.pump();
      await tester.pump();

      expect(
        await provider.pollComputer(
          provider.computers.firstWhere((c) => c.uuid == 'UUID-JULY'),
        ),
        ComputerState.online,
      );
      final updatedJuly = provider.computers.firstWhere(
        (c) => c.uuid == 'UUID-JULY',
      );
      expect(updatedJuly.activeAddress, '190.32.76.233');
      expect(updatedJuly.localAddress, '192.168.3.30');

      final jujo = provider.computers.firstWhere((c) => c.uuid == 'UUID-JUJO');
      expect(await provider.pollComputer(jujo), isNot(ComputerState.online));
      expect(await provider.pollComputer(jujo), ComputerState.offline);
      expect(jujo.name, 'JUJOPC');

      provider.dispose();
    },
  );

  testWidgets(
    'accepts its own WAN answer when polled through a stale reference after a list reload',
    (tester) async {
      ComputerDetails paired(String uuid, String name, String ip, String cert) =>
          ComputerDetails(
              uuid: uuid,
              name: name,
              localAddress: ip,
              remoteAddress: '190.32.76.233',
              activeAddress: '190.32.76.233',
            )
            ..pairState = PairState.paired
            ..serverCert = cert;
      final jujo = paired('UUID-JUJO', 'JUJOPC', '192.168.3.6', 'CERT-JUJO');
      SharedPreferences.setMockInitialValues({
        'saved_computers': [
          jsonEncode(paired('UUID-JULY', 'JulyTower', '192.168.3.30', 'CERT-JULY').toJson()),
          jsonEncode(jujo.toJson()),
        ],
      });

      // Mobile data: only the shared WAN IP answers, and it reaches JUJOPC.
      final provider = createProvider(
        _RouterSharedWanHttpClient(
          onlineIps: {'190.32.76.233'},
          serverXmlByIp: {
            '190.32.76.233': _serverXml(
              name: 'JUJOPC',
              uuid: 'UUID-JUJO',
              localIp: '192.168.3.6',
              externalIp: '190.32.76.233',
            ),
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      // Cloud sync reloads the list mid-poll, so the poller holds an equal but non-identical object.
      final stale = ComputerDetails.fromJson(jujo.toJson());
      expect(await provider.pollComputer(stale), ComputerState.online);

      provider.dispose();
    },
  );

  testWidgets(
    'keeps the HTTPS-learned host permission across an HTTP-only poll',
    (tester) async {
      final guestBits = 0x1000000 | 0x2000000 | 256;
      final july =
          ComputerDetails(
              uuid: 'UUID-JULY',
              name: 'JulyTower',
              localAddress: '192.168.3.30',
              activeAddress: '192.168.3.30',
            )
            ..pairState = PairState.paired
            ..serverCert = 'CERT-JULY'
            ..pairStatusFromHttps = true
            ..hostPermission = guestBits;
      SharedPreferences.setMockInitialValues({
        'saved_computers': [jsonEncode(july.toJson())],
      });

      final plain = _RouterSharedWanHttpClient(
        onlineIps: {'192.168.3.30'},
        serverXmlByIp: {
          '192.168.3.30': _serverXml(
            name: 'JulyTower',
            uuid: 'UUID-JULY',
            localIp: '192.168.3.30',
            externalIp: '190.32.76.233',
          ),
        },
      );
      // HTTPS fails (e.g. TLS hiccup), so the poll falls back to plain HTTP.
      final provider = ComputerProvider(
        discoveryService: DiscoveryService(
          discoveryStarter:
              (serviceType, {required autoResolve, required ipLookupType}) async =>
                  Discovery('perm-test'),
        ),
        httpClient: NvHttpClient(
          httpClient: plain,
          httpsClientFactory: (_) => _RouterSharedWanHttpClient(
            onlineIps: const {},
            serverXmlByIp: const {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final c = provider.computers.single;
      expect(await provider.pollComputer(c), ComputerState.online);
      final after = provider.computers.single;
      expect(after.hostPermission, guestBits);
      expect(after.canLaunchApps, isFalse);

      provider.dispose();
    },
  );

  testWidgets(
    'relays Wake-on-LAN through an awake paired server on the same subnet',
    (tester) async {
      final july =
          ComputerDetails(
              uuid: 'UUID-JULY',
              name: 'JulyTower',
              localAddress: '192.168.3.30',
              remoteAddress: '190.32.76.233',
              macAddress: '3C:7C:3F:17:3F:83',
            )
            ..pairState = PairState.paired
            ..serverCert = 'CERT-JULY';
      final jujo =
          ComputerDetails(
              uuid: 'UUID-JUJO',
              name: 'JUJOPC',
              localAddress: '192.168.3.6',
              remoteAddress: '190.32.76.233',
            )
            ..pairState = PairState.paired
            ..serverCert = 'CERT-JUJO';
      final elsewhere =
          ComputerDetails(
              uuid: 'UUID-OTHER',
              name: 'OtherLan',
              localAddress: '10.0.0.5',
            )
            ..pairState = PairState.paired
            ..serverCert = 'CERT-OTHER';
      SharedPreferences.setMockInitialValues({
        'saved_computers': [
          jsonEncode(july.toJson()),
          jsonEncode(jujo.toJson()),
          jsonEncode(elsewhere.toJson()),
        ],
      });

      final relayCalls = <(String, Map<String, Object>)>[];
      final provider = ComputerProvider(
        discoveryService: DiscoveryService(
          discoveryStarter:
              (serviceType, {required autoResolve, required ipLookupType}) async =>
                  Discovery('wol-relay-test'),
        ),
        httpClient: NvHttpClient(
          httpClient: _RouterSharedWanHttpClient(
            onlineIps: {'192.168.3.6', '10.0.0.5'},
            serverXmlByIp: {
              '192.168.3.6': _serverXml(
                name: 'JUJOPC',
                uuid: 'UUID-JUJO',
                localIp: '192.168.3.6',
                externalIp: '190.32.76.233',
              ),
              '10.0.0.5': _serverXml(
                name: 'OtherLan',
                uuid: 'UUID-OTHER',
                localIp: '10.0.0.5',
                externalIp: '203.0.113.1',
              ),
            },
          ),
        ),
        wolRelayRequest: (relay, body) async {
          relayCalls.add((relay.uuid, body));
          return true;
        },
      );
      await tester.pump();
      await tester.pump();

      ComputerDetails byUuid(String u) =>
          provider.computers.firstWhere((c) => c.uuid == u);
      expect(
        await provider.pollComputer(byUuid('UUID-JUJO')),
        ComputerState.online,
      );
      expect(
        await provider.pollComputer(byUuid('UUID-OTHER')),
        ComputerState.online,
      );

      await tester.runAsync(() => provider.sendWakeOnLan(byUuid('UUID-JULY')));

      expect(relayCalls, hasLength(1));
      expect(relayCalls.single.$1, 'UUID-JUJO');
      expect(relayCalls.single.$2, {
        'mac': '3C:7C:3F:17:3F:83',
        'broadcast': '192.168.3.255',
        'port': 9,
      });

      provider.dispose();
    },
  );
}
