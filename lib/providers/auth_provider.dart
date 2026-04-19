import 'package:flutter/foundation.dart';

import '../services/auth/google_auth_service.dart';
import '../services/sync/cloud_sync_service.dart';

class AuthProvider extends ChangeNotifier {
  bool _signedIn = false;
  String? _email;
  String? _displayName;
  String? _photoUrl;
  bool _syncing = false;

  bool get isSignedIn => _signedIn;
  String? get email => _email;
  String? get displayName => _displayName;
  String? get photoUrl => _photoUrl;
  bool get isSyncing => _syncing;

  bool get deviceFlowAvailable => _auth.clientId != null;

  final _auth = GoogleAuthService.instance;
  final _sync = CloudSyncService.instance;

  Future<void> trySilentSignIn() async {
    await _auth.loadDeviceFlowCredentials();
    final ok = await _auth.trySilentSignIn();
    if (ok) _updateFromAuth();
  }

  Future<bool> signIn() async {
    final ok = await _auth.signIn();
    if (ok) {
      _updateFromAuth();
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
    if (ok) _updateFromAuth();
    return ok;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _signedIn = false;
    _email = null;
    _displayName = null;
    _photoUrl = null;
    notifyListeners();
  }

  Future<bool> pushToCloud() async {
    _syncing = true;
    notifyListeners();
    try {
      return await _sync.pushConfig();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<bool> pullFromCloud() async {
    _syncing = true;
    notifyListeners();
    try {
      return await _sync.pullConfig();
    } finally {
      _syncing = false;
      notifyListeners();
    }
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
