import 'dart:async';
import 'dart:convert';
import 'dart:io' show InternetAddress, Platform;
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:pointycastle/export.dart';
import 'package:logger/logger.dart';
import '../../models/computer_details.dart';
import '../crypto/client_identity.dart';
import '../discovery/mdns_hostname_resolver.dart';
import '../errors/error_codes.dart';

class PairingService {
  PairingService({MdnsHostnameResolver? mdnsResolver})
    : _mdnsResolver = mdnsResolver ?? MdnsHostnameResolver();

  final Logger _log = Logger();
  final MdnsHostnameResolver _mdnsResolver;
  static const Duration _pairPhaseTimeout = Duration(seconds: 60);

  static const Duration _phase5Timeout = Duration(seconds: 5);

  /// MethodChannel for the native Android Foreground Service that runs
  /// the ENTIRE pairing handshake natively (survives Dart VM pause).
  static const MethodChannel _pairingLocksChannel = MethodChannel(
    'com.jujostream/pairing_locks',
  );

  static String get _uniqueId => ClientIdentity.uniqueId;

  /// Set to true from [requestCancel] to abort an in-progress [pair] call.
  /// Checked by [_runPairingPhase] at each retry iteration.
  bool _cancelRequested = false;

  /// Signals the active [pair] call to abort as soon as possible.
  /// Called by the UI when the user explicitly cancels pairing.
  void requestCancel() {
    _cancelRequested = true;
    _log.d('PairingService: cancel requested');
  }

  late final RSAPrivateKey _clientPrivateKey = _parsePkcs8RsaPrivateKey(
    ClientIdentity.keyPem,
  );
  late final Uint8List _clientCertPemBytes = Uint8List.fromList(
    ClientIdentity.certBytes,
  );
  late final Uint8List _clientCertSignature = _extractX509SignatureFromDer(
    _pemToDer(ClientIdentity.certPem),
  );

  String generatePin() {
    final random = Random.secure();
    return random.nextInt(10000).toString().padLeft(4, '0');
  }

  Future<PairingResult> pair(ComputerDetails computer, String pin) async {
    // Reset cancellation flag for this fresh pairing attempt.
    _cancelRequested = false;

    final uniqueId = _uniqueId;

    // ── ANDROID: Run ENTIRE handshake natively in Foreground Service ──────
    //
    // On Android, when the user backgrounds JUJO to enter the PIN in Chrome,
    // the Dart VM is paused. Previously only Phase 1 ran natively, but
    // Phases 2-5 had to wait for Dart to resume — by which time the server's
    // pairing session had often timed out ("wrong PIN" error).
    //
    // Solution: ALL 5 phases run in a native Java thread inside the FGS.
    // Phase 1 blocks until the user enters the PIN. Phases 2-5 execute
    // immediately after in the same thread. Dart only polls for the result.
    final bool useNativeFullPairing = !kIsWeb && Platform.isAndroid;
    final endpoint = useNativeFullPairing
        ? _primaryPairingEndpoint(computer)
        : await _resolvePairingEndpoint(computer, uniqueId);

    if (endpoint == null) {
      return PairingResult.failed(
        'No pairing HTTP endpoint is reachable. Verify the server is running and port 47989 is allowed through the firewall.',
      );
    }

    _log.i('Starting pairing with ${endpoint.address}:${endpoint.port}');

    if (useNativeFullPairing) {
      return _pairViaNativeService(computer, pin, endpoint.baseUrl, uniqueId);
    }

    // ── OTHER PLATFORMS: Dart-based pairing (process doesn't pause) ──────
    return _pairViaDart(computer, pin, endpoint.baseUrl, uniqueId);
  }

  Future<_PairingEndpoint?> _resolvePairingEndpoint(
    ComputerDetails computer,
    String uniqueId,
  ) async {
    final candidates = _buildPairingEndpointCandidates(computer);
    if (candidates.isEmpty) return null;

    for (final endpoint in candidates) {
      for (final probeEndpoint in await _expandPairingEndpoint(endpoint)) {
        try {
          final response = await _freshGet(
            '${probeEndpoint.baseUrl}/serverinfo?uniqueid=$uniqueId',
            timeout: const Duration(seconds: 2),
          );
          if (response.statusCode == 200) {
            _log.i('Pairing endpoint selected: ${probeEndpoint.safeBaseUrl}');
            return probeEndpoint;
          }
          _log.w(
            'Pairing endpoint ${probeEndpoint.safeBaseUrl} returned HTTP ${response.statusCode}',
          );
        } catch (e) {
          _log.w(
            'Pairing endpoint ${probeEndpoint.safeBaseUrl} unavailable: '
            '${sanitizePairingLogMessage(e)}',
          );
        }
      }
    }

    _log.w('No pairing endpoint probe succeeded.');
    return null;
  }

