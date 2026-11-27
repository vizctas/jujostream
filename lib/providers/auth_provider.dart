import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../services/auth/google_auth_service.dart';
import '../services/sync/cloud_sync_service.dart';
import '../services/sync/guest_link.dart';

enum GuestJoinEventKind {
  needSignIn,
  joined,
  accepted,
  declined,
  expired,
  verifyEmail,
  invalidCode,
  alreadyHasAccess,
  error,
}

class GuestJoinEvent {
  final GuestJoinEventKind kind;
  final String serverName;
  const GuestJoinEvent(this.kind, [this.serverName = '']);
}

class AuthProvider extends ChangeNotifier {
  bool _signedIn = false;
  String? _email;
  String? _displayName;
  String? _photoUrl;
  bool _syncing = false;
  String? _cloudError;
  List<CloudPendingInvite> _pendingInvites = const [];
  bool _loadingInvites = false;
  bool _disposed = false;
  String? _savedGuestCode;
  GuestRedeemResult? _waitingGuest;
  Timer? _guestPoll;
  final _guestEvents = StreamController<GuestJoinEvent>.broadcast();

  /// Outcome messages for the UI (snackbars), also for deep-link joins.
  Stream<GuestJoinEvent> get guestJoinEvents => _guestEvents.stream;

  /// A join request waiting for the host's approval, if any.
  GuestRedeemResult? get waitingGuest => _waitingGuest;

  bool get isSignedIn => _signedIn;
  String? get email => _email;
  String? get displayName => _displayName;
  String? get photoUrl => _photoUrl;
  bool get isSyncing => _syncing;
  String? get cloudError => _cloudError;
  List<CloudPendingInvite> get pendingInvites => _pendingInvites;
  bool get isLoadingInvites => _loadingInvites;

  bool get isSupabaseSignedIn {
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  bool get deviceFlowAvailable => _auth.clientId != null;

  final _auth = GoogleAuthService.instance;
  final _sync = CloudSyncService.instance;

  Future<void> trySilentSignIn() async {
    // 1. Try Supabase silent sign-in
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        _signedIn = true;
        _email = session.user.email;
        _displayName = session.user.email?.split('@').first;
        notifyListeners();
        unawaited(pullFromCloud());
        return;
      }
    } catch (_) {}

