import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../crypto/client_identity.dart';

typedef PinnedArtClientFactory =
    http.Client Function(String expectedServerCert);

/// Looks up the paired server certificate for an `https://host:port` origin.
/// Returns null when no paired computer is known at that address.
typedef PinnedCertResolver = String? Function(String host, int port);

/// Downloads public artwork normally and routes paired-host `/appasset`
/// requests through the same mutual-TLS identity used by the NV HTTP client.
class GameArtFileService extends FileService {
  GameArtFileService({
    http.Client? publicClient,
    PinnedArtClientFactory? pinnedClientFactory,
  }) : _publicClient = publicClient ?? http.Client(),
       _pinnedClientFactory =
           pinnedClientFactory ??
           ((cert) {
             final client = ClientIdentity.createHttpClient(
               expectedServerCert: cert,
             );
             // Artwork is best-effort and must never occupy every NVHTTPS
             // worker needed for launch and stream control.
             client.maxConnectionsPerHost = 2;
             client.connectionTimeout = const Duration(seconds: 6);
             client.idleTimeout = const Duration(seconds: 15);
             return IOClient(client);
           });

  /// Art requests must not hang a scheduler slot forever; the disk cache
  /// simply retries on the next visit.
  static const requestTimeout = Duration(seconds: 20);

  final http.Client _publicClient;
  final PinnedArtClientFactory _pinnedClientFactory;
  final Map<String, _PinnedArtClient> _pinnedClients = {};

  /// Installed by the computer store so a paired origin can be pinned lazily
  /// on the first art request. Registration used to happen only inside a
  /// successful `/applist`, so a launcher rendered from the persisted app
  /// cache (warm start, process restart) sent every poster request through
  /// the public client, failed the self-signed handshake, and the tile stayed
  /// grey for the rest of the process.
  PinnedCertResolver? certResolver;

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

  http.Client _clientFor(Uri uri) {
    final origin = _originKey(uri);
    final pinned = _pinnedClients[origin];
    if (pinned != null) return pinned.client;
    if (uri.scheme.toLowerCase() == 'https') {
      final cert = certResolver?.call(uri.host, uri.port);
      if (cert != null && cert.trim().isNotEmpty) {
        registerPinnedOrigin(
          address: uri.host,
          port: uri.port,
          expectedServerCert: cert,
        );
        return _pinnedClients[origin]!.client;
      }
    }
    return _publicClient;
  }

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse(url);
    final client = _clientFor(uri);
    final request = http.Request('GET', uri);
    if (headers != null) request.headers.addAll(headers);
    try {
      return HttpGetResponse(await client.send(request).timeout(requestTimeout));
    } catch (error) {
      debugPrint('[JUJO][art] GET ${uri.host}:${uri.port}${uri.path} failed: $error');
      rethrow;
    }
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
