import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jujostream/services/http_api/nv_http_client.dart';

void main() {
  test('launch result reports the host that answered, for the stream to reuse', () async {
    final mock = MockClient(
      (req) async => http.Response(
        '<root status_code="200"><gamesession>1</gamesession>'
        '<sessionUrl0>rtsp://192.168.3.6:47010</sessionUrl0></root>',
        200,
      ),
    );
    final client = NvHttpClient(httpsClientFactory: (_) => mock);

    final res = await client.launchApp('192.168.3.6', 10, width: 1920, height: 1080);

    expect(res.success, isTrue);
    expect(res.host, '192.168.3.6');
  });
}
