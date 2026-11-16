import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jujostream/models/computer_details.dart';
import 'package:jujostream/models/nv_app.dart';
import 'package:jujostream/models/stream_configuration.dart';
import 'package:jujostream/providers/app_list_provider.dart';
import 'package:jujostream/providers/plugins_provider.dart';
import 'package:jujostream/services/http_api/nv_http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('launchApp uses the freshest computer address, not the one cached at loadApps', () async {
    SharedPreferences.setMockInitialValues({});
    final plugins = await PluginsProvider.load();
    final hosts = <String>[];
    final mockClient = NvHttpClient(
      httpsClientFactory: (_) => MockClient((request) async {
        hosts.add(request.url.host);
        if (request.url.path == '/applist') {
          return http.Response('<root status_code="200"><App><ID>7</ID><AppTitle>Arena</AppTitle></App></root>', 200);
        }
        return http.Response(
          '<root status_code="200"><gamesession>1</gamesession><sessionUrl0>rtsp://192.168.3.30:48010</sessionUrl0></root>',
          200,
        );
      }),
    );
    final provider = AppListProvider(plugins, httpClient: mockClient);
    // Loaded while on Wi-Fi: LAN address.
    await provider.loadApps(
      ComputerDetails(uuid: 'july', localAddress: '192.168.3.30', activeAddress: '192.168.3.30', pairState: PairState.paired),
    );
    // Phone moved to 4G: the poller now reaches the host over WAN.
    final fresh = ComputerDetails(
      uuid: 'july',
      localAddress: '192.168.3.30',
      remoteAddress: '190.32.76.233',
      activeAddress: '190.32.76.233',
      pairState: PairState.paired,
    );

    final res = await provider.launchApp(
      NvApp(appId: 7, appName: 'Arena'),
      streamConfig: const StreamConfiguration(width: 1920, height: 1080, fps: 60),
      computer: fresh,
    );

    expect(res.success, isTrue);
    expect(res.host, '190.32.76.233');
    expect(hosts.last, '190.32.76.233');
  });
}
