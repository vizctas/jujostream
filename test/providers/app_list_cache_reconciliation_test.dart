import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/computer_details.dart';
import 'package:jujostream/models/nv_app.dart';
import 'package:jujostream/providers/app_list_provider.dart';
import 'package:jujostream/providers/plugins_provider.dart';
import 'package:jujostream/services/http_api/nv_http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SequencedAppListClient extends NvHttpClient {
  _SequencedAppListClient(this.responses);

  final List<List<NvApp>> responses;
  int calls = 0;

  @override
  Future<List<NvApp>> getAppList(
    String address, {
    int httpsPort = NvHttpClient.defaultHttpsPort,
    String? expectedServerCert,
  }) async {
    final index = calls < responses.length ? calls : responses.length - 1;
    calls++;
    lastAppListFailure = AppListFailure.none;
    return responses[index];
  }

  @override
  Future<ComputerDetails?> getServerInfoHttps(
    String address, {
    int httpsPort = NvHttpClient.defaultHttpsPort,
    int httpPort = NvHttpClient.defaultHttpPort,
    Duration timeout = const Duration(seconds: 5),
    String? expectedServerCert,
  }) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a complete server list removes stale cached apps', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _SequencedAppListClient([
      [
        NvApp(appId: 10, appName: 'Removed game'),
        NvApp(appId: 20, appName: 'Installed game'),
      ],
      [NvApp(appId: 20, appName: 'Installed game')],
    ]);
    final provider = AppListProvider(
      await PluginsProvider.load(),
      httpClient: client,
    );
    final computer = ComputerDetails(
      uuid: 'server-1',
      localAddress: '192.168.3.6',
      pairState: PairState.paired,
    );

    await provider.loadApps(computer);
    expect(provider.apps.map((app) => app.appName), contains('Removed game'));

    await provider.loadApps(computer, silent: true);

    expect(provider.apps.map((app) => app.appName), ['Installed game']);
    provider.dispose();
  });

  test(
    'a busy-session single-app response preserves the complete list',
    () async {
      SharedPreferences.setMockInitialValues({});
      final client = _SequencedAppListClient([
        [
          NvApp(appId: 10, appName: 'Running game'),
          NvApp(appId: 20, appName: 'Other game'),
        ],
        [NvApp(appId: 10, appName: 'Running game', isRunning: true)],
      ]);
      final provider = AppListProvider(
        await PluginsProvider.load(),
        httpClient: client,
      );
      final computer = ComputerDetails(
        uuid: 'server-1',
        localAddress: '192.168.3.6',
        pairState: PairState.paired,
      );

      await provider.loadApps(computer);
      computer.runningGameId = 10;
      await provider.loadApps(computer, silent: true);

      expect(provider.apps, hasLength(2));
      expect(
        provider.apps.singleWhere((app) => app.appId == 10).isRunning,
        isTrue,
      );
      provider.dispose();
    },
  );
}
