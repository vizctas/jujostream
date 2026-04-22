import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/computer_details.dart';
import '../models/nv_app.dart';
import '../services/discovery/discovery_service.dart';
import '../services/network/wake_on_lan_service.dart';
import '../services/http_api/nv_http_client.dart';
import '../services/pairing/pairing_service.dart';
import '../services/database/achievement_service.dart';
import '../services/database/session_history_service.dart';

class ComputerProvider extends ChangeNotifier with WidgetsBindingObserver {
  final DiscoveryService _discoveryService = DiscoveryService();
  final NvHttpClient _httpClient = NvHttpClient();
  final PairingService _pairingService = PairingService();

  final List<ComputerDetails> _computers = [];
  static const String _computersStorageKey = 'saved_computers';
  static const String _primaryServerKey = 'primary_server_uuid';
  bool _isDiscovering = false;
  bool _isPairing = false;
  String? _error;
  Timer? _pollTimer;

  String? _primaryServerUuid;

  /// Consecutive poll-failure count per computer UUID.
  /// Requires [_kOfflineThreshold] consecutive failures before marking offline.
  /// Prevents transient failures (e.g. after session close) from flipping state.
  final Map<String, int> _pollFailCount = {};
  static const int _kOfflineThreshold = 2;

  NvApp? _activeSessionApp;
  ComputerDetails? _activeSessionComputer;
  DateTime? _activeSessionStart;

  NvApp? get activeSessionApp => _activeSessionApp;
  ComputerDetails? get activeSessionComputer => _activeSessionComputer;
  DateTime? get activeSessionStart => _activeSessionStart;

  void setActiveSession(ComputerDetails computer, NvApp app) {
    _activeSessionApp = app;
    _activeSessionComputer = computer;
    _activeSessionStart = DateTime.now();
    notifyListeners();
  }

  void clearActiveSession() {
    if (_activeSessionApp == null) return;

    unawaited(
      SessionHistoryService.insertSession(
        appId: _activeSessionApp!.appId,
        appName: _activeSessionApp!.appName,
        serverId: _activeSessionComputer?.uuid ?? 'unknown',
        serverName: _activeSessionComputer?.name ?? 'Unknown',
        startTime: _activeSessionStart ?? DateTime.now(),
        endTime: DateTime.now(),
      ),
    );
    _activeSessionApp = null;
    _activeSessionComputer = null;
    _activeSessionStart = null;
    notifyListeners();
  }

  static const Duration _activePollInterval = Duration(seconds: 3);
  static const Duration _idlePollInterval = Duration(seconds: 30);
  static const Duration _pollTimeout = Duration(seconds: 2);
  bool _appInForeground = true;

  List<ComputerDetails> get computers => List.unmodifiable(_computers);
  bool get isDiscovering => _isDiscovering;
  bool get isPairing => _isPairing;

  String? get error => _error;

  String? get primaryServerUuid => _primaryServerUuid;

  ComputerDetails? get primaryServer {
    if (_primaryServerUuid == null) return null;
    try {
      return _computers.firstWhere((c) => c.uuid == _primaryServerUuid);
    } catch (_) {
      return null;
    }
  }