  Future<List<_PairingEndpoint>> _expandPairingEndpoint(
    _PairingEndpoint endpoint,
  ) async {
    List<InternetAddress> resolved = const [];
    Object? lookupError;

    try {
      resolved = await InternetAddress.lookup(
        endpoint.address,
      ).timeout(const Duration(seconds: 2));
    } catch (e) {
      lookupError = e;
      _log.w(
        'System DNS lookup failed for ${endpoint.address}: '
        '${sanitizePairingLogMessage(e)}',
      );
    }

    final unsafeLoopback =
        lookupError == null &&
        _isUnsafeLoopbackPairingResolution(endpoint.address, resolved);

    if (unsafeLoopback || lookupError != null) {
      final mdnsAddresses = await _mdnsResolver.resolve(endpoint.address);
      final mdnsEndpoints = _expandEndpointWithResolvedAddresses(
        endpoint,
        mdnsAddresses,
      );
      if (mdnsEndpoints.isNotEmpty) {
        _log.i(
          'mDNS resolved ${endpoint.address} to '
          '${mdnsEndpoints.map((e) => e.address).join(', ')}',
        );
        return mdnsEndpoints;
      }
    }

    if (unsafeLoopback) {
      // mDNS resolution above returned no usable addresses.
      // On Windows, LLMNR may map .local names to 127.0.0.1 and our mDNS
      // query may also have failed.  Rather than silently blocking the
      // endpoint, try it directly as a last resort — the HTTP probe will
      // fail with a real network error if the address is genuinely wrong,
      // which at least surfaces a useful diagnostic.
      if (endpoint.address.toLowerCase().endsWith('.local')) {
        _log.w(
          'mDNS resolution failed for ${endpoint.address} (OS returned loopback). '
          'Retrying with raw hostname as last resort.',
        );
        return [endpoint];
      }
      _log.w(
        'Skipping pairing endpoint ${endpoint.safeBaseUrl}: non-.local hostname '
        'resolved to loopback (${resolved.map((a) => a.address).join(', ')}).',
      );
      return const [];
    }

    return [endpoint];
  }

  static _PairingEndpoint? _primaryPairingEndpoint(ComputerDetails computer) {
    final candidates = _buildPairingEndpointCandidates(computer);
    return candidates.isEmpty ? null : candidates.first;
  }

  @visibleForTesting
  static List<String> pairingBaseUrlCandidatesForTest(
    ComputerDetails computer,
  ) {
    return _buildPairingEndpointCandidates(
      computer,
    ).map((endpoint) => endpoint.baseUrl).toList(growable: false);
  }

  static List<_PairingEndpoint> _buildPairingEndpointCandidates(
    ComputerDetails computer,
  ) {
    final seenAddresses = <String>{};
    final addresses =
        <String>[
              computer.activeAddress,
              computer.manualAddress,
              computer.localAddress,
              computer.remoteAddress,
            ]
            .map((address) => address.trim())
            .where((address) => address.isNotEmpty)
            .where(seenAddresses.add)
            .toList(growable: false);

    final primaryPort = computer.externalPort > 0
        ? computer.externalPort
        : 47989;
    final ports = <int>[primaryPort, if (primaryPort != 47989) 47989];

    final seenEndpoints = <String>{};
    final endpoints = <_PairingEndpoint>[];
    for (final address in addresses) {
      for (final port in ports) {
        final key = '$address:$port';
        if (seenEndpoints.add(key)) {
          endpoints.add(_PairingEndpoint(address: address, port: port));
        }
      }
    }
    return endpoints;
  }

  @visibleForTesting
  static List<String> pairingBaseUrlCandidatesWithResolvedAddressesForTest(
    ComputerDetails computer,
    Map<String, List<InternetAddress>> resolvedByHost,
  ) {
    final expanded = <_PairingEndpoint>[];
    for (final endpoint in _buildPairingEndpointCandidates(computer)) {
      expanded.addAll(
        _expandEndpointWithResolvedAddresses(
          endpoint,
          resolvedByHost[endpoint.address] ?? const [],
        ),
      );
    }
    return expanded.map((endpoint) => endpoint.baseUrl).toList(growable: false);
  }

  static List<_PairingEndpoint> _expandEndpointWithResolvedAddresses(
    _PairingEndpoint endpoint,
    List<InternetAddress> addresses,
  ) {
    final usableAddresses = MdnsHostnameResolver.filterUsableAddresses(
      addresses,
    );
    return usableAddresses
        .map(
          (address) =>
              _PairingEndpoint(address: address.address, port: endpoint.port),
        )
        .toList(growable: false);
  }

