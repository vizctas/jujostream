import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jujostream/services/http_api/game_art_file_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProviderChannel,
      (_) async => Directory.systemTemp.path,
    );
  });

  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProviderChannel,
      null,
    );
  });

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

  test(
    'launch artwork is downloaded once and reused from the art cache',
    () async {
      var requests = 0;
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final key = 'launch-cache-${DateTime.now().microsecondsSinceEpoch}';
      const url = 'https://cdn.example/launch-poster.png';
      final service = GameArtFileService(
        publicClient: MockClient((_) async {
          requests++;
          return http.Response.bytes(
            png,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      final manager = CacheManager(
        Config(
          'launch-art-test-${DateTime.now().microsecondsSinceEpoch}',
          stalePeriod: const Duration(days: 90),
          maxNrOfCacheObjects: 10,
          fileService: service,
        ),
      );

      try {
        final first = await manager.getSingleFile(url, key: key);
        expect(await first.readAsBytes(), isNotEmpty);
        final second = await manager.getSingleFile(url, key: key);
        expect(second.path, first.path);
        expect(requests, 1);
      } finally {
        await manager.removeFile(key);
        await manager.dispose();
      }
    },
  );
}
