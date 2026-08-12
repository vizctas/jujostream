import 'dart:async';

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

class _BlockingAppListClient extends NvHttpClient {
  _BlockingAppListClient(this.response);

  final List<NvApp> response;
  final Completer<void> release = Completer<void>();
  int calls = 0;

  @override
  Future<List<NvApp>> getAppList(
    String address, {
    int httpsPort = NvHttpClient.defaultHttpsPort,
    String? expectedServerCert,
  }) async {
    calls++;
    await release.future;
    lastAppListFailure = AppListFailure.none;
    return response;
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

  test(
    'same-server launcher re-entry keeps a fresh library in memory',
    () async {
      SharedPreferences.setMockInitialValues({});
      final client = _SequencedAppListClient([
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
      await provider.loadForLauncher(computer);

      expect(client.calls, 1);
      expect(provider.apps.single.appName, 'Installed game');
      expect(provider.isLoading, isFalse);
      provider.dispose();
    },
  );

  test(
    'automatic refresh respects TTL while forced refresh reconciles',
    () async {
      SharedPreferences.setMockInitialValues({});
      final client = _SequencedAppListClient([
        [NvApp(appId: 20, appName: 'Installed game')],
        [NvApp(appId: 20, appName: 'Installed game', isRunning: true)],
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
      await provider.refresh();
      expect(client.calls, 1);

      await provider.refresh(force: true);
      expect(client.calls, 2);
      expect(provider.apps.single.isRunning, isTrue);
      provider.dispose();
    },
  );

  test(
    'cold provider exposes persisted apps before network completes',
    () async {
      SharedPreferences.setMockInitialValues({
        'appCacheV1_server-1':
            '[{"appId":20,"appName":"Cached game","isRunning":false,'
            '"isHdrSupported":false,"posterUrl":"https://cached/poster"}]',
      });
      final client = _BlockingAppListClient([
        NvApp(appId: 20, appName: 'Fresh game'),
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

      final loading = provider.loadForLauncher(computer);
      for (var i = 0; i < 20 && client.calls == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(client.calls, 1);
      expect(provider.apps.single.appName, 'Cached game');
      expect(provider.isLoading, isFalse);

      client.release.complete();
      await loading;
      expect(provider.apps.single.appName, 'Fresh game');
      provider.dispose();
    },
  );

  test(
    'stale launcher refresh reconciles in place without an empty frame',
    () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime.utc(2026, 8, 11, 20);
      final client = _SequencedAppListClient([
        [NvApp(appId: 20, appName: 'Installed game')],
        [
          NvApp(appId: 20, appName: 'Installed game'),
          NvApp(appId: 30, appName: 'New game'),
        ],
      ]);
      final provider = AppListProvider(
        await PluginsProvider.load(),
        httpClient: client,
        clock: () => now,
      );
      final computer = ComputerDetails(
        uuid: 'server-1',
        localAddress: '192.168.3.6',
        pairState: PairState.paired,
      );
      final observedLengths = <int>[];
      provider.addListener(() => observedLengths.add(provider.apps.length));

      await provider.loadApps(computer);
      observedLengths.clear();
      now = now.add(const Duration(seconds: 31));
      await provider.loadForLauncher(computer);

      expect(client.calls, 2);
      expect(provider.apps.map((app) => app.appName), [
        'Installed game',
        'New game',
      ]);
      expect(observedLengths, isNot(contains(0)));
      provider.dispose();
    },
  );
}
