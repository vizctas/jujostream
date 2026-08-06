import 'dart:async';
import 'dart:io';

import 'package:logger/logger.dart';

import '../diagnostics_logger.dart';
import 'package:nsd/nsd.dart';

import '../../models/computer_details.dart';
import 'mdns_hostname_resolver.dart';

typedef DiscoveryStarter =
    Future<Discovery> Function(
      String serviceType, {
      required bool autoResolve,
      required IpLookupType ipLookupType,
    });

typedef DiscoveryStopper = Future<void> Function(Discovery discovery);

class DiscoveryFailure {
  const DiscoveryFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

class DiscoveryService {
  static const String _serviceType = '_nvstream._tcp';

  DiscoveryService({
    DiscoveryStarter? discoveryStarter,
    DiscoveryStopper? discoveryStopper,
    MdnsHostnameResolver? hostnameResolver,
  }) : _discoveryStarter = discoveryStarter ?? startNsdDiscovery,
       _discoveryStopper = discoveryStopper ?? stopNsdDiscovery,
       _hostnameResolver = hostnameResolver ?? MdnsHostnameResolver();

  final Logger _log = diagnosticsLogger('Discovery');
  final DiscoveryStarter _discoveryStarter;
  final DiscoveryStopper _discoveryStopper;
  final MdnsHostnameResolver _hostnameResolver;
  final StreamController<ComputerDetails> _discoveryController =
      StreamController<ComputerDetails>.broadcast();
  final StreamController<DiscoveryFailure> _failureController =
      StreamController<DiscoveryFailure>.broadcast();

  Discovery? _discovery;
  Future<void>? _startOperation;
  bool _disposed = false;
  final Map<String, ComputerDetails> _discoveredComputers = {};

  Stream<ComputerDetails> get onComputerFound => _discoveryController.stream;
  Stream<DiscoveryFailure> get onDiscoveryFailure => _failureController.stream;
  List<ComputerDetails> get discoveredComputers =>
      _discoveredComputers.values.toList(growable: false);
  bool get isActive => _discovery != null;

  Future<void> startDiscovery() {
    if (_disposed || _discovery != null) return Future<void>.value();
    final activeStart = _startOperation;
    if (activeStart != null) return activeStart;

    late final Future<void> operation;
    operation = _start().whenComplete(() {
      if (identical(_startOperation, operation)) {
        _startOperation = null;
      }
    });
    _startOperation = operation;
    return operation;
  }

  Future<void> _start() async {
    try {
      _log.i('Starting mDNS discovery for $_serviceType');
      final discovery = await _discoveryStarter(
        _serviceType,
        autoResolve: true,
        ipLookupType: IpLookupType.any,
      );

      if (_disposed) {
        await _discoveryStopper(discovery);
        return;
      }

      _discovery = discovery;
      discovery.addServiceListener((service, status) {
        if (status == ServiceStatus.found) {
          unawaited(_handleServiceFound(service));
        }
      });
      for (final service in discovery.services) {
        unawaited(_handleServiceFound(service));
      }
    } catch (error, stackTrace) {
      _discovery = null;
      if (!_failureController.isClosed) {
        _failureController.add(DiscoveryFailure(error, stackTrace));
      }
      _log.e('Failed to start discovery: $error');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _handleServiceFound(Service service) async {
    if (_disposed) return;

    final resolvedIps = MdnsHostnameResolver.filterUsableAddresses(
      service.addresses ?? const [],
    );

    late final String normalizedAddress;
    if (resolvedIps.isNotEmpty) {
      normalizedAddress = resolvedIps.first.address;
      _log.d('Using NSD address $normalizedAddress for ${service.name}');
    } else {
      final raw = service.host?.trim() ?? '';
      if (raw.isEmpty) return;

      final normalized = raw.endsWith('.')
          ? raw.substring(0, raw.length - 1).toLowerCase()
          : raw.toLowerCase();
      final parsed = InternetAddress.tryParse(normalized);

      if (parsed != null) {
        final usable = MdnsHostnameResolver.filterUsableAddresses([parsed]);
        if (usable.isEmpty) {
          _log.w('Rejected unusable mDNS address for ${service.name}');
          return;
        }
        normalizedAddress = usable.first.address;
      } else if (normalized.endsWith('.local')) {
        final fallback = await _hostnameResolver.resolve(normalized);
        if (fallback.isEmpty) {
          _log.w('No usable address resolved for ${service.name}');
          return;
        }
        normalizedAddress = fallback.first.address;
      } else {
        normalizedAddress = normalized;
      }
    }

    _log.i(
      'Found service: ${service.name} at $normalizedAddress:${service.port}',
    );

    if (_discoveredComputers.containsKey(normalizedAddress)) {
      _log.d('Duplicate address $normalizedAddress - skipping');
      return;
    }

    final computer = ComputerDetails(
      name: service.name ?? 'Unknown',
      localAddress: normalizedAddress,
      externalPort: service.port ?? 47989,
      state: ComputerState.online,
    );

    _discoveredComputers[normalizedAddress] = computer;
    if (!_discoveryController.isClosed) {
      _discoveryController.add(computer);
    }
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
    if (!_discoveryController.isClosed) {
      _discoveryController.add(computer);
    }
    return computer;
  }

  Future<void> stopDiscovery() async {
    final pendingStart = _startOperation;
    if (pendingStart != null) {
      try {
        await pendingStart;
      } catch (_) {
        return;
      }
    }

    final discovery = _discovery;
    _discovery = null;
    // Forget what was seen in this session. The cache is keyed by address and
    // never expired, so after one app-switch every re-found service hit the
    // duplicate check and stopped being emitted — LAN rediscovery was dead for
    // the rest of the process lifetime.
    _discoveredComputers.clear();
    if (discovery == null) return;

    try {
      await _discoveryStopper(discovery);
      _log.i('Stopped mDNS discovery for $_serviceType');
    } catch (error, stackTrace) {
      if (!_failureController.isClosed) {
        _failureController.add(DiscoveryFailure(error, stackTrace));
      }
      _log.e('Failed to stop discovery: $error');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void removeComputer(String address) {
    _discoveredComputers.remove(address);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(() async {
      try {
        await stopDiscovery();
      } catch (_) {
        // The failure was already emitted through onDiscoveryFailure.
      } finally {
        await _discoveryController.close();
        await _failureController.close();
      }
    }());
  }
}

Future<Discovery> startNsdDiscovery(
  String serviceType, {
  required bool autoResolve,
  required IpLookupType ipLookupType,
}) {
  return startDiscovery(
    serviceType,
    autoResolve: autoResolve,
    ipLookupType: ipLookupType,
  );
}

Future<void> stopNsdDiscovery(Discovery discovery) {
  return stopDiscovery(discovery);
}
