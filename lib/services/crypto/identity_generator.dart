import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

// Minimal ASN.1 DER encoder for self-signed X.509 certs (RSA-2048, SHA256).
// Matches Moonlight's identity format: CN=NVIDIA GameStream Client, 20yr validity.

// -- OIDs --
final _oidSha256Rsa = Uint8List.fromList([
  0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b,
]);
final _oidRsa = Uint8List.fromList([
  0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
]);
final _oidCn = Uint8List.fromList([0x06, 0x03, 0x55, 0x04, 0x03]);

// -- DER primitives --
Uint8List _derLen(int n) {
  if (n < 0x80) return Uint8List.fromList([n]);
  if (n < 0x100) return Uint8List.fromList([0x81, n]);
  return Uint8List.fromList([0x82, (n >> 8) & 0xff, n & 0xff]);
}

Uint8List _derTag(int tag, Uint8List body) {
  final len = _derLen(body.length);
  final out = BytesBuilder();
  out.addByte(tag);
  out.add(len);
  out.add(body);
  return out.toBytes();
}

Uint8List _derSeq(List<Uint8List> items) {
  final body = BytesBuilder();
  for (final i in items) {
    body.add(i);
  }
  return _derTag(0x30, body.toBytes());
}

Uint8List _derSet(List<Uint8List> items) {
  final body = BytesBuilder();
  for (final i in items) {
    body.add(i);
  }
  return _derTag(0x31, body.toBytes());
}

Uint8List _derInt(BigInt v) {
  var bytes = _bigIntBytes(v);
  if (bytes[0] & 0x80 != 0) {
    bytes = Uint8List.fromList([0, ...bytes]);
  }
  return _derTag(0x02, bytes);
}

Uint8List _derBitStr(Uint8List data) {
  final body = Uint8List(data.length + 1);
  body[0] = 0; // no unused bits
  body.setRange(1, body.length, data);
  return _derTag(0x03, body);
}

Uint8List _derOctetStr(Uint8List data) => _derTag(0x04, data);

Uint8List _derUtf8(String s) =>
    _derTag(0x0c, Uint8List.fromList(s.codeUnits));

Uint8List _derNull() => Uint8List.fromList([0x05, 0x00]);

Uint8List _derExplicit(int tag, Uint8List inner) {
  return _derTag(0xa0 | tag, inner);
}

Uint8List _derUtcTime(DateTime dt) {
  final s = '${_p2(dt.year % 100)}${_p2(dt.month)}${_p2(dt.day)}'
      '${_p2(dt.hour)}${_p2(dt.minute)}${_p2(dt.second)}Z';
  return _derTag(0x17, Uint8List.fromList(s.codeUnits));
}

String _p2(int v) => v.toString().padLeft(2, '0');

Uint8List _bigIntBytes(BigInt v) {
  final hex = v.toRadixString(16);
  final padded = hex.length.isOdd ? '0$hex' : hex;
  final out = Uint8List(padded.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(padded.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

// -- Key & Cert generation --

class GeneratedIdentity {
  final String uniqueId;
  final String certPem;
  final String keyPem;
  GeneratedIdentity(this.uniqueId, this.certPem, this.keyPem);
}

GeneratedIdentity generateDeviceIdentity() {
  final rng = FortunaRandom();
  final seed = Uint8List(32);
  final r = Random.secure();
  for (var i = 0; i < 32; i++) {
    seed[i] = r.nextInt(256);
  }
  rng.seed(KeyParameter(seed));

  // uniqueId: 16 hex chars
  final uidBytes = rng.nextBytes(8);
  final uid = uidBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  // RSA-2048 keypair
  final keyGen = RSAKeyGenerator()
    ..init(ParametersWithRandom(
      RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
      rng,
    ));
  final pair = keyGen.generateKeyPair();
  final pub = pair.publicKey;
  final priv = pair.privateKey;

  // Self-signed X.509
  final now = DateTime.now().toUtc();
  final exp = DateTime.utc(now.year + 20, now.month, now.day);

  final serialBytes = rng.nextBytes(8);
  var serial = BigInt.zero;
  for (final b in serialBytes) {
    serial = (serial << 8) | BigInt.from(b);
  }
  serial = serial.abs();
  if (serial == BigInt.zero) serial = BigInt.one;

  // Name: CN=NVIDIA GameStream Client
  final cn = _derSeq([_oidCn, _derUtf8('NVIDIA GameStream Client')]);
  final rdnSeq = _derSeq([_derSet([cn])]);

  // SubjectPublicKeyInfo
  final algRsa = _derSeq([_oidRsa, _derNull()]);
  final pubKeyDer = _derSeq([_derInt(pub.modulus!), _derInt(pub.exponent!)]);
  final spki = _derSeq([algRsa, _derBitStr(pubKeyDer)]);

  // TBSCertificate
  final algSha256Rsa = _derSeq([_oidSha256Rsa, _derNull()]);
  final validity = _derSeq([_derUtcTime(now), _derUtcTime(exp)]);
  final tbs = _derSeq([
    _derExplicit(0, _derInt(BigInt.from(2))), // v3
    _derInt(serial),
    algSha256Rsa,
    rdnSeq, // issuer
    validity,
    rdnSeq, // subject
    spki,
  ]);

  // Sign TBS
  final signer = Signer('SHA-256/RSA');
  signer.init(true, PrivateKeyParameter<RSAPrivateKey>(priv));
  final sig = signer.generateSignature(tbs) as RSASignature;
  final sigBytes = sig.bytes;

  // Full certificate DER
  final certDer = _derSeq([tbs, algSha256Rsa, _derBitStr(sigBytes)]);
  final certPem = _toPem(certDer, 'CERTIFICATE');

  // PKCS#8 private key PEM
  final privDer = _derSeq([
    _derInt(BigInt.zero), // version
    algRsa,
    _derOctetStr(_derSeq([
      _derInt(BigInt.zero), // version
      _derInt(priv.modulus!),
      _derInt(priv.publicExponent!),
      _derInt(priv.privateExponent!),
      _derInt(priv.p!),
      _derInt(priv.q!),
      _derInt(priv.privateExponent! % (priv.p! - BigInt.one)), // dp
      _derInt(priv.privateExponent! % (priv.q! - BigInt.one)), // dq
      _derInt(priv.q!.modInverse(priv.p!)), // qInv
    ])),
  ]);
  final keyPemStr = _toPem(privDer, 'PRIVATE KEY');

  return GeneratedIdentity(uid, certPem, keyPemStr);
}

String _toPem(Uint8List der, String label) {
  final b64 = base64Encode(der);
  final lines = <String>['-----BEGIN $label-----'];
  for (var i = 0; i < b64.length; i += 64) {
    final end = (i + 64 < b64.length) ? i + 64 : b64.length;
    lines.add(b64.substring(i, end));
  }
  lines.add('-----END $label-----');
  return lines.join('\n');
}