  @visibleForTesting
  static String sanitizePairingLogMessage(Object value) {
    var message = value.toString();
    message = message.replaceAllMapped(
      RegExp(r'https?:\/\/[^\s]+', caseSensitive: false),
      (match) => _sanitizePairingUrl(match.group(0)!),
    );
    message = message.replaceAllMapped(
      RegExp(
        r'(clientcert|servercert|uniqueid|salt|clientchallenge|serverchallengeresp|clientpairingsecret|pairingsecret|rikey)=([^&\s,}]+)',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=redacted',
    );
    return message;
  }

  static String _sanitizePairingUrl(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      if (!uri.hasScheme || uri.queryParameters.isEmpty) return rawUrl;

      final safeQuery = <String, String>{};
      uri.queryParameters.forEach((key, value) {
        safeQuery[key] = _isSensitivePairingQueryKey(key) ? 'redacted' : value;
      });
      return uri.replace(queryParameters: safeQuery).toString();
    } catch (_) {
      return rawUrl;
    }
  }

  static bool _isSensitivePairingQueryKey(String key) {
    final lower = key.toLowerCase();
    return lower == 'uniqueid' ||
        lower.contains('cert') ||
        lower.contains('salt') ||
        lower.contains('challenge') ||
        lower.contains('secret') ||
        lower.contains('key');
  }

  @visibleForTesting
  static bool isUnsafeLoopbackPairingResolutionForTest(
    String host,
    List<InternetAddress> resolved,
  ) {
    return _isUnsafeLoopbackPairingResolution(host, resolved);
  }

  static bool _isUnsafeLoopbackPairingResolution(
    String host,
    List<InternetAddress> resolved,
  ) {
    if (_isExplicitLocalHost(host)) return false;
    if (_isIpLiteral(host)) return false;
    return resolved.isNotEmpty &&
        resolved.every((address) => address.isLoopback);
  }

  static bool _isExplicitLocalHost(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1';
  }

  static bool _isIpLiteral(String host) {
    return InternetAddress.tryParse(host.trim()) != null;
  }

  @visibleForTesting
  static String pairingHttpsBaseUrlForTest(
    ComputerDetails computer,
    String selectedHttpBaseUrl,
  ) {
    return _buildPairingHttpsBaseUrl(computer, selectedHttpBaseUrl);
  }

  static String _buildPairingHttpsBaseUrl(
    ComputerDetails computer,
    String selectedHttpBaseUrl,
  ) {
    final httpsPort = computer.httpsPort > 0 ? computer.httpsPort : 47984;
    final selectedHost = Uri.parse(selectedHttpBaseUrl).host;
    final address = selectedHost.isNotEmpty
        ? selectedHost
        : (computer.activeAddress.isNotEmpty
              ? computer.activeAddress
              : computer.localAddress);
    return 'https://$address:$httpsPort';
  }

  /// Runs the entire pairing handshake via the native Android Foreground Service.
  ///
  /// The native side handles all 5 phases in a Java thread that survives
  /// Dart VM pause. This method just starts the service and polls for results.
  Future<PairingResult> _pairViaNativeService(
    ComputerDetails computer,
    String pin,
    String baseUrl,
    String uniqueId,
  ) async {
    _log.i('Using native Android full-pairing (survives Dart VM pause)');

    final httpsPort = computer.httpsPort > 0 ? computer.httpsPort : 47984;

    try {
      // Start the Foreground Service with all pairing parameters
      await _pairingLocksChannel.invokeMethod<void>('startFullPairing', {
        'baseUrl': baseUrl,
        'httpsPort': httpsPort,
        'uniqueId': uniqueId,
        'pin': pin,
        'certPem': ClientIdentity.certPem,
        'keyPem': ClientIdentity.keyPem,
        'timeoutMs': 120000,
      });

      // Poll for the result — the native thread runs independently of Dart.
      // When Dart resumes from background, the result may already be waiting.
      final deadline = DateTime.now().add(const Duration(seconds: 180));

      while (DateTime.now().isBefore(deadline)) {
        if (_cancelRequested) {
          try {
            await _pairingLocksChannel.invokeMethod<void>('release');
          } catch (_) {}
          return PairingResult.cancelled();
        }

        final result = await _pairingLocksChannel.invokeMethod<Map>(
          'pollResult',
        );

        if (result != null) {
          final paired = result['paired'] as bool? ?? false;
          final serverCertHex = result['serverCertHex'] as String? ?? '';
          final error = result['error'] as String?;

          if (error == 'cancelled' || error == 'interrupted') {
            return PairingResult.cancelled();
          }

          if (paired) {
            _log.i('Native pairing succeeded!');
            return PairingResult.success(serverCertHex);
          } else {
            _log.e('Native pairing failed: $error');
            return PairingResult.failed(error ?? 'Pairing failed');
          }
        }

        // Result not ready yet — wait 500ms before polling again.
        await Future.delayed(const Duration(milliseconds: 500));
      }

      return PairingResult.failed('Pairing timed out');
    } catch (e) {
      _log.e('Native pairing error: ${sanitizePairingLogMessage(e)}');
      final classified = classifyError('PAIR', e);
      return PairingResult.failed(classified.userMessage);
    } finally {
      try {
        await _pairingLocksChannel.invokeMethod<void>('release');
      } catch (_) {}
    }
  }

