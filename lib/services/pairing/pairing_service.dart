import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:pointycastle/export.dart';
import 'package:logger/logger.dart';
import '../../models/computer_details.dart';
import '../crypto/client_identity.dart';
import '../errors/error_codes.dart';

class PairingService {
  final Logger _log = Logger();
  static const Duration _pairPhaseTimeout = Duration(seconds: 60);

  static const Duration _phase5Timeout = Duration(seconds: 5);

  /// MethodChannel for acquiring/releasing WakeLock + WifiLock on Android.
  /// Calls silently no-op on non-Android platforms.
  static const MethodChannel _pairingLocksChannel =
      MethodChannel('com.jujostream/pairing_locks');

  static String get _uniqueId => ClientIdentity.uniqueId;

  /// Set to true from [requestCancel] to abort an in-progress [pair] call.
  /// Checked by [_runPairingPhase] at each retry iteration.
  bool _cancelRequested = false;

  /// Signals the active [pair] call to abort as soon as possible.
  /// Called by the UI when the app goes to background during pairing.
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

  Future<void> generateClientIdentity() async {
    _log.d('Using embedded client identity for pairing');
  }

  String generatePin() {
    final random = Random.secure();
    return random.nextInt(10000).toString().padLeft(4, '0');
  }

  Future<PairingResult> pair(ComputerDetails computer, String pin) async {
    // Reset cancellation flag for this fresh pairing attempt.
    _cancelRequested = false;

    final address = computer.activeAddress.isNotEmpty
        ? computer.activeAddress
        : computer.localAddress;

    final pairingPort = computer.externalPort > 0
        ? computer.externalPort
        : 47989;

    _log.i('Starting pairing with $address:$pairingPort, PIN: $pin');

    // Acquire WakeLock + WifiLock so Android doesn\'t throttle the CPU or
    // kill the WiFi socket when the user switches to Chrome to enter the PIN.
    // On non-Android platforms this call is silently ignored.
    try {
      await _pairingLocksChannel.invokeMethod<void>('acquire');
    } catch (_) {}

    final baseUrl = 'http://$address:$pairingPort';
    final uniqueId = _uniqueId;

    try {
      // ── Upfront server-state reset ───────────────────────────────────────
      // Clear any stale pairing session from a previous failed attempt.
      // The delay is OUTSIDE the catch so it always executes even on failure.
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

      _log.d('Phase 1: $phase1Url');

      // ── Phase 1: getservercert — the BLOCKING long-poll phase ─────────────
      //
      // MOONLIGHT REFERENCE INSIGHT (NvHTTP.java):
      //   Phase 1 uses enableReadTimeout=false → readTimeout=0 (INFINITE).
      //   Comment: "The initial pair query does require outside action (user
      //   entering a PIN) but subsequent pairing queries do not."
      //
      // Sunshine/Apollo HOLDS the Phase 1 HTTP response until the user enters
      // the PIN on the web UI. Phases 2-5 complete in seconds afterward.
      //
      // Previous bug: 10s timeout caused Phase 1 to die before user could
      // switch apps, navigate to Sunshine, and type the PIN (30-90s typical).
      // Dead Phase 1 → stale server session → "out of order getservercert."
      //
      // Fix: 90s per connection attempt. Self-heal (unpair + retry) if server
      // rejects Phase 1 with paired=0 (stale session from prior attempt).
      late String phase1Xml;
      late String serverCertHex;
      bool phase1Accepted = false;

      // Outer: 0 = normal attempt, 1 = self-heal (unpair + retry on rejection)
      selfHealLoop:
      for (var selfHeal = 0; selfHeal < 2 && !phase1Accepted; selfHeal++) {
        if (selfHeal == 1) {
          _log.w('Phase 1 rejected by server (stale session). Self-healing: unpair + retry.');
          try {
            await _freshGet(
              '$baseUrl/unpair?uniqueid=$uniqueId',
              timeout: const Duration(seconds: 5),
            );
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 2500));
        }

        // Inner: up to 4 connection attempts per self-heal pass
        for (var attempt = 0; attempt < 4; attempt++) {
          if (_cancelRequested) throw const _PairingCancelledException();
          try {
            final resp = await _freshGet(
              phase1Url,
              // 90 s = enough for user to copy PIN, switch to Chrome,
              // navigate to Sunshine web UI, and type the PIN.
              timeout: const Duration(seconds: 120),
            );
            phase1Xml = resp.body;

            if (_extractXmlValue(phase1Xml, 'paired') == '1') {
              phase1Accepted = true;
              break selfHealLoop; // full success — exit both loops
            }

            // Server returned paired=0 — break inner loop so the outer loop
            // can trigger the self-heal pass (unpair + retry Phase 1).
            _log.w('Phase 1 returned paired=0 on attempt ${attempt + 1}'
                ' (selfHeal=$selfHeal). Will self-heal if available.');
            break;
          } on TimeoutException catch (e) {
            // 90 s elapsed without a server response. The user may still be
            // navigating to the web UI. Retry the same URL (same salt).
            _log.w('Phase 1 attempt ${attempt + 1}/4 timed out: $e. Retrying…');
            // Loop continues to next attempt (no break/rethrow).
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
              _log.w('Phase 1 socket error attempt ${attempt + 1}/4: $e.'
                  '${attempt < 3 ? ' Retrying in 2s…' : ' All attempts exhausted.'}');
              if (attempt < 3) {
                await Future.delayed(const Duration(seconds: 2));
                continue; // next inner attempt
              }
              rethrow; // propagates to outer catch → classifyError → PAIR-001
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
        // Another device is simultaneously pairing (GFE/Sunshine returns empty
        // cert in this case). Mirror Moonlight's ALREADY_IN_PROGRESS handling:
        // call unpair to unblock the server so the user can retry.
        _log.w('Phase 1: empty plaincert — another pairing session is active. Unpairing…');
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

      final httpsPort = computer.httpsPort > 0
          ? computer.httpsPort
          : 47984;
      final httpsBaseUrl = 'https://$address:$httpsPort';

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
          _log.w('Phase 5 HTTPS pairchallenge failed: $e');
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
            _log.w('Phase 5 HTTP pairchallenge failed: $e');
          }
        }

        if (!phase5Completed) {
          _log.w('Phase 5 challenge failed, verifying pair state via HTTPS serverinfo');
          bool serverExplicitlyRejected = false;
          try {
            final serverInfoUrl = '$httpsBaseUrl/serverinfo?uniqueid=$uniqueId';
            final serverInfoResponse = await httpsClient
                .get(Uri.parse(serverInfoUrl))
                .timeout(const Duration(seconds: 5));
            final pairStatus = _extractXmlValue(serverInfoResponse.body, 'PairStatus');

            if (serverInfoResponse.statusCode == 200 && pairStatus == '1') {
              phase5Completed = true;
            } else if (serverInfoResponse.statusCode == 200 && pairStatus == '0') {

              serverExplicitlyRejected = true;
              _log.e('Phase 5: server returned PairStatus=0 â€” pairing explicitly rejected');
            }
          } catch (e) {
            _log.w('Phase 5 serverinfo verification failed (network): $e');

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
      // Cancellation is a normal control flow (user backgrounded the app).
      // Return a typed result so the dialog can show re-entry guidance rather
      // than a generic error message.
      _log.i('Pairing cancelled by lifecycle observer (app went to background).');
      return PairingResult.cancelled();
    } catch (e) {
      _log.e('Pairing error (raw): $e');
      final classified = classifyError('PAIR', e);
      _log.e('Pairing error (code): ${classified.code}');
      return PairingResult.failed(classified.userMessage);
    } finally {
      // Always release locks — even if pairing throws unexpectedly.
      try {
        await _pairingLocksChannel.invokeMethod<void>('release');
      } catch (_) {}
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
      final response = await _freshGet(url, timeout: const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      _log.e('Unpair failed: $e');
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
      // Cancellation check — fires at the top of every retry iteration,
      // i.e., within 1 second of requestCancel() being called (delay below).
      if (_cancelRequested) {
        _log.w('$phaseName aborted: cancel was requested (app went to background)');
        throw const _PairingCancelledException();
      }

      final elapsed = DateTime.now().difference(startTime);
      final remaining = maxWait - elapsed;
      if (remaining.isNegative) {
        throw TimeoutException('$phaseName timed out after ${maxWait.inSeconds}s', maxWait);
      }

      try {
        return await _freshGet(url, timeout: remaining);
      } on TimeoutException {
        throw TimeoutException('$phaseName timed out after ${maxWait.inSeconds}s', maxWait);
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
          _log.w('$phaseName socket dropped: $e. Retrying in 1s...');
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
        rethrow;
      }
    }
  }

  void dispose() {}
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
  String toString() => 'Pairing was interrupted (app went to background)';
}
