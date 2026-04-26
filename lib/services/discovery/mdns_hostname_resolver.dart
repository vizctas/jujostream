import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

class MdnsHostnameResolver {
  Future<List<InternetAddress>> resolve(
    String host, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final normalizedHost = _normalizeHost(host);
    if (!_shouldUseMdns(normalizedHost)) return const [];

    MDnsClient? client;
    final addresses = <InternetAddress>[];
    try {
      client = await _createClient();
      await client.start();
      await for (final record in client.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv4(normalizedHost),
        timeout: timeout,
      )) {
        addresses.add(record.address);
      }
      await for (final record in client.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv6(normalizedHost),
        timeout: timeout,
      )) {
        addresses.add(record.address);
      }
    } catch (e) {
      stderr.writeln(
        'MdnsHostnameResolver: lookup failed for $normalizedHost: $e',
      );
    } finally {
      client?.stop();
    }

    return filterUsableAddresses(addresses);
  }

  /// Builds an [MDnsClient] appropriate for the current platform.
  ///
  /// On Windows the default client binds to `0.0.0.0` which may send/receive
  /// multicast on a virtual or loopback adapter rather than the physical LAN
  /// adapter.  We enumerate non-loopback IPv4 interfaces and bind to the first
  /// usable one so queries actually reach the local network segment.
  static Future<MDnsClient> _createClient() async {
    if (!Platform.isWindows) return MDnsClient();

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      final lanAddr = interfaces
          .expand((iface) => iface.addresses)
          .where((a) => !a.isLoopback && !a.isLinkLocal)
          .firstOrNull;

      if (lanAddr != null) {
        return MDnsClient(
          rawDatagramSocketFactory:
              (
                dynamic host,
                int port, {
                bool reuseAddress = true,
                bool reusePort = false,
                int ttl = 1,
              }) => RawDatagramSocket.bind(
                lanAddr, // bind to LAN adapter, not 0.0.0.0
                port,
                reuseAddress: true,
                reusePort: false, // SO_REUSEPORT not available on Windows
                ttl: ttl,
              ),
        );
      }
    } catch (e) {
      stderr.writeln(
        'MdnsHostnameResolver: interface enumeration failed on Windows ($e),'
        ' falling back to default MDnsClient',
      );
    }
    return MDnsClient();
  }

  static String _normalizeHost(String host) {
    final trimmed = host.trim().toLowerCase();
    return trimmed.endsWith('.')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  static bool _shouldUseMdns(String host) {
    return host.endsWith('.local') && InternetAddress.tryParse(host) == null;
  }

  static List<InternetAddress> filterUsableAddresses(
    Iterable<InternetAddress> addresses,
  ) {
    final seen = <String>{};
    final result = <InternetAddress>[];
    for (final address in addresses) {
      if (address.isLoopback) continue;
      if (address.address.toLowerCase().startsWith('fe80:')) continue;
      if (address.address.contains('%')) continue;
      if (seen.add(address.address)) result.add(address);
    }
    result.sort((a, b) {
      if (a.type == b.type) return 0;
      return a.type == InternetAddressType.IPv4 ? -1 : 1;
    });
    return result;
  }
}
