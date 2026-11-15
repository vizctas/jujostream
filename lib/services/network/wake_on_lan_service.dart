import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

class WakeOnLanService {
  static const List<int> defaultPorts = <int>[9, 7, 47998, 48000];

  /// Returns true only when [mac] is a valid 6-byte MAC address and is neither
  /// the placeholder `00:00:00:00:00:00` nor broadcast `FF:FF:FF:FF:FF:FF`.
  static bool isValidMac(String? mac) {
    if (mac == null || mac.trim().isEmpty) return false;
    final bytes = parseMac(mac.trim());
    if (bytes == null || bytes.length != 6) return false;
    final allZero = bytes.every((b) => b == 0x00);
    final allFf = bytes.every((b) => b == 0xFF);
    return !allZero && !allFf;
  }

  /// Strips scheme (`http://`, `https://`), path, and `:port` suffix from an
  /// IPv4 address, hostname, or bracketed IPv6 literal.
  @visibleForTesting
  static String cleanHost(String? rawAddress) {
    if (rawAddress == null) return '';
    var s = rawAddress.trim();
    if (s.isEmpty) return '';
    if (s.startsWith('https://')) {
      s = s.substring(8);
    } else if (s.startsWith('http://')) {
      s = s.substring(7);
    }
    final slashIdx = s.indexOf('/');
    if (slashIdx >= 0) {
      s = s.substring(0, slashIdx);
    }
    if (s.startsWith('[')) {
      final endBracket = s.indexOf(']');
      if (endBracket > 1) {
        return s.substring(1, endBracket);
      }
    }
    final firstColon = s.indexOf(':');
    final lastColon = s.lastIndexOf(':');
    if (firstColon > 0 && firstColon == lastColon) {
      final portPart = s.substring(lastColon + 1);
      if (int.tryParse(portPart) != null) {
        return s.substring(0, lastColon);
      }
    }
    return s;
  }

  /// Computes the `/24` directed broadcast (`a.b.c.255`) for a private/LAN IPv4
  /// address, or null if [rawAddress] is not a unicast IPv4 literal.
  @visibleForTesting
  static String? subnetBroadcastForIp(String? rawAddress) {
    final host = cleanHost(rawAddress);
    if (host.isEmpty) return null;
    final parts = host.split('.');
    if (parts.length != 4) return null;
    final octets = <int>[];
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255) return null;
      octets.add(v);
    }
    if (octets[0] == 127 || octets[0] == 0 || octets[0] >= 224) return null;
    return '${octets[0]}.${octets[1]}.${octets[2]}.255';
  }

  static Future<void> send(
    String macAddress, {
    String? localAddress,
    String? remoteAddress,
    List<int> ports = defaultPorts,
  }) async {
    if (!isValidMac(macAddress)) return;
    final mac = parseMac(macAddress)!;
    final magic = buildMagicPacket(mac);

    final targetIps = <String>{'255.255.255.255'};

    for (final raw in <String?>[localAddress, remoteAddress]) {
      final host = cleanHost(raw);
      if (host.isEmpty) continue;
      final parsed = InternetAddress.tryParse(host);
      if (parsed != null && parsed.type == InternetAddressType.IPv4) {
        if (!host.startsWith('127.') && host != '0.0.0.0') {
          targetIps.add(host);
        }
        final bcast = subnetBroadcastForIp(host);
        if (bcast != null) {
          targetIps.add(bcast);
        }
      } else if (parsed == null) {
        try {
          final resolved = await InternetAddress.lookup(
            host,
            type: InternetAddressType.IPv4,
          ).timeout(const Duration(seconds: 2));
          for (final addr in resolved) {
            if (!addr.isLoopback) {
              targetIps.add(addr.address);
              final bcast = subnetBroadcastForIp(addr.address);
              if (bcast != null) targetIps.add(bcast);
            }
          }
        } catch (_) {}
      }
    }

    final interfaceIps = <InternetAddress>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            interfaceIps.add(addr);
            final bcast = subnetBroadcastForIp(addr.address);
            if (bcast != null) {
              targetIps.add(bcast);
            }
          }
        }
      }
    } catch (_) {}

    Future<void> sendFromSocket(
      InternetAddress bindAddress,
      Iterable<String> destinations,
    ) async {
      RawDatagramSocket? socket;
      try {
        socket = await RawDatagramSocket.bind(bindAddress, 0);
        socket.broadcastEnabled = true;
        for (var burst = 0; burst < 3; burst++) {
          for (final ip in destinations) {
            final dest = InternetAddress.tryParse(ip);
            if (dest == null) continue;
            for (final port in ports) {
              try {
                socket.send(magic, dest, port);
              } catch (_) {}
            }
          }
        }
      } catch (_) {
      } finally {
        socket?.close();
      }
    }

    await sendFromSocket(InternetAddress.anyIPv4, targetIps);

    for (final ifaceAddr in interfaceIps) {
      final ifaceTargets = <String>{'255.255.255.255'};
      final bcast = subnetBroadcastForIp(ifaceAddr.address);
      if (bcast != null) ifaceTargets.add(bcast);
      final cleanLocal = cleanHost(localAddress);
      if (cleanLocal.isNotEmpty) ifaceTargets.add(cleanLocal);
      await sendFromSocket(ifaceAddr, ifaceTargets);
    }
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
