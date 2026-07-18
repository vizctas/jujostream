import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/computer_details.dart';
import 'package:jujostream/providers/computer_provider.dart';
import 'package:jujostream/services/discovery/discovery_service.dart';
import 'package:nsd/nsd.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ComputerProvider makeProvider({required Future<bool> Function() revoke}) {
    final service = DiscoveryService(
      discoveryStarter:
          (serviceType, {required autoResolve, required ipLookupType}) async =>
              Discovery('revocation-test'),
    );
    return ComputerProvider(
      discoveryService: service,
      unpairRequest: (_) => revoke(),
    );
  }

  Future<ComputerProvider> loadProvider(
    WidgetTester tester, {
    required Future<bool> Function() revoke,
  }) async {
    final computer =
        ComputerDetails(
            uuid: 'client-device',
            name: 'JulyTower',
            localAddress: '192.168.3.6',
          )
          ..pairState = PairState.paired
          ..serverCert = 'pinned-server-cert';
    SharedPreferences.setMockInitialValues({
      'saved_computers': [jsonEncode(computer.toJson())],
    });
    final provider = makeProvider(revoke: revoke);
    await tester.pump();
    await tester.pump();
    return provider;
  }

  testWidgets('successful revocation removes the local server record', (
    tester,
  ) async {
    final provider = await loadProvider(tester, revoke: () async => true);
    final computer = provider.computers.single;

    expect(await provider.revokeAndForgetComputer(computer), isTrue);
    expect(provider.computers, isEmpty);

    provider.dispose();
  });

  testWidgets('failed revocation preserves the local server record', (
    tester,
  ) async {
    final provider = await loadProvider(tester, revoke: () async => false);
    final computer = provider.computers.single;

    expect(await provider.revokeAndForgetComputer(computer), isFalse);
    expect(provider.computers, hasLength(1));
    expect(provider.computers.single.isPaired, isTrue);

    provider.dispose();
  });
}