  /// Runs the pairing handshake entirely in Dart (for macOS/Windows/iOS).
  /// These platforms don't pause the process when switching apps.
  Future<PairingResult> _pairViaDart(
    ComputerDetails computer,
    String pin,
    String baseUrl,
    String uniqueId,
  ) async {
    try {
      // ── Upfront server-state reset ───────────────────────────────────────
      try {
        await _freshGet(
          '$baseUrl/unpair?uniqueid=$uniqueId',
          timeout: const Duration(seconds: 4),
        );
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 1500));

      final salt = _generateRandomBytes(16);
      final aesKey = _deriveAesKey(salt, pin);

      final phase1Url =
          '$baseUrl/pair'
          '?uniqueid=$uniqueId'
          '&devicename=Jujostream+Flutter'
          '&updateState=1'
          '&phrase=getservercert'
          '&salt=${_bytesToHex(salt)}'
          '&clientcert=${_bytesToHex(_clientCertPemBytes)}';

      _log.d('Phase 1: ${sanitizePairingLogMessage(phase1Url)}');

      // ── Phase 1: getservercert — the BLOCKING long-poll phase ─────────────
      late String phase1Xml;
      late String serverCertHex;
      bool phase1Accepted = false;

      // Outer: 0 = normal attempt, 1 = self-heal (unpair + retry on rejection)
      selfHealLoop:
      for (var selfHeal = 0; selfHeal < 2 && !phase1Accepted; selfHeal++) {
        if (selfHeal == 1) {
          _log.w('Phase 1 rejected. Self-healing: unpair + retry.');
          try {
            await _freshGet(
              '$baseUrl/unpair?uniqueid=$uniqueId',
              timeout: const Duration(seconds: 5),
            );
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 2500));
        }

        for (var attempt = 0; attempt < 4; attempt++) {
          if (_cancelRequested) throw const _PairingCancelledException();
          try {
            final resp = await _freshGet(
              phase1Url,
              timeout: const Duration(seconds: 120),
            );
            final responseBody = resp.body;

            phase1Xml = responseBody;

            if (_extractXmlValue(phase1Xml, 'paired') == '1') {
              phase1Accepted = true;
              break selfHealLoop;
            }

            _log.w(
              'Phase 1 returned paired=0 on attempt ${attempt + 1}'
              ' (selfHeal=$selfHeal). Will self-heal if available.',
            );
            break;
          } on TimeoutException catch (e) {
            _log.w(
              'Phase 1 attempt ${attempt + 1}/4 timed out: '
              '${sanitizePairingLogMessage(e)}. Retrying…',
            );
          } catch (e) {
            final lo = e.toString().toLowerCase();
            final isSocketErr =
                lo.contains('connection abort') ||
                lo.contains('software caused') ||
                lo.contains('connection reset') ||
                lo.contains('connection refused') ||
                lo.contains('connection closed') ||
                lo.contains('socketexception') ||
                lo.contains('broken pipe');
            if (isSocketErr) {
              _log.w(
                'Phase 1 socket error attempt ${attempt + 1}/4: '
                '${sanitizePairingLogMessage(e)}.'
                '${attempt < 3 ? ' Retrying in 2s…' : ' All attempts exhausted.'}',
              );
              if (attempt < 3) {
                await Future.delayed(const Duration(seconds: 2));
                continue;
              }
              rethrow;
            }
            rethrow;
          }
        }
      }

      if (!phase1Accepted) {
        return PairingResult.failed('Server rejected pairing request');
      }

      serverCertHex = _extractXmlValue(phase1Xml, 'plaincert') ?? '';
      if (serverCertHex.isEmpty) {
        _log.w(
          'Phase 1: empty plaincert — another pairing session is active. Unpairing…',
        );
        try {
          await _freshGet(
            '$baseUrl/unpair?uniqueid=$uniqueId',
            timeout: const Duration(seconds: 5),
          );
        } catch (_) {}
        return PairingResult.failed(
          'No server certificate returned (pairing already in progress?)',
        );
      }

      final serverCertPemBytes = _hexToBytes(serverCertHex);
      final serverCertPemString = String.fromCharCodes(serverCertPemBytes);
      final serverCertDer = _pemToDer(serverCertPemString);
      final serverCertSignature = _extractX509SignatureFromDer(serverCertDer);

