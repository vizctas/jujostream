import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/computer_details.dart';
import 'package:jujostream/providers/computer_provider.dart';
import 'package:jujostream/services/http_api/nv_http_client.dart';
import 'package:jujostream/services/network/wake_on_lan_service.dart';

void main() {
  group('WakeOnLanService & WAN Address Sanitization', () {
    test('isValidMac rejects placeholder and broadcast MACs', () {
      expect(WakeOnLanService.isValidMac(null), isFalse);
      expect(WakeOnLanService.isValidMac(''), isFalse);
      expect(WakeOnLanService.isValidMac('00:00:00:00:00:00'), isFalse);
      expect(WakeOnLanService.isValidMac('00-00-00-00-00-00'), isFalse);
      expect(WakeOnLanService.isValidMac('FF:FF:FF:FF:FF:FF'), isFalse);
      expect(WakeOnLanService.isValidMac('ff:ff:ff:ff:ff:ff'), isFalse);
      expect(WakeOnLanService.isValidMac('D8:BB:C1:12:34:56'), isTrue);
      expect(WakeOnLanService.isValidMac('d8-bb-c1-12-34-56'), isTrue);
    });

    test('cleanHost strips scheme, port, and path from WAN/LAN addresses', () {
      expect(WakeOnLanService.cleanHost('181.42.15.200:47990'), '181.42.15.200');
      expect(
        WakeOnLanService.cleanHost('https://181.42.15.200:47990/serverinfo'),
        '181.42.15.200',
      );
      expect(
        WakeOnLanService.cleanHost('my-host.local:47989'),
        'my-host.local',
      );
      expect(
        WakeOnLanService.cleanHost('[2001:db8::1]:47990'),
        '2001:db8::1',
      );
    });

    test('subnetBroadcastForIp computes /24 broadcast and ignores loopback', () {
      expect(
        WakeOnLanService.subnetBroadcastForIp('192.168.3.30'),
        '192.168.3.255',
      );
      expect(
        WakeOnLanService.subnetBroadcastForIp('192.168.3.30:47990'),
        '192.168.3.255',
      );
      expect(WakeOnLanService.subnetBroadcastForIp('127.0.0.1'), isNull);
      expect(WakeOnLanService.subnetBroadcastForIp('0.0.0.0'), isNull);
    });

    test('parseServerInfo ignores 00:00:00:00:00:00 MAC and cleans ExternalIP', () {
      final client = NvHttpClient();
      const xmlHttp = '''
<root status_code="200">
  <hostname>JulyTower</hostname>
  <uniqueid>UUID-JULY</uniqueid>
  <mac>00:00:00:00:00:00</mac>
  <LocalIP>192.168.3.30</LocalIP>
  <ExternalIP>181.42.15.200:47990</ExternalIP>
  <HttpsPort>47984</HttpsPort>
  <ExternalPort>47989</ExternalPort>
  <PairStatus>0</PairStatus>
</root>
''';
      final infoHttp = client.parseServerInfo(xmlHttp, '181.42.15.200:47990', 47989);
      expect(infoHttp.macAddress, isEmpty);
      expect(infoHttp.remoteAddress, '181.42.15.200');
      expect(infoHttp.activeAddress, '181.42.15.200');
      expect(infoHttp.localAddress, '192.168.3.30');

      const xmlHttps = '''
<root status_code="200">
  <hostname>JulyTower</hostname>
  <uniqueid>UUID-JULY</uniqueid>
  <mac>D8:BB:C1:12:34:56</mac>
  <LocalIP>192.168.3.30</LocalIP>
  <ExternalIP>181.42.15.200</ExternalIP>
  <HttpsPort>47984</HttpsPort>
  <ExternalPort>47989</ExternalPort>
  <PairStatus>1</PairStatus>
</root>
''';
      final infoHttps = client.parseServerInfo(xmlHttps, '192.168.3.30', 47984);
      expect(infoHttps.macAddress, 'D8:BB:C1:12:34:56');
      expect(infoHttps.remoteAddress, '181.42.15.200');
    });

    test('candidateAddresses strips port suffixes and deduplicates', () {
      final computer = ComputerDetails(
        localAddress: '192.168.3.30',
        remoteAddress: '181.42.15.200:47990',
        activeAddress: '192.168.3.30:47989',
      );
      expect(
        candidateAddresses(computer),
        <String>['192.168.3.30', '181.42.15.200'],
      );
    });

    test('ComputerDetails.fromJson sanitizes persisted port suffixes and zero MAC', () {
      final computer = ComputerDetails.fromJson({
        'uuid': 'u1',
        'name': 'JulyTower',
        'localAddress': '192.168.3.30',
        'remoteAddress': '181.42.15.200:47990',
        'macAddress': '00:00:00:00:00:00',
        'lastSeenAt': DateTime.now().toUtc().toIso8601String(),
      });
      expect(computer.remoteAddress, '181.42.15.200');
      expect(computer.macAddress, isEmpty);
      expect(computer.isCloudRecentlySeen, isTrue);
    });
  });
}
