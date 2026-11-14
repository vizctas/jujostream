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
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parseServerInfo parses FecControlVersion and preserves JSON roundtrip', () {
    final client = NvHttpClient();

    final supported = client.parseServerInfo('''
      <root status_code="200">
        <hostname>JujoHost</hostname>
        <uniqueid>uuid-fec-1</uniqueid>
        <FecControlVersion>1</FecControlVersion>
      </root>
    ''', '192.168.1.50', 47989);
    expect(supported.fecControlVersion, 1);

    final roundtrip = ComputerDetails.fromJson(supported.toJson());
    expect(roundtrip.fecControlVersion, 1);

    final legacy = client.parseServerInfo('''
      <root status_code="200">
        <hostname>LegacyHost</hostname>
        <uniqueid>uuid-fec-0</uniqueid>
      </root>
    ''', '192.168.1.51', 47989);
    expect(legacy.fecControlVersion, 0);
  });

  test('AppListProvider forwards rlFecPercentage=auto only when host advertises FecControlVersion >= 1', () async {
    SharedPreferences.setMockInitialValues({});
    final plugins = await PluginsProvider.load();
    final requests = <Uri>[];

    final mockClient = NvHttpClient(
      httpsClientFactory: (_) => MockClient((request) async {
        requests.add(request.url);
        if (request.url.path == '/applist') {
          return http.Response(
            '<root status_code="200"><App><ID>7</ID><AppTitle>Arena</AppTitle></App></root>',
            200,
          );
        }
        if (request.url.path == '/launch') {
          return http.Response(
            '<root status_code="200"><gamesession>1</gamesession>'
            '<sessionUrl0>rtsp://192.168.1.50:48010</sessionUrl0></root>',
            200,
          );
        }
        if (request.url.path == '/resume') {
          return http.Response(
            '<root status_code="200"><resume>1</resume>'
            '<sessionUrl0>rtsp://192.168.1.50:48010</sessionUrl0></root>',
            200,
          );
        }
        return http.Response('<root status_code="404"></root>', 404);
      }),
    );

    final provider = AppListProvider(plugins, httpClient: mockClient);
    const config = StreamConfiguration(width: 1920, height: 1080, fps: 60);
    final app = NvApp(appId: 7, appName: 'Arena');

    final capableHost = ComputerDetails(
      uuid: 'host-fec-1',
      localAddress: '192.168.1.50',
      activeAddress: '192.168.1.50',
      pairState: PairState.paired,
      fecControlVersion: 1,
    );
    await provider.loadApps(capableHost);
    final launchRes = await provider.launchApp(app, streamConfig: config, forceNewSession: true);
    expect(launchRes.success, isTrue);

    final launchReq = requests.lastWhere((u) => u.path == '/launch');
    expect(launchReq.queryParameters['rlFecPercentage'], 'auto');

    final resumeHost = ComputerDetails(
      uuid: 'host-fec-1-resume',
      localAddress: '192.168.1.50',
      activeAddress: '192.168.1.50',
      pairState: PairState.paired,
      runningGameId: 7,
      fecControlVersion: 1,
    );
    await provider.loadApps(resumeHost);
    final resumeRes = await provider.launchApp(app, streamConfig: config);
    expect(resumeRes.success, isTrue);

    final resumeReq = requests.lastWhere((u) => u.path == '/resume');
    expect(resumeReq.queryParameters['rlFecPercentage'], 'auto');

    final legacyHost = ComputerDetails(
      uuid: 'host-fec-0',
      localAddress: '192.168.1.51',
      activeAddress: '192.168.1.51',
      pairState: PairState.paired,
      fecControlVersion: 0,
    );
    await provider.loadApps(legacyHost);
    final legacyLaunch = await provider.launchApp(app, streamConfig: config, forceNewSession: true);
    expect(legacyLaunch.success, isTrue);

    final legacyReq = requests.lastWhere((u) => u.path == '/launch');
    expect(legacyReq.queryParameters.containsKey('rlFecPercentage'), isFalse);
  });
}
