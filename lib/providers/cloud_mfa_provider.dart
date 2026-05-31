import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum CloudMfaStatus {
  unknown,
  loading,
  satisfied,
  setupRequired,
  verifyRequired,
  unavailable,
  error,
}

class CloudMfaProvider extends ChangeNotifier {
  CloudMfaStatus _status = CloudMfaStatus.unknown;
  String? _verifiedFactorId;
  String? _enrollmentFactorId;
  String? _enrollmentUri;
  String? _enrollmentSecret;
  String? _error;
  bool _refreshing = false;

  CloudMfaStatus get status => _status;
  String? get verifiedFactorId => _verifiedFactorId;
  String? get enrollmentFactorId => _enrollmentFactorId;
  String? get enrollmentUri => _enrollmentUri;
  String? get enrollmentSecret => _enrollmentSecret;
  String? get error => _error;

  bool get isSatisfied => _status == CloudMfaStatus.satisfied;
  bool get blocksCloudUser =>
      _status == CloudMfaStatus.unknown ||
      _status == CloudMfaStatus.loading ||
      _status == CloudMfaStatus.setupRequired ||
      _status == CloudMfaStatus.verifyRequired ||
      _status == CloudMfaStatus.error;

  SupabaseClient get _client => Supabase.instance.client;

  void reset() {
    _status = CloudMfaStatus.unknown;
    _verifiedFactorId = null;
    _enrollmentFactorId = null;
    _enrollmentUri = null;
    _enrollmentSecret = null;
    _error = null;
    _refreshing = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      if (!Supabase.instance.client.auth.currentSession.toString().isNotEmpty) {
        _status = CloudMfaStatus.unavailable;
        notifyListeners();
        return;
      }
    } catch (_) {
      _status = CloudMfaStatus.unavailable;
      notifyListeners();
      return;
    }
    
    final session = _client.auth.currentSession;
    if (session == null) {
      _status = CloudMfaStatus.unavailable;
      notifyListeners();
      return;
    }
    if (_refreshing) return;

    _refreshing = true;
    final showLoading =
        _status == CloudMfaStatus.unknown ||
        _status == CloudMfaStatus.unavailable;
    if (showLoading) {
      _status = CloudMfaStatus.loading;
      _error = null;
      notifyListeners();
    }
    try {
      final aal = _client.auth.mfa.getAuthenticatorAssuranceLevel();
      if (aal.currentLevel == AuthenticatorAssuranceLevels.aal2) {
        _status = CloudMfaStatus.satisfied;
        notifyListeners();
        return;
      }

      final factors = await _client.auth.mfa.listFactors();
      if (factors.totp.isNotEmpty) {
        _status = CloudMfaStatus.verifyRequired;
        _verifiedFactorId = factors.totp.first.id;
        notifyListeners();
        return;
      }

      _status = CloudMfaStatus.setupRequired;
      notifyListeners();
    } catch (e) {
      _status = CloudMfaStatus.error;
      _error = 'Could not check 2FA status: $e';
      notifyListeners();
    } finally {
      _refreshing = false;
    }
  }

  Future<void> startTotpSetup() async {
    _status = CloudMfaStatus.loading;
    _error = null;
    notifyListeners();
    try {
      final res = await _client.auth.mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'Jujo.Stream',
        friendlyName: 'Jujo.Stream Client',
      );
      _status = CloudMfaStatus.setupRequired;
      _enrollmentFactorId = res.id;
      _enrollmentUri = res.totp?.uri;
      _enrollmentSecret = res.totp?.secret;
      notifyListeners();
    } catch (e) {
      _status = CloudMfaStatus.error;
      _error = 'Could not start 2FA setup: $e';
      notifyListeners();
    }
  }

  Future<bool> verifyCode(String code) async {
    final cleanCode = code.trim().replaceAll(' ', '');
    if (cleanCode.length < 6) {
      _error = 'Enter the 6-digit authenticator code.';
      notifyListeners();
      return false;
    }

    final factorId = _enrollmentFactorId ?? _verifiedFactorId;
    if (factorId == null || factorId.isEmpty) {
      await refresh();
      return false;
    }

    _status = CloudMfaStatus.loading;
    _error = null;
    notifyListeners();
    try {
      await _client.auth.mfa.challengeAndVerify(
        factorId: factorId,
        code: cleanCode,
      );
      _status = CloudMfaStatus.satisfied;
      _enrollmentFactorId = null;
      _enrollmentUri = null;
      _enrollmentSecret = null;
      notifyListeners();
      return true;
    } catch (e) {
      _status = _enrollmentFactorId == null
          ? CloudMfaStatus.verifyRequired
          : CloudMfaStatus.setupRequired;
      _error = 'Invalid 2FA code. Try again.';
      notifyListeners();
      return false;
    }
  }
}
