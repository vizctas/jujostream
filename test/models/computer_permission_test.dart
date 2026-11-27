import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jujostream/models/computer_details.dart';
import 'package:jujostream/services/http_api/nv_http_client.dart';

class _BodyClient extends http.BaseClient {
  _BodyClient(this.body);
  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(body.codeUnits), 200);
}

const _list = 0x1000000;
const _view = 0x2000000;
const _launch = 0x4000000;
const _pad = 256;

String _xml(int perm) =>
    '<root status_code="200"><hostname>JulyTower</hostname><uniqueid>u-1</uniqueid>'
    '<PairStatus>1</PairStatus><Permission>$perm</Permission></root>';

void main() {
  ComputerDetails withPerm(int? p) =>
      ComputerDetails(uuid: 'u-1', name: 'JulyTower')..hostPermission = p;

  test('canLaunchApps is true when permission unknown (legacy/unpaired)', () {
    expect(withPerm(null).canLaunchApps, isTrue);
    expect(withPerm(null).canViewStream, isTrue);
  });

  test('guest without launch bit cannot launch but can view', () {
    final c = withPerm(_list | _view | _pad);
    expect(c.canLaunchApps, isFalse);
    expect(c.canViewStream, isTrue);
  });

  test('member viewer with list only cannot view', () {
    expect(withPerm(_list).canViewStream, isFalse);
    expect(withPerm(_list | _view | _launch).canLaunchApps, isTrue);
  });

  test('hostPermission survives JSON round trip', () {
    final c = ComputerDetails.fromJson(withPerm(_list | _view).toJson());
    expect(c.hostPermission, _list | _view);
  });

  test('serverinfo over HTTP does not set hostPermission', () async {
    final client = NvHttpClient(httpClient: _BodyClient(_xml(0)));
    final result = await client.fetchServerInfo('192.168.3.30');
    expect(result.info, isNotNull);
    expect(result.info!.hostPermission, isNull);
  });

  test('serverinfo over HTTPS sets hostPermission', () async {
    final perm = _list | _view | _pad;
    final https = _BodyClient(_xml(perm));
    final client = NvHttpClient(
      httpClient: _BodyClient(_xml(0)),
      httpsClientFactory: (_) => https,
    );
    final result = await client.fetchServerInfo(
      '192.168.3.30',
      expectedServerCert: 'pinned',
    );
    expect(result.info!.pairStatusFromHttps, isTrue);
    expect(result.info!.hostPermission, perm);
  });

  ComputerDetails shared(List<String> perms, {bool owner = false}) =>
      ComputerDetails(uuid: 'u-2', name: 'Shared')
        ..permissions = perms
        ..isCloudOwner = owner;

  test('canRelayWake: owner, wake/admin, or no permission data', () {
    expect(shared(['launch'], owner: true).canRelayWake, isTrue);
    expect(shared(['wake']).canRelayWake, isTrue);
    expect(shared(['admin']).canRelayWake, isTrue);
    expect(shared([]).canRelayWake, isTrue);
  });

  test('canRelayWake: shared without wake is refused', () {
    expect(shared(['launch', 'guests', 'kbm']).canRelayWake, isFalse);
  });
}
