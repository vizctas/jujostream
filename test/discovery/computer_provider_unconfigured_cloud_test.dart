import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/providers/computer_provider.dart';
import 'package:jujostream/services/discovery/discovery_service.dart';
import 'package:nsd/nsd.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cloud session lookup is skipped when Cloud is not configured', () {
    var reads = 0;

    expect(
      isCloudSessionActive(
        cloudConfigured: false,
        readSession: () {
          reads++;
          return true;
        },
      ),
      isFalse,
    );
    expect(reads, 0);
  });

  testWidgets(
    'local launcher remains available when Jujo Cloud has not initialized',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = DiscoveryService(
        discoveryStarter:
            (
              serviceType, {
              required autoResolve,
              required ipLookupType,
            }) async => Discovery('unconfigured-cloud-test'),
      );
      final provider = ComputerProvider(discoveryService: service);

      await tester.pump();

      expect(() => provider.computers, returnsNormally);
      expect(provider.computers, isEmpty);

      provider.dispose();
    },
  );
}
