import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:pool/pool.dart';

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
             client.maxConnectionsPerHost = pinnedConnectionsPerHost;
             client.connectionTimeout = const Duration(seconds: 6);
             client.idleTimeout = const Duration(seconds: 15);
             return IOClient(client);
           });

  /// Art requests must not hang a scheduler slot forever; the disk cache
  /// simply retries on the next visit.
  static const requestTimeout = Duration(seconds: 20);

  /// Paired-host art shares [pinnedConnectionsPerHost] sockets. Taking a slot
  /// here, before the request, keeps [requestTimeout] measuring the request
  /// instead of the wait behind 50 queued posters.
  static const pinnedConnectionsPerHost = 2;
  final Pool _pinnedSlots = Pool(pinnedConnectionsPerHost);

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
    final pinned = client != _publicClient;

    Future<FileServiceResponse> fetch() async {
      final abort = Completer<void>();
      final request = http.AbortableRequest('GET', uri, abortTrigger: abort.future);
      if (headers != null) request.headers.addAll(headers);
      // nvhttp closes the socket after every /appasset response without
      // sending `Connection: close`, so a pooled keep-alive socket is dead by
      // the next request and fails with "Connection closed before full
      // header was received". Ask for a fresh connection each time.
      if (pinned) request.headers['connection'] = 'close';
      try {
        // Headers and body share one deadline, and the body is read here: a
        // response nobody drains keeps its socket checked out forever. Timed
        // out requests used to do exactly that (Future.timeout does not cancel
        // the request), so after one slow burst both paired-host sockets were
        // held by abandoned responses and every later poster timed out: only
        // the first ~29 tiles of the library ever loaded.
        return await () async {
          final response = await client.send(request);
          final bytes = await response.stream.toBytes();
          return HttpGetResponse(
            http.StreamedResponse(
              Stream.value(bytes),
              response.statusCode,
              contentLength: bytes.length,
              request: response.request,
              headers: response.headers,
              reasonPhrase: response.reasonPhrase,
            ),
          );
        }().timeout(requestTimeout);
      } on TimeoutException {
        // Frees the socket now, or as soon as the queued request gets one.
        if (!abort.isCompleted) abort.complete();
        rethrow;
      }
    }

    Future<FileServiceResponse> fetchWithRetry() async {
      try {
        return await fetch();
      } on http.ClientException catch (error) {
        if (!pinned || !error.message.contains('Connection closed')) rethrow;
        // A socket the pool believed open: GET is idempotent, retry once.
        return await fetch();
      }
    }

    try {
      return pinned
          ? await _pinnedSlots.withResource(fetchWithRetry)
          : await fetchWithRetry();
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
