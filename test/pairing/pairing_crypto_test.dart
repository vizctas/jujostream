import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

/// Standalone crypto helpers extracted from PairingService for unit testing.
/// These MUST produce identical output to the Kotlin PairingForegroundService.

Uint8List _sha256(Uint8List data) {
  return SHA256Digest().process(data);
}

Uint8List _deriveAesKey(Uint8List salt, String pin) {
  final pinBytes = utf8.encode(pin);
  final combined = Uint8List(salt.length + pinBytes.length);
  combined.setAll(0, salt);
  combined.setAll(salt.length, pinBytes);
  return _sha256(combined).sublist(0, 16);
}

Uint8List _aesEcbTransform(Uint8List data, Uint8List key, bool encrypt) {
  final engine = AESEngine()..init(encrypt, KeyParameter(key));
  final blockSize = engine.blockSize;
  final roundedSize = ((data.length + blockSize - 1) ~/ blockSize) * blockSize;
  final input = Uint8List(roundedSize);
  input.setAll(0, data);
  final output = Uint8List(roundedSize);
  for (var offset = 0; offset < roundedSize; offset += blockSize) {
    engine.processBlock(input, offset, output, offset);
  }
  return output;
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

void main() {
  group('AES Key Derivation', () {
    test('deriveAesKey produces 16-byte key from salt + pin', () {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final key = _deriveAesKey(salt, '1234');
      expect(key.length, 16);
    });

    test('deriveAesKey is deterministic', () {
      final salt = Uint8List.fromList(List.generate(16, (i) => i * 3));
      final key1 = _deriveAesKey(salt, '5678');
      final key2 = _deriveAesKey(salt, '5678');
      expect(key1, equals(key2));
    });

    test('different PINs produce different keys', () {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final key1 = _deriveAesKey(salt, '1234');
      final key2 = _deriveAesKey(salt, '5678');
      expect(key1, isNot(equals(key2)));
    });

    test('different salts produce different keys', () {
      final salt1 = Uint8List.fromList(List.generate(16, (i) => i));
      final salt2 = Uint8List.fromList(List.generate(16, (i) => i + 1));
      final key1 = _deriveAesKey(salt1, '1234');
      final key2 = _deriveAesKey(salt2, '1234');
      expect(key1, isNot(equals(key2)));
    });

    test('PIN with leading zeros is handled correctly', () {
      final salt = Uint8List.fromList(List.generate(16, (i) => 0xAA));
      final key1 = _deriveAesKey(salt, '0001');
      final key2 = _deriveAesKey(salt, '1');
      // '0001' and '1' are different strings → different keys
      expect(key1, isNot(equals(key2)));
    });
  });

  group('AES-ECB Encrypt/Decrypt', () {
    test('encrypt then decrypt returns original data (16 bytes)', () {
      final key = Uint8List.fromList(List.generate(16, (i) => i));
      final data = Uint8List.fromList(List.generate(16, (i) => i + 0x10));
      final encrypted = _aesEcbTransform(data, key, true);
      final decrypted = _aesEcbTransform(encrypted, key, false);
      expect(decrypted.sublist(0, 16), equals(data));
    });

    test('encrypt then decrypt returns original data (32 bytes)', () {
      final key = Uint8List.fromList(List.generate(16, (i) => i));
      final data = Uint8List.fromList(List.generate(32, (i) => i));
      final encrypted = _aesEcbTransform(data, key, true);
      final decrypted = _aesEcbTransform(encrypted, key, false);
      expect(decrypted.sublist(0, 32), equals(data));
    });

    test('non-block-aligned data is zero-padded', () {
      final key = Uint8List.fromList(List.generate(16, (i) => i));
      final data = Uint8List.fromList([1, 2, 3, 4, 5]); // 5 bytes
      final encrypted = _aesEcbTransform(data, key, true);
      // Should be padded to 16 bytes
      expect(encrypted.length, 16);
      final decrypted = _aesEcbTransform(encrypted, key, false);
      expect(decrypted.sublist(0, 5), equals(data));
      // Remaining bytes should be zero
      expect(decrypted.sublist(5), equals(List.filled(11, 0)));
    });
  });

  group('Hex Encoding', () {
    test('bytesToHex produces lowercase hex', () {
      final bytes = Uint8List.fromList([0x00, 0x0F, 0xFF, 0xAB]);
      expect(_bytesToHex(bytes), '000fffab');
    });

    test('hexToBytes roundtrips with bytesToHex', () {
      final original = Uint8List.fromList(List.generate(32, (i) => i));
      final hex = _bytesToHex(original);
      final decoded = _hexToBytes(hex);
      expect(decoded, equals(original));
    });

    test('empty bytes produce empty hex', () {
      expect(_bytesToHex(Uint8List(0)), '');
    });
  });

  group('SHA-256', () {
    test('produces 32-byte hash', () {
      final hash = _sha256(Uint8List.fromList(utf8.encode('test')));
      expect(hash.length, 32);
    });

    test('is deterministic', () {
      final data = Uint8List.fromList(utf8.encode('hello world'));
      expect(_sha256(data), equals(_sha256(data)));
    });

    test('different inputs produce different hashes', () {
      final h1 = _sha256(Uint8List.fromList(utf8.encode('a')));
      final h2 = _sha256(Uint8List.fromList(utf8.encode('b')));
      expect(h1, isNot(equals(h2)));
    });
  });

  group('PIN Generation Format', () {
    test('PIN is always 4 digits with leading zeros', () {
      // Simulate generatePin logic
      for (var i = 0; i < 100; i++) {
        final pin = i.toString().padLeft(4, '0');
        expect(pin.length, 4);
        expect(int.tryParse(pin), isNotNull);
      }
    });

    test('PIN 0 becomes 0000', () {
      expect(0.toString().padLeft(4, '0'), '0000');
    });

    test('PIN 1 becomes 0001', () {
      expect(1.toString().padLeft(4, '0'), '0001');
    });

    test('PIN 9999 stays 9999', () {
      expect(9999.toString().padLeft(4, '0'), '9999');
    });
  });
}