      final clientChallenge = _generateRandomBytes(16);
      final encryptedChallenge = _aesEcbEncrypt(clientChallenge, aesKey);

      final phase2Url =
          '$baseUrl/pair'
          '?uniqueid=$uniqueId'
          '&devicename=Jujostream+Flutter'
          '&updateState=1'
          '&clientchallenge=${_bytesToHex(encryptedChallenge)}';

      _log.d('Phase 2: sending client challenge');
      final phase2Response = await _runPairingPhase(
        'Phase 2',
        phase2Url,
        timeout: _pairPhaseTimeout,
      );

      if (phase2Response.statusCode != 200) {
        return PairingResult.failed(
          'Phase 2 failed: HTTP ${phase2Response.statusCode}',
        );
      }

      final phase2Xml = phase2Response.body;
      if (_extractXmlValue(phase2Xml, 'paired') != '1') {
        return PairingResult.failed('Server rejected challenge (wrong PIN?)');
      }

      final serverChallengeHex =
          _extractXmlValue(phase2Xml, 'challengeresponse') ?? '';
      if (serverChallengeHex.isEmpty) {
        return PairingResult.failed('No challenge response from server');
      }

      final serverChallengeResponse = _aesEcbDecrypt(
        _hexToBytes(serverChallengeHex),
        aesKey,
      );

      if (serverChallengeResponse.length < 48) {
        return PairingResult.failed('Malformed challenge response from server');
      }

      final serverResponse = serverChallengeResponse.sublist(0, 32);
      final serverChallenge = serverChallengeResponse.sublist(32, 48);

      final clientSecret = _generateRandomBytes(16);
      final clientHash = _sha256(
        Uint8List.fromList([
          ...serverChallenge,
          ..._clientCertSignature,
          ...clientSecret,
        ]),
      );
      final encryptedClientHash = _aesEcbEncrypt(clientHash, aesKey);

      final phase3Url =
          '$baseUrl/pair'
          '?uniqueid=$uniqueId'
          '&devicename=Jujostream+Flutter'
          '&updateState=1'
          '&serverchallengeresp=${_bytesToHex(encryptedClientHash)}';

      _log.d('Phase 3: sending server challenge response');
      final phase3Response = await _runPairingPhase(
        'Phase 3',
        phase3Url,
        timeout: _pairPhaseTimeout,
      );

      if (phase3Response.statusCode != 200) {
        return PairingResult.failed(
          'Phase 3 failed: HTTP ${phase3Response.statusCode}',
        );
      }

      final phase3Xml = phase3Response.body;
      if (_extractXmlValue(phase3Xml, 'paired') != '1') {
        return PairingResult.failed('Server rejected secret (wrong PIN?)');
      }

      final pairingSecretHex =
          _extractXmlValue(phase3Xml, 'pairingsecret') ?? '';
      if (pairingSecretHex.isEmpty) {
        return PairingResult.failed('No pairing secret from server');
      }

      final pairingSecret = _hexToBytes(pairingSecretHex);
      if (pairingSecret.length <= 16) {
        return PairingResult.failed('Invalid pairing secret from server');
      }

      final serverSecret = pairingSecret.sublist(0, 16);
      final expectedServerResponse = _sha256(
        Uint8List.fromList([
          ...clientChallenge,
          ...serverCertSignature,
          ...serverSecret,
        ]),
      );
      if (!_constantTimeEquals(serverResponse, expectedServerResponse)) {
        return PairingResult.failed('PIN incorrect or pairing state invalid');
      }

      final clientSignature = _signSha256Rsa(clientSecret, _clientPrivateKey);
      final clientPairingSecret = Uint8List.fromList([
        ...clientSecret,
        ...clientSignature,
      ]);

      final phase4Url =
          '$baseUrl/pair'
          '?uniqueid=$uniqueId'
          '&devicename=Jujostream+Flutter'
          '&updateState=1'
          '&clientpairingsecret=${_bytesToHex(clientPairingSecret)}';

      _log.d('Phase 4: sending client pairing secret');
      final phase4Response = await _runPairingPhase(
        'Phase 4',
        phase4Url,
        timeout: _pairPhaseTimeout,
      );

      if (phase4Response.statusCode != 200) {
        return PairingResult.failed(
          'Phase 4 failed: HTTP ${phase4Response.statusCode}',
        );
      }

      final phase4Xml = phase4Response.body;
      if (_extractXmlValue(phase4Xml, 'paired') != '1') {
        return PairingResult.failed('Server rejected client pairing secret');
      }

      final httpsBaseUrl = _buildPairingHttpsBaseUrl(computer, baseUrl);

