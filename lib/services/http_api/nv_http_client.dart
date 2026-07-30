import 'dart:io' show HandshakeException;
import 'dart:math';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:logger/logger.dart';
import '../../models/computer_details.dart';
import '../../models/nv_app.dart';
import '../crypto/client_identity.dart';
import '../discovery/mdns_hostname_resolver.dart';
import 'game_art_file_service.dart';

enum AppListFailure {
  none,
  serverRejectedClientCertificate,
  serverIdentityRejected,
  network,
}

class NvHttpClient {
  final Logger _log = Logger();
  final http.Client _httpClient;
  final MdnsHostnameResolver _mdnsResolver = MdnsHostnameResolver();
  final http.Client Function(String? expectedServerCert) _httpsClientFactory;

  NvHttpClient({
    http.Client? httpClient,
    http.Client Function(String? expectedServerCert)? httpsClientFactory,
  }) : _httpClient = httpClient ?? http.Client(),
       _httpsClientFactory =
           httpsClientFactory ??
           ((expectedServerCert) => IOClient(
             ClientIdentity.createHttpClient(
               expectedServerCert: expectedServerCert,
             ),
           ));

  static const int defaultHttpsPort = 47984;
  static const int defaultHttpPort = 47989;

  /// True when the most recent getAppList call returned empty because the
  /// server rejected the client certificate (vs a network failure).
  /// Lets callers trigger cloud-pairing recovery instead of just erroring.
  AppListFailure lastAppListFailure = AppListFailure.none;

  bool get lastAppListCertRejected =>
      lastAppListFailure == AppListFailure.serverRejectedClientCertificate;

  static String get uniqueId => ClientIdentity.uniqueId;

  http.Client _newHttpsClient(String? expectedServerCert) {
    return _httpsClientFactory(expectedServerCert);
  }

  String _baseUrl(String address, int port, {bool https = true}) {
    final scheme = https ? 'https' : 'http';
    return '$scheme://$address:$port';
  }

  /// Resolves a `.local` hostname to a real IP via mDNS before HTTP calls.
  /// On Windows, [InternetAddress.lookup] maps `.local` to 127.0.0.1 via LLMNR.
  /// Returns the resolved IP string, or the original [address] if not `.local`
  /// or if resolution fails (let the call fail naturally with a real error).
  Future<String> _resolveAddress(String address) async {
    if (!address.toLowerCase().endsWith('.local')) return address;
    try {
      final resolved = await _mdnsResolver.resolve(
        address,
        timeout: const Duration(seconds: 2),
      );
      if (resolved.isNotEmpty) {
        _log.d('mDNS pre-resolved $address → ${resolved.first.address}');
        return resolved.first.address;
      }
    } catch (e) {
      _log.w('mDNS pre-resolution failed for $address: $e');
    }
    return address;
  }

