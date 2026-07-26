import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../crypto/client_identity.dart';

typedef PinnedArtClientFactory =
    http.Client Function(String expectedServerCert);

/// Downloads public artwork normally and routes paired-host `/appasset`
/// requests through the same mutual-TLS identity used by the NV HTTP client.
class GameArtFileService extends FileService {
  GameArtFileService({
    http.Client? publicClient,
    PinnedArtClientFactory? pinnedClientFactory,
  }) : _publicClient = publicClient ?? http.Client(),
       _pinnedClientFactory =
           pinnedClientFactory ??
           ((cert) => IOClient(
             ClientIdentity.createHttpClient(expectedServerCert: cert),
           ));

  final http.Client _publicClient;
  final PinnedArtClientFactory _pinnedClientFactory;
  final Map<String, _PinnedArtClient> _pinnedClients = {};

  void registerPinnedOrigin({
    required String address,
    required int port,
    required String expectedServerCert,
  }) {
    final certificate = expectedServerCert.trim();
    if (certificate.isEmpty) return;

    final origin = _originKey(Uri(scheme: 'https', host: address, port: port));
    final existing = _pinnedClients[origin];
    if (existing?.certificate == certificate) return;

    existing?.client.close();
    _pinnedClients[origin] = _PinnedArtClient(
      certificate,
      _pinnedClientFactory(certificate),
    );
  }

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse(url);
    final client = _pinnedClients[_originKey(uri)]?.client ?? _publicClient;
    final request = http.Request('GET', uri);
    if (headers != null) request.headers.addAll(headers);
    return HttpGetResponse(await client.send(request));
  }

  static String _originKey(Uri uri) {
    final port = uri.hasPort
        ? uri.port
        : uri.scheme.toLowerCase() == 'https'
        ? 443
        : 80;
    return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}:$port';
  }
}

class _PinnedArtClient {
  const _PinnedArtClient(this.certificate, this.client);

  final String certificate;
  final http.Client client;
}

final gameArtFileService = GameArtFileService();