      final httpsClient = IOClient(ClientIdentity.createHttpClient());

      try {
        final httpsPairChallengeUrl =
            '$httpsBaseUrl/pair'
            '?uniqueid=$uniqueId'
            '&devicename=Jujostream+Flutter'
            '&updateState=1'
            '&phrase=pairchallenge';
        final httpPairChallengeUrl =
            '$baseUrl/pair'
            '?uniqueid=$uniqueId'
            '&devicename=Jujostream+Flutter'
            '&updateState=1'
            '&phrase=pairchallenge';

        var phase5Completed = false;

        _log.d('Phase 5 (HTTPS): $httpsPairChallengeUrl');
        try {
          final pairChallengeResponse = await httpsClient
              .get(Uri.parse(httpsPairChallengeUrl))
              .timeout(_phase5Timeout);

          if (pairChallengeResponse.statusCode == 200 &&
              _extractXmlValue(pairChallengeResponse.body, 'paired') == '1') {
            phase5Completed = true;
          } else {
            _log.w(
              'Phase 5 HTTPS pairchallenge not accepted '
              '(status=${pairChallengeResponse.statusCode})',
            );
          }
        } catch (e) {
          _log.w(
            'Phase 5 HTTPS pairchallenge failed: '
            '${sanitizePairingLogMessage(e)}',
          );
        }

        if (!phase5Completed) {
          _log.d('Phase 5 fallback (HTTP): $httpPairChallengeUrl');
          try {
            final httpPairChallengeResponse = await _freshGet(
              httpPairChallengeUrl,
              timeout: const Duration(seconds: 5),
            );
            if (httpPairChallengeResponse.statusCode == 200 &&
                _extractXmlValue(httpPairChallengeResponse.body, 'paired') ==
                    '1') {
              phase5Completed = true;
            } else {
              _log.w(
                'Phase 5 HTTP pairchallenge not accepted '
                '(status=${httpPairChallengeResponse.statusCode})',
              );
            }
          } catch (e) {
            _log.w(
              'Phase 5 HTTP pairchallenge failed: '
              '${sanitizePairingLogMessage(e)}',
            );
          }
        }

        if (!phase5Completed) {
          _log.w(
            'Phase 5 challenge failed, verifying pair state via HTTPS serverinfo',
          );
          bool serverExplicitlyRejected = false;
          try {
            final serverInfoUrl = '$httpsBaseUrl/serverinfo?uniqueid=$uniqueId';
            final serverInfoResponse = await httpsClient
                .get(Uri.parse(serverInfoUrl))
                .timeout(const Duration(seconds: 5));
            final pairStatus = _extractXmlValue(
              serverInfoResponse.body,
              'PairStatus',
            );

            if (serverInfoResponse.statusCode == 200 && pairStatus == '1') {
              phase5Completed = true;
            } else if (serverInfoResponse.statusCode == 200 &&
                pairStatus == '0') {
              serverExplicitlyRejected = true;
              _log.e(
                'Phase 5: server returned PairStatus=0 — pairing explicitly rejected',
              );
            }
          } catch (e) {
            _log.w(
              'Phase 5 serverinfo verification failed (network): '
              '${sanitizePairingLogMessage(e)}',
            );
          }

          if (serverExplicitlyRejected) {
            return PairingResult.failed(
              'Server rejected pairing after handshake. '
              'Please check Sunshine/Apollo logs and try again.',
            );
          }
        }

        if (!phase5Completed) {
          _log.w(
            'Phase 5 HTTPS unconfirmed (network error only); '
            'accepting because Phase 4 completed and next poll will verify.',
          );
        }
      } finally {
        httpsClient.close();
      }