  Future<ComputerDetails?> getServerInfo(
    String address, {
    int port = defaultHttpPort,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final resolvedAddress = await _resolveAddress(address);
    try {
      final url =
          '${_baseUrl(resolvedAddress, port, https: false)}/serverinfo'
          '?uniqueid=$uniqueId';
      _log.d('Fetching server info (HTTP) from: $url');

      final response = await _httpClient.get(Uri.parse(url)).timeout(timeout);

      if (response.statusCode == 200) {
        return parseServerInfo(response.body, address, port);
      }
      _log.w(
        'serverinfo HTTP ${response.statusCode} from $resolvedAddress:$port',
      );
    } catch (e) {
      _log.w('Failed to get server info (HTTP) from $resolvedAddress: $e');
    }
    return null;
  }

  /// Convenience wrapper that discards the cert verdict.
  /// Prefer [fetchServerInfo] on any path that owns pairing state.
  Future<ComputerDetails?> getServerInfoHttps(
    String address, {
    int httpsPort = defaultHttpsPort,
    int httpPort = defaultHttpPort,
    Duration timeout = const Duration(seconds: 5),
    String? expectedServerCert,
  }) async {
    final result = await fetchServerInfo(
      address,
      httpsPort: httpsPort,
      httpPort: httpPort,
      timeout: timeout,
      expectedServerCert: expectedServerCert,
    );
    return result.info;
  }

  /// Fetches `/serverinfo`, reporting whether the pinned server certificate was
  /// rejected.
  ///
  /// The HTTP fallback below makes a rotated server certificate look like an
  /// ordinary reachable server, which is how a dead `serverCert` used to
  /// survive forever. `certRejected` is the signal that the stored pairing is
  /// gone and must be cleared — it is returned rather than stored on the
  /// instance because this client is shared across concurrent calls.
  Future<({ComputerDetails? info, bool certRejected})> fetchServerInfo(
    String address, {
    int httpsPort = defaultHttpsPort,
    int httpPort = defaultHttpPort,
    Duration timeout = const Duration(seconds: 5),
    String? expectedServerCert,
  }) async {
    final resolvedAddress = await _resolveAddress(address);
    final pinned = expectedServerCert != null && expectedServerCert.isNotEmpty;
    var certRejected = false;
    try {
      final url =
          '${_baseUrl(resolvedAddress, httpsPort)}/serverinfo'
          '?uniqueid=$uniqueId';
      _log.d('Fetching server info (HTTPS) from: $url');

      final client = _newHttpsClient(expectedServerCert);
      try {
        final response = await client.get(Uri.parse(url)).timeout(timeout);

        if (response.statusCode == 200) {
          // on_verify_failed (nvhttp.cpp) sends HTTP 200 with status_code="401" as an XML
          // attribute when the client cert is unrecognized. extractXmlValue uses an element
          // regex and misses attributes — without this check we'd return pairStatusFromHttps=true
          // + pairState=notPaired, falsely treating the server as "HTTPS confirmed not paired".
          final attrMatch = RegExp(
            r'status_code="(\d+)"',
          ).firstMatch(response.body);
          final xmlAttrStatus = attrMatch?.group(1);
          if (xmlAttrStatus != null && xmlAttrStatus != '200') {
            _log.w(
              'serverinfo HTTPS XML status_code=$xmlAttrStatus (cert unrecognized), '
              'falling back to HTTP',
            );
            // The server answered and refused this device: the pairing is gone.
            certRejected = true;
          } else {
            final info = parseServerInfo(
              response.body,
              resolvedAddress,
              httpPort,
            );
            info.pairStatusFromHttps = true;
            return (info: info, certRejected: false);
          }
        }
        _log.w('serverinfo HTTPS ${response.statusCode}, falling back to HTTP');
      } finally {
        client.close();
      }
    } on HandshakeException catch (e) {
      // Only meaningful when a cert was pinned: the server presented a
      // different certificate than the one stored at pairing time.
      certRejected = pinned;
      _log.w('HTTPS serverinfo handshake failed ($e), falling back to HTTP');
    } catch (e) {
      _log.w('HTTPS serverinfo failed ($e), falling back to HTTP');
    }

    final info = await getServerInfo(
      resolvedAddress,
      port: httpPort,
      timeout: timeout,
    );
    return (info: info, certRejected: certRejected);
  }

  @visibleForTesting
  ComputerDetails parseServerInfo(
    String xmlBody,
    String connectAddress,
    int connectPort,
  ) {
    final computer = ComputerDetails(localAddress: connectAddress);

    computer.name = extractXmlValue(xmlBody, 'hostname') ?? 'Unknown';
    computer.uuid = extractXmlValue(xmlBody, 'uniqueid') ?? '';
    computer.macAddress = extractXmlValue(xmlBody, 'mac') ?? '';

    computer.localAddress =
        extractXmlValue(xmlBody, 'LocalIP') ?? connectAddress;
    computer.activeAddress = connectAddress;
    computer.remoteAddress = extractXmlValue(xmlBody, 'ExternalIP') ?? '';
    computer.httpsPort =
        int.tryParse(extractXmlValue(xmlBody, 'HttpsPort') ?? '') ??
        defaultHttpsPort;

    final xmlPort =
        int.tryParse(
          extractXmlValue(xmlBody, 'ExternalPort') ??
              extractXmlValue(xmlBody, 'HttpPort') ??
              '',
        ) ??
        0;
    computer.externalPort = xmlPort > 0 ? xmlPort : connectPort;

    final pairStatus = extractXmlValue(xmlBody, 'PairStatus');
    computer.pairState = pairStatus == '1'
        ? PairState.paired
        : PairState.notPaired;

    final currentGame = extractXmlValue(xmlBody, 'currentgame');
    computer.runningGameId = int.tryParse(currentGame ?? '0') ?? 0;

    computer.state = ComputerState.online;

    computer.serverVersion =
        extractXmlValue(xmlBody, 'appversion') ??
        extractXmlValue(xmlBody, 'ServerVersion') ??
        '7.1.431.-1';
    computer.gfeVersion =
        extractXmlValue(xmlBody, 'GfeVersion') ??
        extractXmlValue(xmlBody, 'gfeversion') ??
        '';
    // Absent on older server versions — optional, defaults to empty.
    computer.gpuName = extractXmlValue(xmlBody, 'GpuName') ?? '';
    computer.encoderName = extractXmlValue(xmlBody, 'EncoderName') ?? '';
    final codecValue =
        extractXmlValue(xmlBody, 'ServerCodecModeSupport') ??
        extractXmlValue(xmlBody, 'serverCodecModeSupport') ??
        '';
    computer.serverCodecModeSupport =
        codecValue.startsWith('0x') || codecValue.startsWith('0X')
        ? (int.tryParse(codecValue.substring(2), radix: 16) ?? 15)
        : (int.tryParse(codecValue) ?? 15);

    return computer;
  }

  Future<List<NvApp>> getAppList(
    String address, {
    int httpsPort = defaultHttpsPort,
    String? expectedServerCert,
  }) async {
    lastAppListFailure = AppListFailure.none;
    final resolvedAddress = await _resolveAddress(address);
    try {
      final url =
          '${_baseUrl(resolvedAddress, httpsPort)}/applist'
          '?uniqueid=$uniqueId';
      _log.d('Fetching app list (HTTPS) from: $url');

      final client = _newHttpsClient(expectedServerCert);
      late http.Response response;
      try {
        response = await client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
      } finally {
        client.close();
      }

      _log.d(
        'applist HTTPS ${response.statusCode}, body length: ${response.body.length}',
      );

      if (response.statusCode == 200) {
        final xmlStatus = extractXmlValue(response.body, 'status_code');
        if (xmlStatus != null && xmlStatus != '200') {
          _log.w('applist XML status_code=$xmlStatus (not paired or error)');
          lastAppListFailure = AppListFailure.serverRejectedClientCertificate;
          return [];
        }
        // on_verify_failed sends the status_code as an XML attribute
        // (<root status_code="401" .../>), which extractXmlValue misses.
        final attrMatch = RegExp(
          r'status_code="(\d+)"',
        ).firstMatch(response.body);
        final attrStatus = attrMatch?.group(1);
        if (attrStatus != null && attrStatus != '200') {
          _log.w(
            'applist XML attr status_code=$attrStatus '
            '(client cert not recognized by server)',
          );
          lastAppListFailure = AppListFailure.serverRejectedClientCertificate;
          return [];
        }
        lastAppListFailure = AppListFailure.none;
        final serverCert = expectedServerCert?.trim();
        if (serverCert != null && serverCert.isNotEmpty) {
          gameArtFileService.registerPinnedOrigin(
            address: resolvedAddress,
            port: httpsPort,
            expectedServerCert: serverCert,
          );
        }
        return parseAppList(response.body, resolvedAddress, httpsPort);
      }
      _log.w(
        'applist HTTPS ${response.statusCode} from $resolvedAddress:$httpsPort',
      );
    } on HandshakeException catch (e) {
      lastAppListFailure = expectedServerCert?.trim().isNotEmpty ?? false
          ? AppListFailure.serverIdentityRejected
          : AppListFailure.network;
      _log.e('Failed TLS handshake with $resolvedAddress: $e');
    } catch (e) {
      lastAppListFailure = AppListFailure.network;
      _log.e('Failed to get app list from $resolvedAddress: $e');
    }
    return [];
  }

  @visibleForTesting
  List<NvApp> parseAppList(String xmlBody, String address, int httpsPort) {
    final apps = <NvApp>[];

    final appRegex = RegExp(r'<App>(.*?)</App>', dotAll: true);
    final matches = appRegex.allMatches(xmlBody);

    for (final match in matches) {
      final appXml = match.group(1) ?? '';
      final appId = int.tryParse(extractXmlValue(appXml, 'ID') ?? '0') ?? 0;
      final appName = extractXmlValue(appXml, 'AppTitle') ?? '';
      final runningRaw = (extractXmlValue(appXml, 'IsRunning') ?? '')
          .toLowerCase();
      final isRunning =
          runningRaw == 'true' || runningRaw == '1' || runningRaw == 'yes';
      final isHdrSupported = extractXmlValue(appXml, 'IsHdrSupported') == '1';
      final serverUuid = extractXmlValue(appXml, 'UUID') ?? '';

      final strippedName = appName
          .replaceAll('\u200B', '')
          .replaceAll('\u200C', '')
          .toLowerCase()
          .trim();
      const remoteInputUuid = '8CB5C136-DA67-4F99-B4A1-F9CD35005CF4';
      const terminateAppUuid = 'E16CBE1B-295D-4632-9A76-EC4180C857D3';
      final isGhostApp =
          strippedName == 'terminate' ||
          strippedName == 'remote input' ||
          strippedName == 'remote desktop' ||
          strippedName == 'remote' ||
          serverUuid.toUpperCase() == remoteInputUuid ||
          serverUuid.toUpperCase() == terminateAppUuid;
      if (appId > 0 && appName.isNotEmpty && !isGhostApp) {
        final base = _baseUrl(address, httpsPort);
        // Richer art advertised by the host (absent/0 on older servers -> hero
        // and gallery stay empty and callers fall back to the poster).
        final hasHero = extractXmlValue(appXml, 'HasHeroImage') == '1';
        final extraCount =
            int.tryParse(extractXmlValue(appXml, 'ExtraImageCount') ?? '0') ??
            0;
        apps.add(
          NvApp(
            appId: appId,
            appName: appName,
            isRunning: isRunning,
            isHdrSupported: isHdrSupported,
            serverUuid: serverUuid.isNotEmpty ? serverUuid : null,

            posterUrl:
                '$base/appasset'
                '?uniqueid=$uniqueId&appid=$appId&AssetType=2&AssetIdx=0',
            heroImageUrl: hasHero
                ? '$base/appasset?uniqueid=$uniqueId&appid=$appId&AssetType=3&AssetIdx=0'
                : null,
            screenshotUrls: [
              for (var i = 0; i < extraCount; i++)
                '$base/appasset?uniqueid=$uniqueId&appid=$appId&AssetType=4&AssetIdx=$i',
            ],
          ),
        );
      }
    }

    apps.sort(
      (a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
    );
    return apps;
  }

  /// Maximum number of retry attempts for launch/resume when the server
  /// refuses the connection (common with Sunshine during state transitions).
  static const int _maxLaunchRetries = 3;
  static const List<int> _launchRetryDelaysMs = [800, 1500, 3000];

  Future<LaunchResult> launchApp(
    String address,
    int appId, {
    int port = defaultHttpsPort,
    required int width,
    required int height,
    int fps = 60,
    int bitrate = 20000,
    bool sops = true,
    bool enableHdr = false,
    bool localAudio = false,
    String? aspectRatio,
    bool clientMic = false,
    String? videoPacingMode,
    int? videoPacingSlackMs,
    int? videoMaxFrameAgeMs,
    String surroundAudioInfo = '1',
    Map<String, String> extraLaunchParams = const <String, String>{},
    String? expectedServerCert,
  }) async {
    final riKeyBytes = _randomBytes(16);
    final riKeyHex = riKeyBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final riKeyId = DateTime.now().millisecondsSinceEpoch % 0x7FFFFFFF;

    final params = {
      'uniqueid': uniqueId,
      'appid': appId.toString(),
      'mode': '${width}x${height}x$fps',
      'additionalStates': '1',
      'sops': sops ? '1' : '0',
      'rikey': riKeyHex,
      'rikeyid': riKeyId.toString(),
      'localAudioPlayMode': localAudio ? '1' : '0',
      'surroundAudioInfo': surroundAudioInfo,
      'remoteControllersBitmap': '0',
      'gcmap': '0',
    };
    if (enableHdr) params['enableHdr'] = '1';
    // Only forward a concrete "W:H"; sentinels ("auto"/"off") are resolved or
    // dropped client-side and must never reach the server (it validates W:H).
    if (aspectRatio != null && aspectRatio.contains(':')) {
      params['aspectRatio'] = aspectRatio;
    }
    if (clientMic) params['clientMic'] = '1';
    if (videoPacingMode != null && videoPacingMode.isNotEmpty) {
      params['videoPacingMode'] = videoPacingMode;
    }
    if (videoPacingSlackMs != null) {
      params['videoPacingSlackMs'] = videoPacingSlackMs.toString();
    }
    if (videoMaxFrameAgeMs != null) {
      params['videoMaxFrameAgeMs'] = videoMaxFrameAgeMs.toString();
    }
    if (extraLaunchParams.isNotEmpty) params.addAll(extraLaunchParams);

    final queryString = Uri(queryParameters: params).query;
    final url = '${_baseUrl(address, port)}/launch?$queryString';

    for (var attempt = 0; attempt <= _maxLaunchRetries; attempt++) {
      try {
        if (attempt > 0) {
          final delayMs =
              _launchRetryDelaysMs[(attempt - 1).clamp(
                0,
                _launchRetryDelaysMs.length - 1,
              )];
          _log.i('Launch retry $attempt/$_maxLaunchRetries after ${delayMs}ms');
          await Future.delayed(Duration(milliseconds: delayMs));
        }

        _log.i(
          'Launching app $appId on $address:$port (attempt ${attempt + 1})',
        );
        final client = _newHttpsClient(expectedServerCert);
        try {
          final response = await client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 10));

          if (response.statusCode != 200) {
            // Server-side and rate-limit statuses are transient — Sunshine
            // answers them while it is switching state. Returning immediately
            // treated a 503 mid-transition as a permanent failure.
            if (_isTransientStatus(response.statusCode) &&
                attempt < _maxLaunchRetries) {
              _log.w('Launch got HTTP ${response.statusCode}; retrying');
              continue;
            }
            return LaunchResult.fail('HTTP ${response.statusCode}');
          }

          final serverRiKey =
              extractXmlValue(response.body, 'rikey') ?? riKeyHex;
          final serverRiKeyId =
              int.tryParse(
                extractXmlValue(response.body, 'rikeyid') ?? riKeyId.toString(),
              ) ??
              riKeyId;
          final sessionUrl = extractXmlValue(response.body, 'sessionUrl0');

          final gamesession =
              extractXmlValue(response.body, 'gamesession') ?? '0';
          if (gamesession == '0') {
            _log.w(
              'Launch rejected: gamesession=0 (app may already be running — use resume)',
            );
            return LaunchResult.fail(
              'Launch rejected (gamesession=0). Try resuming the running session.',
            );
          }

          _log.d(
            'Launch response rikey=$serverRiKey rikeyid=$serverRiKeyId sessionUrl=$sessionUrl',
          );
          return LaunchResult.ok(
            riKey: serverRiKey,
            riKeyId: serverRiKeyId,
            sessionUrl: sessionUrl,
          );
        } finally {
          client.close();
        }
      } catch (e) {
        final isRetryable = _isRetryableError(e);
        if (isRetryable && attempt < _maxLaunchRetries) {
          _log.w('Launch attempt ${attempt + 1} failed (retryable): $e');
          continue;
        }
        _log.e('Failed to launch app after ${attempt + 1} attempts: $e');
        return LaunchResult.fail(_friendlyError(e, address, port));
      }
    }
    return LaunchResult.fail(
      'Failed to connect to $address:$port after $_maxLaunchRetries retries',
    );
  }