  Future<void> setPrimaryServer(String uuid) async {
    _primaryServerUuid = uuid;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_primaryServerKey, uuid);
  }

  Future<void> clearPrimaryServer() async {
    _primaryServerUuid = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_primaryServerKey);
  }

  ComputerProvider() {
    WidgetsBinding.instance.addObserver(this);
    _loadPersistedComputers();
    _discoveryService.onComputerFound.listen(_onComputerDiscovered);
    _startAdaptivePoll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;

    if (_appInForeground) {
      // Always restart the timer on resume — even if it was already running.
      // This prevents the "poll never checks back" bug where the timer was
      // cancelled but the state flag didn't change.
      _startAdaptivePoll();
      // Trigger an immediate poll so the UI updates without waiting for the
      // next timer tick (3s).
      _pollAll();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _startAdaptivePoll() {
    _pollTimer?.cancel();
    final interval = _appInForeground ? _activePollInterval : _idlePollInterval;
    _pollTimer = Timer.periodic(interval, (_) => _pollAll());
  }

  Future<void> _pollAll() async {
    if (_isPairing || _computers.isEmpty || !_appInForeground) return;
    final snapshot = List<ComputerDetails>.from(_computers);
    // Poll all computers in parallel instead of sequentially.
    // Sequential polling with 5s timeouts caused extreme slowness on macOS
    // when any server was unreachable.
    await Future.wait(
      snapshot.map((computer) => pollComputer(computer)),
      eagerError: false,
    );
  }

  Future<void> _loadPersistedComputers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _primaryServerUuid = prefs.getString(_primaryServerKey);
      final jsonList = prefs.getStringList(_computersStorageKey) ?? const [];
      if (jsonList.isEmpty) {
        return;
      }

      _computers
        ..clear()
        ..addAll(
          jsonList.map((entry) {
            final map = jsonDecode(entry) as Map<String, dynamic>;
            final computer = ComputerDetails.fromJson(map);
            computer.state = ComputerState.unknown;

            if (computer.pairState == PairState.paired &&
                computer.serverCert.isNotEmpty) {
              computer.pairStatusFromHttps = true;
            }
            return computer;
          }),
        );
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persistComputers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _computers
          .map((computer) => jsonEncode(computer.toJson()))
          .toList(growable: false);
      await prefs.setStringList(_computersStorageKey, jsonList);
    } catch (_) {}
  }

  Future<void> startDiscovery() async {
    _isDiscovering = true;
    _error = null;
    notifyListeners();

    try {
      await _discoveryService.startDiscovery();
    } catch (e) {
      _error = 'Discovery failed: $e';
      notifyListeners();
    }
  }

  Future<void> stopDiscovery() async {
    await _discoveryService.stopDiscovery();
    _isDiscovering = false;
    notifyListeners();
  }

  Future<void> sendWakeOnLan(ComputerDetails computer) async {
    if (computer.macAddress.isEmpty) return;
    await WakeOnLanService.send(computer.macAddress);
  }

  Future<bool> sendWakeOnLanWithFeedback(
    ComputerDetails computer, {
    required void Function(String status) onStatus,
    Duration timeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    if (computer.macAddress.isEmpty) {
      onStatus('No MAC address configured');
      return false;
    }
    onStatus('Sending magic packet…');
    await WakeOnLanService.send(computer.macAddress);

    final dl = DateTime.now().add(timeout);
    int elapsed = 0;
    while (DateTime.now().isBefore(dl)) {
      await Future<void>.delayed(pollInterval);
      elapsed += pollInterval.inSeconds;
      onStatus('Waiting for response… (${elapsed}s)');
      try {
        final address = computer.activeAddress.isNotEmpty
            ? computer.activeAddress
            : computer.localAddress;
        final info = await _httpClient.getServerInfoHttps(
          address,
          httpsPort: computer.httpsPort > 0
              ? computer.httpsPort
              : NvHttpClient.defaultHttpsPort,
          httpPort: computer.externalPort > 0
              ? computer.externalPort
              : NvHttpClient.defaultHttpPort,
        );
        if (info != null) {
          onStatus('PC is online!');
          return true;
        }
      } catch (_) {}
    }
    onStatus('Timed out — PC did not respond');
    return false;
  }

  Future<void> addComputerManually(String rawAddress) async {
    _error = null;
    notifyListeners();

    final String host;
    final int port;
    final colonIdx = rawAddress.lastIndexOf(':');
    if (colonIdx > 0) {
      final maybePart = rawAddress.substring(0, colonIdx);
      final portStr = rawAddress.substring(colonIdx + 1);
      final parsedPort = int.tryParse(portStr);
      if (parsedPort != null && parsedPort > 0 && parsedPort < 65536) {
        host = maybePart;
        port = parsedPort;
      } else {
        host = rawAddress;
        port = 47989;
      }
    } else {
      host = rawAddress;
      port = 47989;
    }

    try {
      final serverInfo = await _httpClient.getServerInfoHttps(
        host,
        httpsPort: NvHttpClient.defaultHttpsPort,
        httpPort: port,
      );
      if (serverInfo != null) {
        serverInfo.manualAddress = host;
        _addOrUpdateComputer(serverInfo);
      } else {
        final computer = ComputerDetails(
          name: host,
          localAddress: host,
          manualAddress: host,
          externalPort: port,
          state: ComputerState.offline,
        );
        _addOrUpdateComputer(computer);
      }
    } catch (e) {
      _error = 'Failed to add computer: $e';
      notifyListeners();
    }
  }

  Future<void> pollComputer(ComputerDetails computer) async {
    final address = computer.activeAddress.isNotEmpty
        ? computer.activeAddress
        : computer.localAddress;

    final httpPort = computer.externalPort > 0
        ? computer.externalPort
        : NvHttpClient.defaultHttpPort;
    final httpsPort = computer.httpsPort > 0
        ? computer.httpsPort
        : NvHttpClient.defaultHttpsPort;

    final serverInfo = await _httpClient.getServerInfoHttps(
      address,
      httpsPort: httpsPort,
      httpPort: httpPort,
      timeout: _pollTimeout,
    );

    if (serverInfo != null) {
      serverInfo.manualAddress = computer.manualAddress;
      if (serverInfo.serverCert.isEmpty && computer.serverCert.isNotEmpty) {
        serverInfo.serverCert = computer.serverCert;
      }
      _pollFailCount[computer.uuid] = 0;
      _addOrUpdateComputer(serverInfo);
    } else {
      final key = computer.uuid.isNotEmpty
          ? computer.uuid
          : computer.localAddress;
      final count = (_pollFailCount[key] ?? 0) + 1;
      _pollFailCount[key] = count;
      if (count >= _kOfflineThreshold) {
        computer.state = ComputerState.offline;
        _persistComputers();
        notifyListeners();
      }
    }
  }

  void removeComputer(ComputerDetails computer) {
    _computers.removeWhere(
      (c) => c.uuid == computer.uuid || c.localAddress == computer.localAddress,
    );

    _persistComputers();
    notifyListeners();

    final discovered = _discoveryService.discoveredComputers;
    for (final d in discovered) {
      if (d.localAddress == computer.localAddress) {
        Future.microtask(() => _onComputerDiscovered(d));
        break;
      }
    }
  }

  String generatePairingPin() {
    return _pairingService.generatePin();
  }

  /// Aborts the in-progress [pairComputer] call as soon as possible.
  /// Called by the UI when the app is sent to background during pairing
  /// so the Phase 2 long-poll retry loop exits cleanly.
  void cancelActivePairing() {
    _pairingService.requestCancel();
  }

  Future<PairingResult> pairComputer(
    ComputerDetails computer,
    String pin,
  ) async {
    final wasDiscovering = _isDiscovering;
    if (wasDiscovering) {
      await stopDiscovery();
    }

    _isPairing = true;
    computer.pairState = PairState.alreadyInProgress;
    _error = null;
    notifyListeners();

    try {
      final result = await _pairingService.pair(computer, pin);

      _isPairing = false;
      if (result.paired) {
        computer.pairState = PairState.paired;
        computer.serverCert = result.serverCert ?? computer.serverCert;

        computer.pairStatusFromHttps = true;

        // Persist immediately so the paired state survives even if
        // the subsequent pollComputer() call fails or times out.
        _persistComputers();
        notifyListeners();

        unawaited(AchievementService.instance.unlock('first_connection'));
        await pollComputer(computer);
      } else {
        computer.pairState = PairState.failed;
        _error = result.error ?? 'Pairing failed';
        _persistComputers();
        notifyListeners();
      }

      return result;
    } finally {
      _isPairing = false;
      if (wasDiscovering) {
        await startDiscovery();
      }
    }
  }

  /// Verifies that [computer] is still paired by performing a fresh HTTPS
  /// `/serverinfo` request. Returns `true` if the server confirms pairing,
  /// `false` if the server says "not paired" or the check fails.
  ///
  /// When the server reports "not paired", the local state is updated
  /// immediately (pairState → notPaired, serverCert cleared, persisted).
  ///
  /// This is used as an entry gate before navigating into a server's app
  /// list, preventing the user from entering a server that revoked pairing.
  Future<bool> verifyPairing(ComputerDetails computer) async {
    if (!computer.isPaired) return false;

    final address = computer.activeAddress.isNotEmpty
        ? computer.activeAddress
        : computer.localAddress;
    final httpsPort = computer.httpsPort > 0
        ? computer.httpsPort
        : NvHttpClient.defaultHttpsPort;
    final httpPort = computer.externalPort > 0
        ? computer.externalPort
        : NvHttpClient.defaultHttpPort;

    try {
      final info = await _httpClient.getServerInfoHttps(
        address,
        httpsPort: httpsPort,
        httpPort: httpPort,
        timeout: const Duration(seconds: 3),
      );
      if (info == null) {
        // Server unreachable — can't verify. Allow entry optimistically
        // (the stream will fail with a clear error if truly unpaired).
        return true;
      }
      if (info.pairState == PairState.paired) {
        return true;
      }
      // Server confirmed: NOT paired. Update local state.
      computer.pairState = PairState.notPaired;
      computer.serverCert = '';
      computer.pairStatusFromHttps = false;
      _persistComputers();
      notifyListeners();
      return false;
    } catch (_) {
      // Network error — allow entry optimistically.
      return true;
    }
  }

  Future<bool> unpairComputer(ComputerDetails computer) async {
    final success = await _pairingService.unpair(computer);
    if (success) {
      computer.pairState = PairState.notPaired;
      computer.serverCert = '';
      _persistComputers();
      notifyListeners();
    }
    return success;
  }

  void _onComputerDiscovered(ComputerDetails computer) async {
    if (_isPairing) {
      return;
    }

    final httpPort = computer.externalPort > 0 ? computer.externalPort : 47989;
    final httpsPort = computer.httpsPort > 0
        ? computer.httpsPort
        : NvHttpClient.defaultHttpsPort;
    final serverInfo = await _httpClient.getServerInfoHttps(
      computer.localAddress,
      httpsPort: httpsPort,
      httpPort: httpPort,
    );
    if (serverInfo != null) {
      serverInfo.manualAddress = computer.manualAddress;
      if (serverInfo.name.isEmpty ||
          serverInfo.name.toLowerCase() == 'unknown') {
        serverInfo.name = computer.name;
      }
      _addOrUpdateComputer(serverInfo);
    } else {
      _addOrUpdateComputer(computer);
    }
  }

  void _addOrUpdateComputer(ComputerDetails computer) {
    // Match by UUID first (most reliable), then by localAddress or activeAddress.
    // On macOS, mDNS may discover the same server via different addresses
    // (e.g., hostname.local vs raw IP), so we also check cross-address matches.
    final existingIndex = _computers.indexWhere(
      (c) =>
          (c.uuid.isNotEmpty && c.uuid == computer.uuid) ||
          c.localAddress == computer.localAddress ||
          (c.activeAddress.isNotEmpty &&
              c.activeAddress == computer.activeAddress) ||
          (c.localAddress.isNotEmpty &&
              c.localAddress == computer.activeAddress) ||
          (c.activeAddress.isNotEmpty &&
              c.activeAddress == computer.localAddress),
    );

    if (existingIndex >= 0) {
      final existing = _computers[existingIndex];

      if (computer.serverCert.isEmpty && existing.serverCert.isNotEmpty) {
        computer.serverCert = existing.serverCert;
      }
      if ((computer.name.isEmpty || computer.name.toLowerCase() == 'unknown') &&
          existing.name.isNotEmpty &&
          existing.name.toLowerCase() != 'unknown') {
        computer.name = existing.name;
      }
      if (computer.manualAddress.isEmpty && existing.manualAddress.isNotEmpty) {
        computer.manualAddress = existing.manualAddress;
      }
      if (computer.activeAddress.isEmpty && existing.activeAddress.isNotEmpty) {
        computer.activeAddress = existing.activeAddress;
      }
      if (computer.externalPort <= 0 && existing.externalPort > 0) {
        computer.externalPort = existing.externalPort;
      }

      // ── Pairing state reconciliation ──────────────────────────────────
      // Trust the server's PairStatus when the response came via HTTPS
      // (authenticated channel). If HTTPS says "not paired", the server
      // revoked pairing — clear local state immediately.
      //
      // Only preserve the local "paired" cache when the incoming data came
      // from an HTTP-only fallback (pairStatusFromHttps == false) AND the
      // existing record was confirmed via HTTPS previously. This prevents
      // a plain-HTTP poll (which can't verify pairing) from flipping a
      // legitimately paired server to unpaired.
      if (computer.pairStatusFromHttps) {
        // HTTPS is authoritative — if server says notPaired, trust it.
        if (computer.pairState == PairState.notPaired &&
            existing.pairState == PairState.paired) {
          // Server revoked pairing. Clear cached cert so the UI shows
          // "Not Paired" and blocks entry until re-paired.
          computer.serverCert = '';
        }
      } else if (computer.pairState == PairState.notPaired &&
          existing.pairState == PairState.paired &&
          existing.serverCert.isNotEmpty &&
          existing.pairStatusFromHttps) {
        // HTTP-only fallback — can't verify pairing. Preserve the cached
        // HTTPS-confirmed state to avoid false negatives from plain HTTP.
        computer.pairState = PairState.paired;
        computer.pairStatusFromHttps = true;
      }
      _computers[existingIndex] = computer;
    } else {
      _computers.add(computer);
    }
    _persistComputers();
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _discoveryService.dispose();
    _httpClient.dispose();
    _pairingService.dispose();
    super.dispose();
  }
}