      _log.i('Pairing successful!');
      return PairingResult.success(serverCertHex);
    } on _PairingCancelledException {
      _log.i('Pairing cancelled by user.');
      return PairingResult.cancelled();
    } catch (e) {
      _log.e('Pairing error (raw): ${sanitizePairingLogMessage(e)}');
      final classified = classifyError('PAIR', e);
      _log.e('Pairing error (code): ${classified.code}');
      return PairingResult.failed(classified.userMessage);
    }
  }

  Future<bool> unpair(ComputerDetails computer) async {
    final address = computer.activeAddress.isNotEmpty
        ? computer.activeAddress
        : computer.localAddress;
    final url =
        'http://$address:${computer.externalPort}/unpair'
        '?uniqueid=$_uniqueId';

    try {
      final response = await _freshGet(
        url,
        timeout: const Duration(seconds: 5),
      );
      return response.statusCode == 200;
    } catch (e) {
      _log.e('Unpair failed: ${sanitizePairingLogMessage(e)}');
      return false;
    }
  }

  Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  Uint8List _deriveAesKey(Uint8List salt, String pin) {
    final pinBytes = utf8.encode(pin);
    final combined = Uint8List(salt.length + pinBytes.length);
    combined.setAll(0, salt);
    combined.setAll(salt.length, pinBytes);
    final hash = _sha256(combined);

    return hash.sublist(0, 16);
  }

  Uint8List _sha256(Uint8List data) {
    final digest = SHA256Digest();
    return digest.process(data);
  }

  Uint8List _aesEcbEncrypt(Uint8List data, Uint8List key) {
    return _aesEcbTransform(data, key, true);
  }

  Uint8List _aesEcbDecrypt(Uint8List data, Uint8List key) {
    return _aesEcbTransform(data, key, false);
  }

  Uint8List _aesEcbTransform(Uint8List data, Uint8List key, bool encrypt) {
    final engine = AESEngine()..init(encrypt, KeyParameter(key));
    final blockSize = engine.blockSize;
    final roundedSize =
        ((data.length + blockSize - 1) ~/ blockSize) * blockSize;

    final input = Uint8List(roundedSize);
    input.setAll(0, data);

    final output = Uint8List(roundedSize);
    for (var offset = 0; offset < roundedSize; offset += blockSize) {
      engine.processBlock(input, offset, output, offset);
    }
    return output;
  }

  Uint8List _signSha256Rsa(Uint8List data, RSAPrivateKey privateKey) {
    final signer = Signer('SHA-256/RSA');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final signature = signer.generateSignature(data) as RSASignature;
    return signature.bytes;
  }

  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  RSAPrivateKey _parsePkcs8RsaPrivateKey(String pem) {
    final der = _pemToDer(pem);
    final top = _readDerElement(der, 0);
    var cursor = top.contentOffset;

    final version = _readDerElement(der, cursor);
    cursor += version.totalLength;

    final algorithm = _readDerElement(der, cursor);
    cursor += algorithm.totalLength;

    final privateKeyOctet = _readDerElement(der, cursor);
    final rsaDer = Uint8List.fromList(
      der.sublist(
        privateKeyOctet.contentOffset,
        privateKeyOctet.contentOffset + privateKeyOctet.contentLength,
      ),
    );

    final rsaSeq = _readDerElement(rsaDer, 0);
    var rsaCursor = rsaSeq.contentOffset;

    final rsaVersion = _readDerElement(rsaDer, rsaCursor);
    rsaCursor += rsaVersion.totalLength;

    final modulus = _readDerInteger(rsaDer, rsaCursor);
    rsaCursor += modulus.$2;

    final publicExponent = _readDerInteger(rsaDer, rsaCursor);
    rsaCursor += publicExponent.$2;

    final privateExponent = _readDerInteger(rsaDer, rsaCursor);
    rsaCursor += privateExponent.$2;

    final p = _readDerInteger(rsaDer, rsaCursor);
    rsaCursor += p.$2;

    final q = _readDerInteger(rsaDer, rsaCursor);

    return RSAPrivateKey(modulus.$1, privateExponent.$1, p.$1, q.$1);
  }

  Uint8List _extractX509SignatureFromDer(Uint8List der) {
    final top = _readDerElement(der, 0);
    var cursor = top.contentOffset;

    final tbsCert = _readDerElement(der, cursor);
    cursor += tbsCert.totalLength;

    final sigAlg = _readDerElement(der, cursor);
    cursor += sigAlg.totalLength;

    final sigValue = _readDerElement(der, cursor);
    if (sigValue.tag != 0x03 || sigValue.contentLength <= 1) {
      return Uint8List(0);
    }

    final sigContent = der.sublist(
      sigValue.contentOffset,
      sigValue.contentOffset + sigValue.contentLength,
    );
    return Uint8List.fromList(sigContent.sublist(1));
  }

  Uint8List _pemToDer(String pem) {
    final base64Body = pem
        .replaceAll('\r', '')
        .split('\n')
        .where((line) => !line.startsWith('-----') && line.trim().isNotEmpty)
        .join('');
    return Uint8List.fromList(base64Decode(base64Body));
  }

  (BigInt, int) _readDerInteger(Uint8List data, int offset) {
    final element = _readDerElement(data, offset);
    final valueBytes = data.sublist(
      element.contentOffset,
      element.contentOffset + element.contentLength,
    );
    return (_unsignedBigInt(valueBytes), element.totalLength);
  }

  BigInt _unsignedBigInt(List<int> bytes) {
    var start = 0;
    if (bytes.isNotEmpty && bytes.first == 0) {
      start = 1;
    }
    final data = bytes.sublist(start);
    if (data.isEmpty) {
      return BigInt.zero;
    }
    final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return BigInt.parse(hex, radix: 16);
  }

  _DerElement _readDerElement(Uint8List data, int offset) {
    final tag = data[offset];
    final firstLengthByte = data[offset + 1];

    int contentLength;
    int lengthBytes;

    if ((firstLengthByte & 0x80) == 0) {
      contentLength = firstLengthByte;
      lengthBytes = 1;
    } else {
      final byteCount = firstLengthByte & 0x7F;
      if (byteCount == 0) {
        throw const FormatException('Invalid DER length encoding');
      }
      contentLength = 0;
      for (var i = 0; i < byteCount; i++) {
        contentLength = (contentLength << 8) | data[offset + 2 + i];
      }
      lengthBytes = 1 + byteCount;
    }

    final headerLength = 1 + lengthBytes;
    final totalLength = headerLength + contentLength;

    return _DerElement(
      tag: tag,
      contentOffset: offset + headerLength,
      contentLength: contentLength,
      totalLength: totalLength,
    );
  }

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Uint8List _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }

  String? _extractXmlValue(String xml, String tag) {
    final regex = RegExp('<$tag>(.*?)</$tag>', dotAll: true);
    final match = regex.firstMatch(xml);
    return match?.group(1)?.trim();
  }

  static Future<http.Response> _freshGet(
    String url, {
    Duration? timeout,
  }) async {
    final client = http.Client();
    try {
      final future = client.get(Uri.parse(url));
      return await (timeout != null ? future.timeout(timeout) : future);
    } finally {
      client.close();
    }
  }

  /// Runs a single pairing phase with automatic socket-error retry.
  ///
  /// Throws [_PairingCancelledException] if [requestCancel] was called.
  /// Throws [TimeoutException] if [timeout] (default 60s) is exceeded.
  /// Other non-socket exceptions are rethrown immediately.
  Future<http.Response> _runPairingPhase(
    String phaseName,
    String url, {
    Duration? timeout,
  }) async {
    final startTime = DateTime.now();
    final maxWait = timeout ?? const Duration(seconds: 60);

    while (true) {
      if (_cancelRequested) {
        _log.w('$phaseName aborted: cancel was requested');
        throw const _PairingCancelledException();
      }

      final elapsed = DateTime.now().difference(startTime);
      final remaining = maxWait - elapsed;
      if (remaining.isNegative) {
        throw TimeoutException(
          '$phaseName timed out after ${maxWait.inSeconds}s',
          maxWait,
        );
      }

      try {
        return await _freshGet(url, timeout: remaining);
      } on TimeoutException {
        throw TimeoutException(
          '$phaseName timed out after ${maxWait.inSeconds}s',
          maxWait,
        );
      } catch (e) {
        if (e is _PairingCancelledException) rethrow;
        final lower = e.toString().toLowerCase();
        if (lower.contains('connection abort') ||
            lower.contains('software caused connection') ||
            lower.contains('connection lost') ||
            lower.contains('connection closed') ||
            lower.contains('connection reset') ||
            lower.contains('broken pipe') ||
            lower.contains('socketexception')) {
          _log.w(
            '$phaseName socket dropped: ${sanitizePairingLogMessage(e)}. '
            'Retrying in 1s...',
          );
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
        rethrow;
      }
    }
  }

  void dispose() {}
}

