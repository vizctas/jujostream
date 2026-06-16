import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart';

import '../../models/notification_mirror_pairing.dart';
import '../companion/companion_server.dart';
import '../crypto/client_identity.dart';
import '../discovery/mdns_hostname_resolver.dart';
import 'notification_mirror_controller.dart';

class NotificationMirrorDiscoveryService {
  NotificationMirrorDiscoveryService._();

  static final instance = NotificationMirrorDiscoveryService._();
  static const serviceType = '_jujo-notify._tcp';

  final StreamController<DiscoveredNotificationBroadcaster> _foundController =
      StreamController<DiscoveredNotificationBroadcaster>.broadcast();
  final Map<String, DiscoveredNotificationBroadcaster> _found = {};

  Registration? _registration;
  Discovery? _discovery;

  Stream<DiscoveredNotificationBroadcaster> get onBroadcasterFound =>
      _foundController.stream;
  List<DiscoveredNotificationBroadcaster> get foundBroadcasters {
    final list = _found.values.toList()
      ..sort((a, b) => a.deviceName.compareTo(b.deviceName));
    return list;
  }

  Future<void> updateAdvertising(
    NotificationMirrorController controller,
  ) async {
    if (controller.mode.canBroadcast && controller.broadcastAvailable) {
      await startAdvertising(controller.mode);
    } else {
      await stopAdvertising();
    }
  }

  Future<void> startAdvertising(NotificationMirrorMode mode) async {
    if (_registration != null) return;
    try {
      final lanUrl = await CompanionServer.instance.lanUrl;
      final port = Uri.tryParse(lanUrl ?? '')?.port ?? CompanionServer.port;
      final txt = _txt({
        'deviceId': ClientIdentity.uniqueId,
        'deviceName': Platform.localHostname.isNotEmpty
            ? Platform.localHostname
            : 'Jujo Device',
        'role': mode == NotificationMirrorMode.both ? 'both' : 'broadcaster',
        'apiVersion': '1',
        'port': port.toString(),
      });
      _registration = await register(
        Service(
          name: 'JUJO ${ClientIdentity.uniqueId}',
          type: serviceType,
          port: port,
          txt: txt,
        ),
      );
      debugPrint('[NotificationMirrorDiscovery] advertising $serviceType');
    } catch (e) {
      debugPrint('[NotificationMirrorDiscovery] advertise failed: $e');
    }
  }

  Future<void> stopAdvertising() async {
    final registration = _registration;
    _registration = null;
    if (registration == null) return;
    try {
      await unregister(registration);
    } catch (e) {
      debugPrint('[NotificationMirrorDiscovery] unregister failed: $e');
    }
  }

  Future<void> startScan() async {
    if (_discovery != null) return;
    _found.clear();
    try {
      _discovery = await startDiscovery(serviceType, autoResolve: true);
      _discovery!.addServiceListener((service, status) {
        if (status != ServiceStatus.found) return;
        final record = DiscoveredNotificationBroadcaster.fromNsd(
          host: service.host,
          port: service.port,
          txt: service.txt,
          addresses: MdnsHostnameResolver.filterUsableAddresses(
            service.addresses ?? const [],
          ),
        );
        if (record == null || record.deviceId == ClientIdentity.uniqueId) {
          return;
        }
        _found[record.deviceId] = record;
        _foundController.add(record);
      });
    } catch (e) {
      debugPrint('[NotificationMirrorDiscovery] scan failed: $e');
    }
  }

  Future<void> stopScan() async {
    final discovery = _discovery;
    _discovery = null;
    if (discovery == null) return;
    try {
      await stopDiscovery(discovery);
    } catch (e) {
      debugPrint('[NotificationMirrorDiscovery] stop scan failed: $e');
    }
  }

  Map<String, Uint8List?> _txt(Map<String, String> values) {
    return values.map(
      (key, value) => MapEntry(key, Uint8List.fromList(utf8.encode(value))),
    );
  }
}