  Future<LaunchResult> resumeApp(
    String address,
    int appId, {
    int port = defaultHttpsPort,
    required int width,
    required int height,
    int fps = 60,
    int bitrate = 20000,
    bool sops = true,
    bool enableHdr = false,
    bool localAudio = false,
    String? aspectRatio,
    bool clientMic = false,
    String? videoPacingMode,
    int? videoPacingSlackMs,
    int? videoMaxFrameAgeMs,
    String surroundAudioInfo = '1',
    Map<String, String> extraLaunchParams = const <String, String>{},
    String? expectedServerCert,
  }) async {
    final riKeyBytes = _randomBytes(16);
    final riKeyHex = riKeyBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final riKeyId = DateTime.now().millisecondsSinceEpoch % 0x7FFFFFFF;

    final params = {
      'uniqueid': uniqueId,
      'appid': appId.toString(),
      'mode': '${width}x${height}x$fps',
      'additionalStates': '1',
      'sops': sops ? '1' : '0',
      'rikey': riKeyHex,
      'rikeyid': riKeyId.toString(),
      'localAudioPlayMode': localAudio ? '1' : '0',
      'surroundAudioInfo': surroundAudioInfo,
      'remoteControllersBitmap': '0',
      'gcmap': '0',
    };
    if (enableHdr) params['enableHdr'] = '1';
    // Only forward a concrete "W:H"; sentinels ("auto"/"off") are resolved or
    // dropped client-side and must never reach the server (it validates W:H).
    if (aspectRatio != null && aspectRatio.contains(':')) {
      params['aspectRatio'] = aspectRatio;
    }
    if (clientMic) params['clientMic'] = '1';
    if (videoPacingMode != null && videoPacingMode.isNotEmpty) {
      params['videoPacingMode'] = videoPacingMode;
    }
    if (videoPacingSlackMs != null) {
      params['videoPacingSlackMs'] = videoPacingSlackMs.toString();
    }
    if (videoMaxFrameAgeMs != null) {
      params['videoMaxFrameAgeMs'] = videoMaxFrameAgeMs.toString();
    }
    if (extraLaunchParams.isNotEmpty) params.addAll(extraLaunchParams);
    final queryString = Uri(queryParameters: params).query;
    final url = '${_baseUrl(address, port)}/resume?$queryString';

    for (var attempt = 0; attempt <= _maxLaunchRetries; attempt++) {
      try {
        if (attempt > 0) {
          final delayMs =
              _launchRetryDelaysMs[(attempt - 1).clamp(
                0,
                _launchRetryDelaysMs.length - 1,
              )];
          _log.i('Resume retry $attempt/$_maxLaunchRetries after ${delayMs}ms');
          await Future.delayed(Duration(milliseconds: delayMs));
        }

        _log.i(
          'Resuming app $appId on $address:$port (attempt ${attempt + 1})',
        );
        final client = _newHttpsClient(expectedServerCert);
        try {
          final response = await client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 10));

          if (response.statusCode != 200) {
            if (_isTransientStatus(response.statusCode) &&
                attempt < _maxLaunchRetries) {
              _log.w('Resume got HTTP ${response.statusCode}; retrying');
              continue;
            }
            return LaunchResult.fail('HTTP ${response.statusCode}');
          }

          final resumeStatus = extractXmlValue(response.body, 'resume') ?? '0';
          if (resumeStatus == '0') {
            return LaunchResult.fail('Resume rejected (resume=0)');
          }

          final serverRiKey =
              extractXmlValue(response.body, 'rikey') ?? riKeyHex;
          final serverRiKeyId =
              int.tryParse(
                extractXmlValue(response.body, 'rikeyid') ?? riKeyId.toString(),
              ) ??
              riKeyId;
          final sessionUrl = extractXmlValue(response.body, 'sessionUrl0');

          _log.d('Resume response rikey=$serverRiKey rikeyid=$serverRiKeyId');
          return LaunchResult.ok(
            riKey: serverRiKey,
            riKeyId: serverRiKeyId,
            sessionUrl: sessionUrl,
          );
        } finally {
          client.close();
        }
      } catch (e) {
        final isRetryable = _isRetryableError(e);
        if (isRetryable && attempt < _maxLaunchRetries) {
          _log.w('Resume attempt ${attempt + 1} failed (retryable): $e');
          continue;
        }
        _log.e('Failed to resume app after ${attempt + 1} attempts: $e');
        return LaunchResult.fail(_friendlyError(e, address, port));
      }
    }
    return LaunchResult.fail(
      'Failed to connect to $address:$port after $_maxLaunchRetries retries',
    );
  }

  /// Returns true for transient network errors that are worth retrying
  /// (connection refused, reset, timeout, host unreachable).
  static bool _isRetryableError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('connection refused') ||
        msg.contains('connection reset') ||
        msg.contains('broken pipe') ||
        msg.contains('host is down') ||
        msg.contains('no route to host') ||
        msg.contains('network is unreachable') ||
        msg.contains('timed out') ||
        msg.contains('timeout');
  }

  /// Statuses worth another attempt: the server is up but momentarily unable
  /// to serve the request (state transition, restart, rate limit).
  static bool _isTransientStatus(int status) =>
      status == 408 || status == 429 || status >= 500;

  /// Converts raw exceptions into user-friendly error messages.
  static String _friendlyError(Object e, String address, int port) {
    final msg = e.toString();
    if (msg.contains('Connection refused')) {
      return 'Connection refused by $address:$port. '
          'Check that Sunshine/Vibepollo is running and the port is correct.';
    }
    if (msg.contains('timed out') || msg.contains('Timeout')) {
      return 'Connection to $address:$port timed out. '
          'The host may be asleep or unreachable.';
    }
    if (msg.contains('No route to host') ||
        msg.contains('Network is unreachable')) {
      return 'Cannot reach $address. Check your network connection.';
    }
    return '$e';
  }

  static List<int> _randomBytes(int n) {
    final rng = Random.secure();
    return List<int>.generate(n, (_) => rng.nextInt(256));
  }

  Future<bool> quitApp(
    String address, {
    int port = defaultHttpsPort,
    String? expectedServerCert,
  }) async {
    try {
      final url = '${_baseUrl(address, port)}/cancel?uniqueid=$uniqueId';
      _log.i('Quitting app on $address (HTTPS)');

      final client = _newHttpsClient(expectedServerCert);
      try {
        final response = await client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 5));
        return response.statusCode == 200;
      } finally {
        client.close();
      }
    } catch (e) {
      _log.e('Failed to quit app: $e');
      return false;
    }
  }

  @visibleForTesting
  String? extractXmlValue(String xml, String tag) {
    final regex = RegExp('<$tag>(.*?)</$tag>', dotAll: true);
    final match = regex.firstMatch(xml);
    return match?.group(1)?.trim();
  }

  void dispose() {
    _httpClient.close();
  }
}

class LaunchResult {
  final bool success;
  final String riKey;
  final int riKeyId;
  final String? sessionUrl;
  final String error;

  const LaunchResult._({
    required this.success,
    this.riKey = '',
    this.riKeyId = 0,
    this.sessionUrl,
    this.error = '',
  });

  factory LaunchResult.ok({
    required String riKey,
    required int riKeyId,
    String? sessionUrl,
  }) => LaunchResult._(
    success: true,
    riKey: riKey,
    riKeyId: riKeyId,
    sessionUrl: sessionUrl,
  );

  factory LaunchResult.fail(String error) =>
      LaunchResult._(success: false, error: error);
}
