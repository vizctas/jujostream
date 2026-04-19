import 'dart:async';
import 'package:logger/logger.dart';
import 'package:nsd/nsd.dart';
import '../../models/computer_details.dart';

class DiscoveryService {
  static const String _serviceType = '_nvstream._tcp';

  final Logger _log = Logger();
  final StreamController<ComputerDetails> _discoveryController =
      StreamController<ComputerDetails>.broadcast();

  Discovery? _discovery;
  final Map<String, ComputerDetails> _discoveredComputers = {};

  Stream<ComputerDetails> get onComputerFound => _discoveryController.stream;
  List<ComputerDetails> get discoveredComputers =>
      _discoveredComputers.values.toList();

  Future<void> startDiscovery() async {
    try {
      _log.i('Starting mDNS discovery for $_serviceType');

      _discovery = await startNsdDiscovery(_serviceType, autoResolve: true);

      _discovery!.addServiceListener((service, status) {
        if (status == ServiceStatus.found) {
          _handleServiceFound(service);
        }
      });
    } catch (e) {
      _log.e('Failed to start discovery: $e');
    }
  }

  void _handleServiceFound(Service service) {
    final address = service.host ?? '';
    if (address.isEmpty) return;

    // Normalize: strip trailing dot from mDNS hostnames (e.g. "mypc.local.")
    // and lower-case to avoid duplicate hostnames with different cases on macOS.
    final normalizedAddress = address.endsWith('.')
        ? address.substring(0, address.length - 1).toLowerCase()
        : address.toLowerCase();

    // Skip IPv6 link-local addresses — they cause duplicate entries on macOS
    // and are unreliable for HTTP polling.
    if (normalizedAddress.startsWith('fe80:') ||
        normalizedAddress.contains('%')) {
      _log.d('Skipping IPv6 link-local: $normalizedAddress');
      return;
    }

    _log.i(
      'Found service: ${service.name} at $normalizedAddress:${service.port}',
    );

    // Deduplicate: if we already have a computer at this address, skip.
    // On macOS, the same server often appears twice (server name + PC hostname).
    if (_discoveredComputers.containsKey(normalizedAddress)) {
      _log.d('Duplicate address $normalizedAddress — skipping');
      return;
    }

    final computer = ComputerDetails(
      name: service.name ?? 'Unknown',
      localAddress: normalizedAddress,
      externalPort: service.port ?? 47989,
      state: ComputerState.online,
    );

    _discoveredComputers[normalizedAddress] = computer;
    _discoveryController.add(computer);
  }

  Future<ComputerDetails?> addComputerManually(String address) async {
    _log.i('Adding computer manually: $address');

    final computer = ComputerDetails(
      name: 'Manual: $address',
      manualAddress: address,
      localAddress: address,
      state: ComputerState.unknown,
    );

    _discoveredComputers[address] = computer;
    _discoveryController.add(computer);
    return computer;
  }

  Future<void> stopDiscovery() async {
    try {
      if (_discovery != null) {
        await stopNsdDiscovery(_discovery!);
        _discovery = null;
      }
    } catch (e) {
      _log.e('Failed to stop discovery: $e');
    }
  }

  void removeComputer(String address) {
    _discoveredComputers.remove(address);
  }

  void dispose() {
    stopDiscovery();
    _discoveryController.close();
  }
}

Future<Discovery> startNsdDiscovery(String serviceType,
    {bool autoResolve = true}) {
  return startDiscovery(serviceType, autoResolve: autoResolve);
}

Future<void> stopNsdDiscovery(Discovery discovery) {
  return stopDiscovery(discovery);
}