    // 2. Fall back to Google Auth silent sign-in
    await _auth.loadDeviceFlowCredentials();
    final ok = await _auth.trySilentSignIn();
    if (ok) {
      _updateFromAuth();
      unawaited(pullFromCloud());
    }
  }

  Future<bool> loginWithCloud({required String email, required String password}) async {
    _cloudError = null;
    // Guard: Supabase.instance.client throws LateInitializationError if not initialized.
    try {
      Supabase.instance.client; // probe — will throw if uninitialized
    } catch (_) {
      _cloudError = 'Cloud sync is not configured. Please check your app settings.';
      notifyListeners();
      return false;
    }
    try {
      final client = Supabase.instance.client;
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.session == null) {
        _cloudError = 'El servidor no devolvió una sesión válida.';
        return false;
      }
      if (response.user?.emailConfirmedAt == null) {
        await client.auth.signOut();
        _cloudError = 'Por favor, confirma tu correo antes de iniciar sesión.';
        return false;
      }

      _signedIn = true;
      _email = response.user?.email;
      _displayName = response.user?.email?.split('@').first;
      notifyListeners();
      unawaited(_redeemSavedGuestCode());
      return true;
    } on AuthException catch (e) {
      _cloudError = e.message;
      return false;
    } catch (e) {
      _cloudError = e.toString();
      return false;
    }
  }

  Future<bool> signUpWithCloud({required String email, required String password}) async {
    _cloudError = null;
    try {
      Supabase.instance.client; // probe
    } catch (_) {
      _cloudError = 'Cloud sync is not configured. Please check your app settings.';
      notifyListeners();
      return false;
    }
    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );

      // Supabase returns a session if email confirmation is disabled,
      // or user object with unconfirmed email if confirmation is required.
      if (response.user == null) {
        _cloudError = 'Error al registrar la cuenta.';
        return false;
      }

      return true;
    } on AuthException catch (e) {
      _cloudError = e.message;
      return false;
    } catch (e) {
      _cloudError = e.toString();
      return false;
    }
  }

  Future<void> signOutFromCloud() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    unawaited(_sync.refreshCloudVisibility());
    _signedIn = false;
    _email = null;
    _displayName = null;
    _photoUrl = null;
    _pendingInvites = const [];
    _clearWaitingGuest();
    notifyListeners();
  }

  Future<bool> signIn() async {
    final ok = await _auth.signIn();
    if (ok) {
      _updateFromAuth();
      unawaited(pullFromCloud());
      return true;
    }
    return false;
  }

  Future<DeviceCodeResult?> startDeviceFlow() async {
    return _auth.requestDeviceCode();
  }

  Future<bool> pollDeviceFlow(
    DeviceCodeResult deviceCode, {
    void Function(String status)? onStatus,
  }) async {
    final ok = await _auth.pollForDeviceToken(
      deviceCode,
      onStatus: onStatus,
    );
    if (ok) {
      _updateFromAuth();
      unawaited(pullFromCloud());
    }
    return ok;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    unawaited(_sync.refreshCloudVisibility());
    _signedIn = false;
    _email = null;
    _displayName = null;
    _photoUrl = null;
    _pendingInvites = const [];
    notifyListeners();
  }

  Future<bool> pushToCloud() async {
    _syncing = true;
    _cloudError = null;
    notifyListeners();
    try {
      final ok = isSupabaseSignedIn
          ? await _sync.pushConfigToSupabase()
          : await _sync.pushConfig();
      if (!ok) {
        _cloudError = _sync.lastError ?? 'Unknown error';
      }
      return ok;
    } catch (e) {
      _cloudError = e.toString();
      return false;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<bool> pullFromCloud() async {
    _syncing = true;
    _cloudError = null;
    notifyListeners();
    try {
      final ok = isSupabaseSignedIn
          ? await _sync.pullConfigFromSupabase()
          : await _sync.pullConfig();
      if (!ok) {
        _cloudError = _sync.lastError ?? 'Unknown error';
      } else if (isSupabaseSignedIn) {
        unawaited(refreshPendingInvites());
        unawaited(_redeemSavedGuestCode());
      }
      return ok;
    } catch (e) {
      _cloudError = e.toString();
      return false;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> refreshPendingInvites() async {
    if (!isSupabaseSignedIn) {
      if (_pendingInvites.isNotEmpty) {
        _pendingInvites = const [];
        if (!_disposed) notifyListeners();
      }
      return;
    }
    _loadingInvites = true;
    if (!_disposed) notifyListeners();
    try {
      _pendingInvites = await _sync.fetchPendingInvites();
    } finally {
      _loadingInvites = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> respondToPendingInvite(
    CloudPendingInvite invite, {
    required bool accept,
  }) async {
    _cloudError = null;
    final ok = await _sync.respondToInvite(invite, accept: accept);
    if (_disposed) return ok;
    if (ok) {
      _pendingInvites = _pendingInvites
          .where((i) => i.inviteId != invite.inviteId)
          .toList(growable: false);
    } else {
      _cloudError = _sync.lastError ?? 'Unknown error';
    }
    notifyListeners();
    return ok;
  }

  /// Redeems a guest link/code. Signed out: keeps the code for after sign-in.
  Future<void> redeemGuestCode(String raw) async {
    final code = normalizeGuestCode(raw);
    if (code == null) {
      _guestEvents.add(const GuestJoinEvent(GuestJoinEventKind.invalidCode));
      return;
    }
    if (!isSupabaseSignedIn) {
      _savedGuestCode = code;
      _guestEvents.add(const GuestJoinEvent(GuestJoinEventKind.needSignIn));
      return;
    }
    final result = await _sync.redeemGuestLink(code);
    switch (result.outcome) {
      case GuestRedeemOutcome.active:
        await pullFromCloud();
        _guestEvents.add(
          GuestJoinEvent(GuestJoinEventKind.joined, result.serverName),
        );
      case GuestRedeemOutcome.requested:
        _waitingGuest = result;
        _guestPoll?.cancel();
        _guestPoll = Timer.periodic(
          const Duration(seconds: 3),
          (_) => _pollWaitingGuest(),
        );
        if (!_disposed) notifyListeners();
      case GuestRedeemOutcome.verifyEmail:
        _guestEvents.add(const GuestJoinEvent(GuestJoinEventKind.verifyEmail));
      case GuestRedeemOutcome.invalidOrExpired:
        _guestEvents.add(const GuestJoinEvent(GuestJoinEventKind.invalidCode));
      case GuestRedeemOutcome.alreadyHasAccess:
        _guestEvents.add(
          const GuestJoinEvent(GuestJoinEventKind.alreadyHasAccess),
        );
      case GuestRedeemOutcome.error:
        _guestEvents.add(const GuestJoinEvent(GuestJoinEventKind.error));
    }
  }

  Future<void> _redeemSavedGuestCode() async {
    final code = _savedGuestCode;
    if (code == null) return;
    _savedGuestCode = null;
    await redeemGuestCode(code);
  }

  Future<void> cancelWaitingGuest() async {
    final waiting = _waitingGuest;
    if (waiting == null) return;
    _clearWaitingGuest();
    await _sync.cancelGuestRequest(waiting.inviteId);
  }

  void _clearWaitingGuest() {
    _guestPoll?.cancel();
    _guestPoll = null;
    _waitingGuest = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> _pollWaitingGuest() async {
    final waiting = _waitingGuest;
    if (waiting == null) return;
    GuestJoinEventKind? done;
    try {
      final status = await _sync.guestRequestStatus(waiting.inviteId);
      if (_waitingGuest != waiting) return;
      if (status == 'active') {
        await pullFromCloud();
        done = GuestJoinEventKind.accepted;
      } else if (status == 'declined') {
        done = GuestJoinEventKind.declined;
      } else if (status == null ||
          (waiting.expiresAt != null &&
              !waiting.expiresAt!.isAfter(DateTime.now().toUtc()))) {
        done = GuestJoinEventKind.expired;
      }
    } catch (_) {
      return;
    }
    if (done == null || _waitingGuest != waiting) return;
    _clearWaitingGuest();
    _guestEvents.add(GuestJoinEvent(done, waiting.serverName));
  }

  @override
  void dispose() {
    _guestPoll?.cancel();
    _guestEvents.close();
    _disposed = true;
    super.dispose();
  }

  void _updateFromAuth() {
    final user = _auth.currentUser;
    _signedIn = _auth.isSignedIn;
    _email = _auth.signedInEmail ?? user?.email;
    _displayName = user?.displayName;
    _photoUrl = user?.photoUrl;
    notifyListeners();
  }
}
