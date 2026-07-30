import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/io_client.dart';
import '../models/computer_details.dart';
import '../models/nv_app.dart';
import '../services/discovery/discovery_service.dart';
import '../services/network/wake_on_lan_service.dart';
import '../services/http_api/nv_http_client.dart';
import '../services/pairing/pairing_service.dart';
import '../services/database/achievement_service.dart';
import '../services/database/session_history_service.dart';
import '../services/sync/cloud_sync_service.dart';
import '../services/auth/supabase_config.dart';
import '../services/crypto/client_identity.dart';

/// Every address this server is known by, best guess first.
///
/// The hot paths (applist, launch, stream) all follow `activeAddress`, so
/// making the poll try the alternatives and promote whichever answers is what
/// lets a server survive a DHCP change or a switch between its `.local` name
/// and its raw IP.
List<String> candidateAddresses(ComputerDetails computer) {
  final seen = <String>{};
  return <String>[
        computer.activeAddress,
        computer.localAddress,
        computer.manualAddress,
        computer.remoteAddress,
      ]
      .map((a) => a.trim())
      .where((a) => a.isNotEmpty)
      .where(seen.add)
      .toList(growable: false);
}

bool isComputerVisible({
  required ComputerDetails computer,
  required bool cloudSignedIn,
  required bool lanDiscovered,
}) {
  return cloudSignedIn ||
      !computer.isCloud ||
      lanDiscovered ||
      hasLocalPairingCredentials(computer);
}

/// A Cloud record is still a trusted server for this device after the Cloud
/// session ends: the pinned pairing certificate is the authority, and the cloud
/// only ever added remote discovery on top of it.
///
/// This used to also require an RFC1918 `localAddress`, which hid servers
/// reached over mDNS `.local`, IPv6, Tailscale (100.64/10) or link-local — a
/// user standing next to their machine watched its card vanish when their
/// Supabase token expired.
bool hasLocalPairingCredentials(ComputerDetails computer) {
  return computer.isPaired && computer.serverCert.isNotEmpty;
}

/// Cloud is optional for LAN-only installations. Avoid reading Supabase's
/// late-initialized client when the release was built without cloud defines.
bool isCloudSessionActive({
  required bool cloudConfigured,
  required bool Function() readSession,
}) => cloudConfigured && readSession();

/// Whether a cloud session is live right now.
///
/// `Supabase.instance` throws when `initialize()` failed — a build shipped with
/// a bad URL/key, for instance. Unguarded, that exception used to propagate out
/// of the `computers` getter during build and left a LAN-only user unable to
/// see or enter any server at all. Every caller must go through here.
bool hasCloudSession() => isCloudSessionActive(
  cloudConfigured: SupabaseConfig.current.isConfigured,
  readSession: () {
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  },
);

/// Test seam for the server-side unpair request. The default keeps using the
/// established nVHTTP endpoint implemented by [PairingService].
typedef UnpairRequest = Future<bool> Function(ComputerDetails computer);

class ComputerProvider extends ChangeNotifier with WidgetsBindingObserver {
  final DiscoveryService _discoveryService;
  final NvHttpClient _httpClient = NvHttpClient();
  final PairingService _pairingService = PairingService();
  final UnpairRequest? _unpairRequest;

  final List<ComputerDetails> _computers = [];
  final Set<String> _lanDiscoveryKeys = {};
  StreamSubscription<void>? _syncSubscription;
  final List<String> _customOrder = [];
  static const String _computersStorageKey = 'saved_computers';
  static const String _primaryServerKey = 'primary_server_uuid';
  static const String _customOrderKey = 'computer_custom_order';
  bool _isDiscovering = false;

  /// Servers with a pairing handshake in flight.
  ///
  /// This used to be one global flag, which froze polling for *every* server
  /// for the whole handshake — phase 1 alone can block for minutes waiting on
  /// the user to type a PIN.
  final Set<String> _pairingKeys = <String>{};
  String? _error;
  Timer? _pollTimer;

  String? _primaryServerUuid;

  /// Consecutive poll-failure count per computer UUID.
  /// Requires [_kOfflineThreshold] consecutive failures before marking offline.
  /// Prevents transient failures (e.g. after session close) from flipping state.
  final Map<String, int> _pollFailCount = {};
  static const int _kOfflineThreshold = 2;

