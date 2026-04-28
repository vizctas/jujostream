import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jujostream/services/metadata/steam_video_client.dart';

void main() {
  group('SteamVideoClient', () {
    test(
      'searchApp returns exact app id and artwork from store search',
      () async {
        final client = SteamVideoClient(
          client: _FakeClient(
            http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': 620,
                    'name': 'Portal 2',
                    'tiny_image': 'https://example.com/portal.jpg',
                  },
                ],
              }),
              200,
            ),
          ),
        );

        final result = await client.searchApp('Portal 2');

        expect(result?.appId, 620);
        expect(result?.imageUrl, 'https://example.com/portal.jpg');
      },
    );

    test('searchAppId preserves existing app id lookup behavior', () async {
      final client = SteamVideoClient(
        client: _FakeClient(
          http.Response(
            jsonEncode({
              'items': [
                {'id': 620, 'name': 'Portal 2'},
              ],
            }),
            200,
          ),
        ),
      );

      final appId = await client.searchAppId('Portal 2');

      expect(appId, 620);
    });
  });
}

class _FakeClient extends http.BaseClient {
  final http.Response response;

  _FakeClient(this.response);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
