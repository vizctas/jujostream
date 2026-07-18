import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/providers/computer_provider.dart';
import 'package:jujostream/services/discovery/discovery_service.dart';
import 'package:nsd/nsd.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://discovery.test.supabase.co',
      publishableKey: 'test-key',
    );
  });

  testWidgets('provider owns discovery across application lifecycle', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var starts = 0;
    var stops = 0;
    final service = DiscoveryService(
      discoveryStarter:
          (serviceType, {required autoResolve, required ipLookupType}) async {
            starts++;
            return Discovery('discovery-$starts');
          },
      discoveryStopper: (_) async => stops++,
    );

    final provider = ComputerProvider(discoveryService: service);
    await tester.pump();
    expect(starts, 1);

    provider.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump();
    expect(stops, 1);

    provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(starts, 2);

    provider.dispose();
    await tester.pump();
  });
}