class _PairingEndpoint {
  final String address;
  final int port;

  const _PairingEndpoint({required this.address, required this.port});

  String get baseUrl => 'http://$address:$port';

  String get safeBaseUrl => baseUrl;
}

class _DerElement {
  final int tag;
  final int contentOffset;
  final int contentLength;
  final int totalLength;

  const _DerElement({
    required this.tag,
    required this.contentOffset,
    required this.contentLength,
    required this.totalLength,
  });
}

class PairingResult {
  final bool paired;
  final String? serverCert;
  final String? error;

  /// True when pairing was interrupted by the user backgrounding the app.
  /// The dialog uses this to show specific "re-enter PIN" guidance instead
  /// of a generic error, and to auto-retry once the user is back in foreground.
  final bool wasCancelled;

  PairingResult._({
    required this.paired,
    this.serverCert,
    this.error,
    this.wasCancelled = false,
  });

  factory PairingResult.success(String serverCert) =>
      PairingResult._(paired: true, serverCert: serverCert);

  factory PairingResult.failed(String error) =>
      PairingResult._(paired: false, error: error);

  factory PairingResult.cancelled() => PairingResult._(
    paired: false,
    error: 'Pairing interrupted',
    wasCancelled: true,
  );
}

/// Thrown internally by [PairingService._runPairingPhase] when
/// [PairingService.requestCancel] is called while a phase is retrying.
class _PairingCancelledException implements Exception {
  const _PairingCancelledException();
  @override
  String toString() => 'Pairing was cancelled by user';
}
