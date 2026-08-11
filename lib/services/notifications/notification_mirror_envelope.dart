import 'dart:convert';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';

final class NotificationMirrorEnvelope {
  NotificationMirrorEnvelope({DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  static const maxEncodedBytes = 32 * 1024;
  static const _maxClockSkew = Duration(seconds: 45);
  final DateTime Function() _clock;
  final Set<String> _seenNonces = {};

  Future<String> seal(Map<String, dynamic> payload, String token) async {
    final cleartext = utf8.encode(
      jsonEncode({
        'timestamp': _clock().millisecondsSinceEpoch,
        'payload': payload,
      }),
    );
    if (cleartext.length > maxEncodedBytes) {
      throw const FormatException('Notification payload is too large');
    }
    final algorithm = AesGcm.with256bits();
    final box = await algorithm.encrypt(cleartext, secretKey: _key(token));
    return jsonEncode({
      'version': 2,
      'box': base64Url.encode(box.concatenation()),
    });
  }

  Future<Map<String, dynamic>> open(String encoded, String token) async {
    if (encoded.length > maxEncodedBytes * 2) {
      throw const FormatException('Notification envelope is too large');
    }
    final envelope = jsonDecode(encoded);
    if (envelope is! Map || envelope['version'] != 2) {
      throw const FormatException('Unsupported notification envelope');
    }
    final packed = base64Url.decode(envelope['box']?.toString() ?? '');
    final box = SecretBox.fromConcatenation(
      packed,
      nonceLength: 12,
      macLength: 16,
    );
    final nonceId = base64Url.encode(box.nonce);
    if (_seenNonces.contains(nonceId)) {
      throw const FormatException('Notification envelope replayed');
    }
    final cleartext = await AesGcm.with256bits().decrypt(
      box,
      secretKey: _key(token),
    );
    final decoded = jsonDecode(utf8.decode(cleartext));
    if (decoded is! Map) throw const FormatException('Invalid payload');
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      (decoded['timestamp'] as num?)?.toInt() ?? 0,
      isUtc: true,
    );
    if (_clock().difference(timestamp).abs() > _maxClockSkew) {
      throw const FormatException('Notification envelope expired');
    }
    final payload = decoded['payload'];
    if (payload is! Map) throw const FormatException('Invalid payload');
    _seenNonces.add(nonceId);
    if (_seenNonces.length > 512) _seenNonces.remove(_seenNonces.first);
    return payload.map((key, value) => MapEntry(key.toString(), value));
  }

  SecretKey _key(String token) {
    if (token.trim().length < 16) {
      throw const FormatException('Notification token is too short');
    }
    return SecretKey(hashes.sha256.convert(utf8.encode(token)).bytes);
  }
}
