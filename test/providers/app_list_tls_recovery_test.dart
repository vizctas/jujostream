import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/computer_details.dart';
import 'package:jujostream/models/nv_app.dart';
import 'package:jujostream/providers/app_list_provider.dart';
import 'package:jujostream/providers/plugins_provider.dart';
import 'package:jujostream/services/http_api/nv_http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RotatedIdentityHttpClient extends NvHttpClient {
  int calls = 0;

  @override
  Future<List<NvApp>> getAppList(
    String address, {
    int httpsPort = NvHttpClient.defaultHttpsPort,
    String? expectedServerCert,
  }) async {
    calls++;
    if (calls == 1) {
      lastAppListFailure = AppListFailure.serverIdentityRejected;
      return const [];
    }
    lastAppListFailure = AppListFailure.none;
    return [NvApp(appId: 1, appName: 'Recovered Game')];
  }

  @override
  Future<ComputerDetails?> getServerInfoHttps(
    String address, {
    int httpsPort = NvHttpClient.defaultHttpsPort,
    int httpPort = NvHttpClient.defaultHttpPort,
    Duration timeout = const Duration(seconds: 5),
    String? expectedServerCert,
  }) async {
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reloads apps after cloud verifies a rotated server identity', () async {
    SharedPreferences.setMockInitialValues({});
    final plugins = await PluginsProvider.load();
    final httpClient = _RotatedIdentityHttpClient();
    var recoveries = 0;
    final provider = AppListProvider(
      plugins,
      httpClient: httpClient,
      recoverServerIdentity: (computer) async {
        recoveries++;
        computer.serverCert = 'new-cloud-fingerprint';
        return true;
      },
    );
    final computer = ComputerDetails(
      uuid: 'server-1',
      localAddress: '192.168.3.6',
      serverCert: 'old-fingerprint',
      pairState: PairState.paired,
    );

    await provider.loadApps(computer);
    for (var attempt = 0; attempt < 100 && provider.apps.isEmpty; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    expect(recoveries, 1);
    expect(httpClient.calls, 2);
    expect(
      provider.apps,
      isNotEmpty,
      reason: 'error=${provider.error}, cert=${computer.serverCert}',
    );
    expect(provider.apps.single.appName, 'Recovered Game');
    expect(provider.error, isNull);
  });

  test(
    'requires explicit pairing when cloud cannot verify the new identity',
    () async {
      SharedPreferences.setMockInitialValues({});
      final plugins = await PluginsProvider.load();
      final httpClient = _RotatedIdentityHttpClient();
      final provider = AppListProvider(
        plugins,
        httpClient: httpClient,
        recoverServerIdentity: (_) async => false,
      );

      await provider.loadApps(
        ComputerDetails(
          uuid: 'server-1',
          localAddress: '192.168.3.6',
          serverCert: 'old-fingerprint',
          pairState: PairState.paired,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(httpClient.calls, 1);
      expect(provider.apps, isEmpty);
      expect(provider.error, contains('Server identity changed'));
      expect(provider.error, contains('pair this device again locally'));
    },
  );
}
