import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

class WakeOnLanService {
  static Future<void> send(String macAddress) async {
    final mac = parseMac(macAddress);
    if (mac == null) return;

    final magic = buildMagicPacket(mac);
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;

    socket.send(magic, InternetAddress('255.255.255.255'), 9);
    socket.send(magic, InternetAddress('255.255.255.255'), 7);

    socket.close();
  }

  @visibleForTesting
  static List<int>? parseMac(String mac) {

    final clean = mac.replaceAll(RegExp(r'[:\-]'), '');
    if (clean.length != 12) return null;
    final bytes = <int>[];
    for (var i = 0; i < 12; i += 2) {
      final byte = int.tryParse(clean.substring(i, i + 2), radix: 16);
      if (byte == null) return null;
      bytes.add(byte);
    }
    return bytes;
  }

  @visibleForTesting
  static List<int> buildMagicPacket(List<int> mac) {
    return [...List.filled(6, 0xFF), for (var i = 0; i < 16; i++) ...mac];
  }
}
