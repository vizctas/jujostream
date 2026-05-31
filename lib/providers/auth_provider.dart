import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../services/auth/google_auth_service.dart';
import '../services/sync/cloud_sync_service.dart';

class AuthProvider extends ChangeNotifier {
  bool _signedIn = false;
  String? _email;
  String? _displayName;
  String? _photoUrl;
  bool _syncing = false;
  String? _cloudError;

  bool get isSignedIn => _signedIn;
  String? get email => _email;
  String? get displayName => _displayName;
  String? get photoUrl => _photoUrl;
  bool get isSyncing => _syncing;
  String? get cloudError => _cloudError;

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
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.session == null) {
        _cloudError = 'El servidor no devolvió una sesión válida.';
        return false;
      }
      if (response.user?.emailConfirmedAt == null) {
        await Supabase.instance.client.auth.signOut();
        _cloudError = 'Por favor, confirma tu correo antes de iniciar sesión.';
        return false;
      }
      
      _signedIn = true;
      _email = response.user?.email;
      _displayName = response.user?.email?.split('@').first;
      notifyListeners();
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
    _signedIn = false;
    _email = null;
    _displayName = null;
    _photoUrl = null;
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
