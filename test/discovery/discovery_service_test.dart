import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/services/discovery/discovery_service.dart';
import 'package:nsd/nsd.dart';

void main() {
  test('starts one NSD session and requests resolved IP addresses', () async {
    final discovery = Discovery('test-discovery');
    var starts = 0;
    IpLookupType? requestedLookup;

    final service = DiscoveryService(
      discoveryStarter:
          (serviceType, {required autoResolve, required ipLookupType}) async {
            starts++;
            requestedLookup = ipLookupType;
            return discovery;
          },
      discoveryStopper: (_) async {},
    );

    await Future.wait([service.startDiscovery(), service.startDiscovery()]);

    expect(starts, 1);
    expect(requestedLookup, IpLookupType.any);
    service.dispose();
  });

  test('uses resolved IPv4 and rejects loopback fallback', () async {
    final discovery = Discovery('test-discovery');
    final service = DiscoveryService(
      discoveryStarter:
          (serviceType, {required autoResolve, required ipLookupType}) async =>
              discovery,
      discoveryStopper: (_) async {},
    );
    await service.startDiscovery();

    discovery.add(
      Service(
        name: 'JulyTower',
        host: 'JUJOPC.local.',
        port: 47989,
        addresses: [InternetAddress('192.168.3.6')],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.discoveredComputers, hasLength(1));
    expect(service.discoveredComputers.single.localAddress, '192.168.3.6');

    discovery.add(
      const Service(name: 'Invalid loopback', host: '127.0.0.1', port: 47989),
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.discoveredComputers, hasLength(1));
    service.dispose();
  });
}
