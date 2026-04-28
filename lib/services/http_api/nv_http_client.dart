import 'dart:math';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:logger/logger.dart';
import '../../models/computer_details.dart';
import '../../models/nv_app.dart';
import '../crypto/client_identity.dart';
import '../discovery/mdns_hostname_resolver.dart';

class NvHttpClient {
  final Logger _log = Logger();
  final http.Client _httpClient = http.Client();
  final MdnsHostnameResolver _mdnsResolver = MdnsHostnameResolver();

  static const int defaultHttpsPort = 47984;
  static const int defaultHttpPort = 47989;

  static String get uniqueId => ClientIdentity.uniqueId;

  http.Client _newHttpsClient() {
    return IOClient(ClientIdentity.createHttpClient());
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

  Future<ComputerDetails?> getServerInfoHttps(
    String address, {
    int httpsPort = defaultHttpsPort,
    int httpPort = defaultHttpPort,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final resolvedAddress = await _resolveAddress(address);
    try {
      final url =
          '${_baseUrl(resolvedAddress, httpsPort)}/serverinfo'
          '?uniqueid=$uniqueId';
      _log.d('Fetching server info (HTTPS) from: $url');

      final client = _newHttpsClient();
      try {
        final response = await client.get(Uri.parse(url)).timeout(timeout);

        if (response.statusCode == 200) {
          final info = parseServerInfo(
            response.body,
            resolvedAddress,
            httpPort,
          );
          info.pairStatusFromHttps = true;
          return info;
        }
        _log.w('serverinfo HTTPS ${response.statusCode}, falling back to HTTP');
      } finally {
        client.close();
      }
    } catch (e) {
      _log.w('HTTPS serverinfo failed ($e), falling back to HTTP');
    }

    return getServerInfo(resolvedAddress, port: httpPort, timeout: timeout);
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
  }) async {
    final resolvedAddress = await _resolveAddress(address);
    try {
      final url =
          '${_baseUrl(resolvedAddress, httpsPort)}/applist'
          '?uniqueid=$uniqueId';
      _log.d('Fetching app list (HTTPS) from: $url');

      final client = _newHttpsClient();
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
          return [];
        }
        return parseAppList(response.body, resolvedAddress, httpsPort);
      }
      _log.w(
        'applist HTTPS ${response.statusCode} from $resolvedAddress:$httpsPort',
      );
    } catch (e) {
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
        apps.add(
          NvApp(
            appId: appId,
            appName: appName,
            isRunning: isRunning,
            isHdrSupported: isHdrSupported,
            serverUuid: serverUuid.isNotEmpty ? serverUuid : null,

            posterUrl:
                '${_baseUrl(address, httpsPort)}/appasset'
                '?uniqueid=$uniqueId&appid=$appId&AssetType=2&AssetIdx=0',
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
    int width = 1920,
    int height = 1080,
    int fps = 60,
    int bitrate = 20000,
    bool sops = true,
    bool enableHdr = false,
    bool localAudio = false,
    String surroundAudioInfo = '1',
    Map<String, String> extraLaunchParams = const <String, String>{},
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
        final client = _newHttpsClient();
        try {
          final response = await client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 10));

          if (response.statusCode != 200) {
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
    int width = 1920,
    int height = 1080,
    int fps = 60,
    int bitrate = 20000,
    bool sops = true,
    bool enableHdr = false,
    bool localAudio = false,
    String surroundAudioInfo = '1',
    Map<String, String> extraLaunchParams = const <String, String>{},
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
        final client = _newHttpsClient();
        try {
          final response = await client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 10));

          if (response.statusCode != 200) {
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

  Future<bool> quitApp(String address, {int port = defaultHttpsPort}) async {
    try {
      final url = '${_baseUrl(address, port)}/cancel?uniqueid=$uniqueId';
      _log.i('Quitting app on $address (HTTPS)');

      final client = _newHttpsClient();
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