  /// Timestamp of the last successful pairing per computer UUID.
  /// Polls and verifyPairing cannot override paired state during this
  /// grace period — Sunshine may take a few seconds to fully register
  /// the pairing internally after Phase 5 completes.
  final Map<String, DateTime> _pairingCompletedAt = {};
  static const Duration _pairingGracePeriod = Duration(seconds: 15);

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

  String _orderKey(ComputerDetails c) =>
      c.uuid.isNotEmpty ? c.uuid : c.localAddress;

  static const Duration _activePollInterval = Duration(seconds: 3);
  static const Duration _idlePollInterval = Duration(seconds: 30);
  // getServerInfoHttps spends this budget twice (HTTPS 47984, then the HTTP
  // 47989 fallback). At 2s a cold TLS handshake plus mDNS resolution blows
  // through it and two consecutive misses mark a healthy server offline.
  static const Duration _pollTimeout = Duration(seconds: 5);
  bool _appInForeground = true;

  /// Whether a JUJO cloud account is currently signed in. Cloud-paired servers
  /// must only be visible/enterable while signed in — on sign-out they are
  /// hidden (not deleted) and restored on the next sign-in.
  bool get _cloudSignedIn => hasCloudSession();

  List<ComputerDetails> get computers {
    final visible = _computers
        .where(
          (computer) => isComputerVisible(
            computer: computer,
            cloudSignedIn: _cloudSignedIn,
            lanDiscovered: _isLanDiscovered(computer),
          ),
        )
        .toList();
    if (_customOrder.isEmpty) return List.unmodifiable(visible);
    final orderMap = <String, int>{};
    for (var i = 0; i < _customOrder.length; i++) {
      orderMap[_customOrder[i]] = i;
    }
    final sorted = List<ComputerDetails>.from(visible);
    sorted.sort((a, b) {
      final keyA = _orderKey(a);
      final keyB = _orderKey(b);
      final idxA = orderMap[keyA];
      final idxB = orderMap[keyB];
      if (idxA != null && idxB != null) return idxA.compareTo(idxB);
      if (idxA != null) return -1;
      if (idxB != null) return 1;
      return 0;
    });
    return List.unmodifiable(sorted);
  }

  bool get isDiscovering => _isDiscovering;
  bool get isPairing => _pairingKeys.isNotEmpty;

  String? get error => _error;

  String? get primaryServerUuid => _primaryServerUuid;

