import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jujostream/services/http_api/game_art_file_service.dart';

void main() {
  test('routes paired host artwork through its pinned client', () async {
    final publicRequests = <Uri>[];
    final pinnedRequests = <Uri>[];
    final service = GameArtFileService(
      publicClient: MockClient((request) async {
        publicRequests.add(request.url);
        return http.Response.bytes(utf8.encode('public'), 200);
      }),
      pinnedClientFactory: (expectedServerCert) {
        expect(expectedServerCert, 'server-cert');
        return MockClient((request) async {
          pinnedRequests.add(request.url);
          return http.Response.bytes(utf8.encode('paired'), 200);
        });
      },
    );

    service.registerPinnedOrigin(
      address: '192.168.3.10',
      port: 47984,
      expectedServerCert: 'server-cert',
    );

    final paired = await service.get(
      'https://192.168.3.10:47984/appasset?appid=1',
    );
    expect(await paired.content.transform(utf8.decoder).join(), 'paired');

    final public = await service.get('https://cdn.example/poster.jpg');
    expect(await public.content.transform(utf8.decoder).join(), 'public');

    expect(pinnedRequests, hasLength(1));
    expect(publicRequests, hasLength(1));
  });

  test('does not pin an empty server certificate', () async {
    var pinnedClientCreated = false;
    final service = GameArtFileService(
      publicClient: MockClient((_) async => http.Response('public', 200)),
      pinnedClientFactory: (_) {
        pinnedClientCreated = true;
        return MockClient((_) async => http.Response('paired', 200));
      },
    );

    service.registerPinnedOrigin(
      address: '192.168.3.10',
      port: 47984,
      expectedServerCert: '  ',
    );
    final response = await service.get(
      'https://192.168.3.10:47984/appasset?appid=1',
    );

    expect(await response.content.transform(utf8.decoder).join(), 'public');
    expect(pinnedClientCreated, isFalse);
  });
}