  ComputerDetails? get primaryServer {
    if (_primaryServerUuid == null) return null;
    try {
      final c = _computers.firstWhere((c) => c.uuid == _primaryServerUuid);
      // Don't surface a cloud-paired primary while signed out — it must not be
      // auto-connectable until the account signs back in.
      if (c.isCloud && !_cloudSignedIn) return null;
      return c;
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

  ComputerProvider({
    DiscoveryService? discoveryService,
    UnpairRequest? unpairRequest,
  }) : _discoveryService = discoveryService ?? DiscoveryService(),
       _unpairRequest = unpairRequest {
    WidgetsBinding.instance.addObserver(this);
    _loadPersistedComputers();
    _discoveryService.onComputerFound.listen(_onComputerDiscovered);
    _startAdaptivePoll();
    _syncSubscription = CloudSyncService.onSyncCompleted.listen((_) {
      _loadPersistedComputers();
    });
    unawaited(startDiscovery());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;

    if (_appInForeground) {
      unawaited(startDiscovery());
      // Always restart the timer on resume — even if it was already running.
      // This prevents the "poll never checks back" bug where the timer was
      // cancelled but the state flag didn't change.
      _startAdaptivePoll();
      // Trigger an immediate poll so the UI updates without waiting for the
      // next timer tick (3s).
      _pollAll();
      // Re-attempt cloud pairing for any server that failed at login time.
      _retryCloudPairingOnResume();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.detached) {
        if (_lanDiscoveryKeys.isNotEmpty) {
          _lanDiscoveryKeys.clear();
          notifyListeners();
        }
        unawaited(stopDiscovery());
      }
    }
  }

  void _startAdaptivePoll() {
    _pollTimer?.cancel();
    final interval = _appInForeground ? _activePollInterval : _idlePollInterval;
    _pollTimer = Timer.periodic(interval, (_) => _pollAll());
  }

  Future<void> _pollAll() async {
    if (_computers.isEmpty || !_appInForeground) return;
    final snapshot = _computers
        .where((c) => !_pairingKeys.contains(_failKey(c)))
        .toList(growable: false);
    if (snapshot.isEmpty) return;
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

      // This runs again after every cloud sync. Without carrying the polled
      // state over, every server resets to `unknown` — which the UI treats as
      // offline — until the next poll lands.
      final knownStates = {
        for (final c in _computers)
          if (c.uuid.isNotEmpty) c.uuid: c.state,
      };

      _computers
        ..clear()
        ..addAll(
          jsonList.map((entry) {
            final map = jsonDecode(entry) as Map<String, dynamic>;
            final computer = ComputerDetails.fromJson(map);
            computer.state =
                knownStates[computer.uuid] ?? ComputerState.unknown;

            if (computer.pairState == PairState.paired &&
                computer.serverCert.isNotEmpty) {
              computer.pairStatusFromHttps = true;
            }
            return computer;
          }),
        );
      final orderList = prefs.getStringList(_customOrderKey);
      if (orderList != null) {
        _customOrder
          ..clear()
          ..addAll(orderList);
      }
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

  Future<void> _persistCustomOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _customOrderKey,
        _customOrder.toList(growable: false),
      );
    } catch (_) {}
  }

  Future<void> reorderComputers(int oldIndex, int newIndex) async {
    final sorted = List<ComputerDetails>.from(computers);
    if (oldIndex < 0 || oldIndex >= sorted.length) return;
    if (newIndex < 0 || newIndex >= sorted.length) return;
    final item = sorted.removeAt(oldIndex);
    sorted.insert(newIndex, item);
    _customOrder.clear();
    for (final c in sorted) {
      _customOrder.add(_orderKey(c));
    }
    await _persistCustomOrder();
    notifyListeners();
  }

  Future<void> startDiscovery() async {
    _isDiscovering = true;
    _error = null;
    notifyListeners();

    try {
      await _discoveryService.startDiscovery();
      _isDiscovering = _discoveryService.isActive;
      notifyListeners();
    } catch (e) {
      _isDiscovering = false;
      _error = 'Discovery failed: $e';
      notifyListeners();
    }
  }

  Future<void> stopDiscovery() async {
    try {
      await _discoveryService.stopDiscovery();
    } catch (e) {
      _error = 'Discovery stop failed: $e';
    } finally {
      _isDiscovering = false;
      notifyListeners();
    }
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
          expectedServerCert: computer.serverCert,
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

  /// Polls one server and returns its resulting state.
  ///
  /// Callers must use the return value rather than re-reading `computer.state`:
  /// on success [_addOrUpdateComputer] replaces the list entry with a new
  /// object, leaving the caller's reference stale.
  Future<ComputerState> pollComputer(ComputerDetails computer) async {
    final httpPort = computer.externalPort > 0
        ? computer.externalPort
        : NvHttpClient.defaultHttpPort;
    final httpsPort = computer.httpsPort > 0
        ? computer.httpsPort
        : NvHttpClient.defaultHttpsPort;

    // Walk every known address instead of only activeAddress. The first one
    // usually answers, so the common case is still a single request.
    ({ComputerDetails? info, bool certRejected})? result;
    for (final address in candidateAddresses(computer)) {
      final attempt = await _httpClient.fetchServerInfo(
        address,
        httpsPort: httpsPort,
        httpPort: httpPort,
        timeout: _pollTimeout,
        expectedServerCert: computer.serverCert,
      );
      result ??= attempt;
      if (attempt.info != null || attempt.certRejected) {
        result = attempt;
        break;
      }
    }
    final serverInfo = result?.info;
    final certRejected = result?.certRejected ?? false;

    if (certRejected) {
      // The server is up and refuses this device — it was reinstalled or its
      // state file was wiped. Drop the dead credentials so the UI offers
      // pairing again instead of showing a permanently "connected" card.
      _clearStalePairing(computer, serverInfo);
    }

    if (serverInfo != null) {
      serverInfo.manualAddress = computer.manualAddress;
      if (!certRejected &&
          serverInfo.serverCert.isEmpty &&
          computer.serverCert.isNotEmpty) {
        serverInfo.serverCert = computer.serverCert;
      }
      _pollFailCount[_failKey(computer)] = 0;
      _addOrUpdateComputer(serverInfo);
      return serverInfo.state;
    }

    final key = _failKey(computer);
    final count = (_pollFailCount[key] ?? 0) + 1;
    _pollFailCount[key] = count;
    if (count >= _kOfflineThreshold) {
      computer.state = ComputerState.offline;
      _persistComputers();
      notifyListeners();
      return ComputerState.offline;
    }
    return computer.state;
  }

  /// Key for [_pollFailCount]. Must be identical on the reset and the increment
  /// side — using `uuid` on one and this fallback on the other meant a
  /// uuid-less record could never clear its counter.
  String _failKey(ComputerDetails c) =>
      c.uuid.isNotEmpty ? c.uuid : c.localAddress;

  /// Forgets the pairing credentials of a server that no longer recognises us.
  void _clearStalePairing(ComputerDetails computer, ComputerDetails? fresh) {
    for (final c in [computer, ?fresh]) {
      c.serverCert = '';
      c.pairState = PairState.notPaired;
      c.pairStatusFromHttps = false;
    }
    _persistComputers();
    notifyListeners();
  }

  void removeComputer(ComputerDetails computer) {
    _computers.removeWhere(
      (c) => c.uuid == computer.uuid || c.localAddress == computer.localAddress,
    );
    _pollFailCount.remove(_failKey(computer));
    _pairingCompletedAt.remove(_failKey(computer));

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

    final pairingKey = _failKey(computer);
    _pairingKeys.add(pairingKey);
    computer.pairState = PairState.alreadyInProgress;
    _error = null;
    notifyListeners();

    try {
      final result = await _pairingService.pair(computer, pin);

      if (result.paired) {
        computer.pairState = PairState.paired;
        computer.serverCert = result.serverCert ?? computer.serverCert;

        computer.pairStatusFromHttps = true;

        // Record pairing timestamp — polls and verifyPairing will not
        // override the paired state during the grace period.
        final graceKey = computer.uuid.isNotEmpty
            ? computer.uuid
            : computer.localAddress;
        _pairingCompletedAt[graceKey] = DateTime.now();

        // Persist immediately so the paired state survives even if
        // the subsequent pollComputer() call fails or times out.
        _persistComputers();
        notifyListeners();

        unawaited(AchievementService.instance.unlock('first_connection'));

        // Still marked as pairing during the post-pairing poll so the periodic
        // _pollAll() timer doesn't race with us on *this* server.
        await pollComputer(computer);
      } else {
        computer.pairState = PairState.failed;
        _error = result.error ?? 'Pairing failed';
        _persistComputers();
        notifyListeners();
      }

      return result;
    } finally {
      _pairingKeys.remove(pairingKey);
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
    if (!computer.isPaired) {
      final cloudPaired = await _attemptCloudPairingOnTheFly(computer);
      if (!cloudPaired) {
        return false;
      }
    }

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
      final result = await _httpClient.fetchServerInfo(
        address,
        httpsPort: httpsPort,
        httpPort: httpPort,
        timeout: const Duration(seconds: 3),
        expectedServerCert: computer.serverCert,
      );
      final info = result.info;

      if (result.certRejected) {
        // Reached the server and it refused this device. Not ambiguous, so do
        // not fail open — clear the dead pairing and let the caller re-pair.
        _clearStalePairing(computer, info);
        return await _attemptCloudPairingOnTheFly(computer);
      }

      if (info == null) {
        // Server unreachable — can't verify. Allow entry optimistically
        // (the stream will fail with a clear error if truly unpaired).
        return true;
      }
      if (info.pairState == PairState.paired) {
        return true;
      }

      // Try on-the-fly cloud pairing before failing
      final cloudPaired = await _attemptCloudPairingOnTheFly(computer);
      if (cloudPaired) {
        return true;
      }

      // If the response came via HTTP fallback (not HTTPS-authenticated),
      // it cannot reliably determine pairing status. Allow entry.
      if (!info.pairStatusFromHttps) {
        return true;
      }

      // Check grace period — don't revoke pairing if we just completed it.
      final graceKey = computer.uuid.isNotEmpty
          ? computer.uuid
          : computer.localAddress;
      final pairedAt = _pairingCompletedAt[graceKey];
      final inManualGrace =
          pairedAt != null &&
          DateTime.now().difference(pairedAt) < _pairingGracePeriod;
      final inCloudGrace = CloudSyncService.instance.isInCloudPairingGrace(
        graceKey,
      );
      if (inManualGrace || inCloudGrace) {
        return true;
      }

      // HTTPS confirmed: NOT paired. Update local state.
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

  /// Forgets this device's pairing with [computer].
  ///
  /// The request to the server is best-effort: if the server is gone,
  /// reinstalled, or moved, there is nothing left to revoke there, and keeping
  /// the local credentials would only leave the user stuck with a pairing that
  /// cannot be repaired. Local state is therefore always cleared; the return
  /// value reports whether the server also acknowledged.
  Future<bool> unpairComputer(ComputerDetails computer) async {
    final success =
        await (_unpairRequest?.call(computer) ??
            _pairingService.unpair(computer));

    computer.pairState = PairState.notPaired;
    computer.serverCert = '';
    computer.pairStatusFromHttps = false;

    // Clear grace period so a subsequent re-pair doesn't inherit
    // stale protection from the previous pairing session.
    _pairingCompletedAt.remove(_failKey(computer));

    _persistComputers();
    notifyListeners();
    return success;
  }

  /// Revokes this client's pairing at the server before forgetting the local
  /// record. A failure intentionally leaves the record — and its paired state —
  /// intact so the user can retry and never loses the route to revoke the
  /// device remotely.
  ///
  /// Unlike [unpairComputer] this is fail-closed on purpose: forgetting our
  /// credentials while the server still trusts this device would leave an
  /// authorised client with no way to revoke it from here.
  Future<bool> revokeAndForgetComputer(ComputerDetails computer) async {
    final revoked =
        await (_unpairRequest?.call(computer) ??
            _pairingService.unpair(computer));
    if (!revoked) return false;

    _pairingCompletedAt.remove(_failKey(computer));
    removeComputer(computer);
    return true;
  }

  void _onComputerDiscovered(ComputerDetails computer) async {
    // Only skip the server currently mid-handshake; discovering the others is
    // harmless and keeps the list fresh.
    if (_pairingKeys.contains(_failKey(computer))) {
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
      expectedServerCert: computer.serverCert,
    );
    if (serverInfo != null) {
      serverInfo.manualAddress = computer.manualAddress;
      if (serverInfo.name.isEmpty ||
          serverInfo.name.toLowerCase() == 'unknown') {
        serverInfo.name = computer.name;
      }
      _markLanDiscovered(serverInfo);
      _addOrUpdateComputer(serverInfo);
    } else {
      _markLanDiscovered(computer);
      _addOrUpdateComputer(computer);
    }
  }

  bool _isLanDiscovered(ComputerDetails computer) {
    return _computerKeys(computer).any(_lanDiscoveryKeys.contains);
  }

  void _markLanDiscovered(ComputerDetails computer) {
    _lanDiscoveryKeys.addAll(_computerKeys(computer));
  }

  Iterable<String> _computerKeys(ComputerDetails computer) sync* {
    if (computer.uuid.isNotEmpty) yield 'uuid:${computer.uuid}';
    if (computer.localAddress.isNotEmpty) {
      yield 'address:${computer.localAddress.toLowerCase()}';
    }
    if (computer.activeAddress.isNotEmpty) {
      yield 'address:${computer.activeAddress.toLowerCase()}';
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
              c.activeAddress == computer.localAddress) ||
          // Match by cert fingerprint — handles cloud-synced servers that arrive
          // with a temporary Supabase row UUID before the real Sunshine uniqueid
          // is discovered via polling. Prevents duplicate "Not Paired" ghost cards.
          (c.serverCert.isNotEmpty &&
              computer.serverCert.isNotEmpty &&
              c.serverCert.toLowerCase() == computer.serverCert.toLowerCase()),
    );

    if (existingIndex >= 0) {
      final existing = _computers[existingIndex];

      if (computer.serverCert.isEmpty && existing.serverCert.isNotEmpty) {
        computer.serverCert = existing.serverCert;
      }
      if (computer.configHttpsPort == 0 && existing.configHttpsPort > 0) {
        computer.configHttpsPort = existing.configHttpsPort;
      }
      // An HTTP-fallback poll carries no <ExternalIP> and no <HttpsPort>, so
      // without these a single degraded response wiped the remote address and
      // reset a learned custom port back to the 47984 default, permanently.
      if (computer.remoteAddress.isEmpty && existing.remoteAddress.isNotEmpty) {
        computer.remoteAddress = existing.remoteAddress;
      }
      if (computer.httpsPort == NvHttpClient.defaultHttpsPort &&
          existing.httpsPort > 0 &&
          existing.httpsPort != NvHttpClient.defaultHttpsPort) {
        computer.httpsPort = existing.httpsPort;
      }
      if (existing.isCloud) {
        computer.isCloud = true;
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
        // EXCEPT during the post-pairing grace period where Sunshine may
        // not yet have fully registered the pairing internally.
        if (computer.pairState == PairState.notPaired &&
            existing.pairState == PairState.paired) {
          final graceKey = existing.uuid.isNotEmpty
              ? existing.uuid
              : existing.localAddress;
          final pairedAt = _pairingCompletedAt[graceKey];
          final inManualGrace =
              pairedAt != null &&
              DateTime.now().difference(pairedAt) < _pairingGracePeriod;
          // Also check cloud-sync grace window (covers cloud-paired servers
          // where _attemptCloudPairing fires asynchronously after pullConfigFromSupabase).
          final inCloudGrace = CloudSyncService.instance.isInCloudPairingGrace(
            graceKey,
          );
          final inGracePeriod = inManualGrace || inCloudGrace;

          if (inGracePeriod) {
            // Still within grace period — preserve paired state.
            computer.pairState = PairState.paired;
            computer.pairStatusFromHttps = true;
          } else {
            // Server revoked pairing. Clear cached cert so the UI shows
            // "Not Paired" and blocks entry until re-paired.
            computer.serverCert = '';
          }
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
      final oldKey = _orderKey(existing);
      final newKey = _orderKey(computer);
      _computers[existingIndex] = computer;
      // Migrate custom order key if UUID was discovered (empty -> non-empty)
      if (oldKey != newKey && oldKey.isNotEmpty) {
        final idx = _customOrder.indexOf(oldKey);
        if (idx >= 0) {
          _customOrder[idx] = newKey;
        }
      }
    } else {
      _computers.add(computer);
      final key = _orderKey(computer);
      if (key.isNotEmpty && !_customOrder.contains(key)) {
        _customOrder.add(key);
      }
    }
    _persistComputers();
    notifyListeners();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _discoveryService.dispose();
    _httpClient.dispose();
    _pairingService.dispose();
    super.dispose();
  }

  /// Returns the confighttp HTTPS port for cloud pairing calls.
  /// Mirrors CloudSyncService._configPort — confighttp runs at base+1,
  /// nvhttp HTTPS at base-5, so the offset is always 6.
  static int _configPort(ComputerDetails c) =>
      c.configHttpsPort > 0 ? c.configHttpsPort : c.httpsPort + 6;

  void _retryCloudPairingOnResume() {
    if (!SupabaseConfig.current.isConfigured) return;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    unawaited(
      CloudSyncService.instance.retryUnpairedCloudServers(session.accessToken),
    );
  }

  Future<bool> _attemptCloudPairingOnTheFly(ComputerDetails computer) async {
    try {
      if (!SupabaseConfig.current.isConfigured) return false;
      final supabaseClient = Supabase.instance.client;
      final session = supabaseClient.auth.currentSession;
      if (session == null) return false;
      final token = session.accessToken;

      final address = computer.activeAddress.isNotEmpty
          ? computer.activeAddress
          : computer.localAddress;
      final serverUrl = 'https://$address:${_configPort(computer)}';

      final clientPem = ClientIdentity.certPem;
      if (clientPem.isEmpty || computer.serverCert.isEmpty) return false;

      final deviceName = io.Platform.localHostname;
      final body = jsonEncode({
        'token': token,
        'clientCert': clientPem,
        'deviceName': deviceName.isNotEmpty ? deviceName : 'Jujo.Stream Client',
      });

      final uri = Uri.parse('$serverUrl/api/pair/cloud');

      // Use a clean HttpClient without presenting an untrusted client certificate during the TLS handshake.
      // The server companion will register the certificate passed in the JSON request body.
      final ioClient = ClientIdentity.createHttpClient(
        expectedServerCert: computer.serverCert,
        includeClientIdentity: false,
      );
      final client = IOClient(ioClient);

      try {
        final response = await client
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: body,
            )
            .timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final resBody = jsonDecode(response.body) as Map<String, dynamic>;
          if (resBody['status'] == true) {
            computer.pairState = PairState.paired;
            computer.pairStatusFromHttps = true;

            final graceKey = computer.uuid.isNotEmpty
                ? computer.uuid
                : computer.localAddress;
            _pairingCompletedAt[graceKey] = DateTime.now();

            _persistComputers();
            notifyListeners();
            return true;
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return false;
  }
}
