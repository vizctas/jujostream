import 'dart:async';
import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as gauth;
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceCodeResult {
  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final int expiresIn;
  final int interval;
  DeviceCodeResult({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.expiresIn,
    required this.interval,
  });
}

class GoogleAuthService {
  GoogleAuthService._();
  static final instance = GoogleAuthService._();

  final _log = Logger(printer: SimplePrinter());

  static const _prefClientId = 'google_oauth_client_id';
  static const _prefRefreshToken = 'google_device_flow_refresh_token';
  static const _prefEmail = 'google_device_flow_email';

  static const _scopes = 'https://www.googleapis.com/auth/drive.appdata';
  static const _driveScopes = [drive.DriveApi.driveAppdataScope];

  bool _initialized = false;

  GoogleSignInAccount? _currentUser;
  GoogleSignInAccount? get currentUser => _currentUser;

  bool get isSignedIn => _currentUser != null || _deviceFlowAccessToken != null;

  String? get signedInEmail =>
      _currentUser?.email ?? _deviceFlowEmail;

  String? _deviceFlowAccessToken;
  DateTime? _deviceFlowTokenExpiry;
  String? _deviceFlowRefreshToken;
  String? _deviceFlowEmail;
  String? _clientId;

  Future<void> loadDeviceFlowCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _clientId = prefs.getString(_prefClientId);
    _deviceFlowRefreshToken = prefs.getString(_prefRefreshToken);
    _deviceFlowEmail = prefs.getString(_prefEmail);
  }

  Future<void> setClientId(String clientId) async {
    _clientId = clientId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefClientId, clientId);
  }

  String? get clientId => _clientId;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize();
    _initialized = true;
  }

  Future<bool> trySilentSignIn() async {
    if (_deviceFlowRefreshToken != null && _clientId != null) {
      final ok = await _refreshDeviceFlowToken();
      if (ok) return true;
    }

    try {
      await _ensureInitialized();
      final future = GoogleSignIn.instance.attemptLightweightAuthentication();
      _currentUser = future != null ? await future : null;
      if (_currentUser != null) {
        _log.i('Silent sign-in OK: ${_currentUser!.email}');
      }
      return _currentUser != null;
    } catch (e) {
      _log.w('Silent sign-in failed: $e');
      return false;
    }
  }

  Future<bool> signIn() async {
    try {
      await _ensureInitialized();
      _currentUser = await GoogleSignIn.instance.authenticate(
        scopeHint: _driveScopes,
      );
      _log.i('Sign-in OK: ${_currentUser!.email}');
      return true;
    } catch (e) {
      _log.e('Sign-in failed: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _ensureInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      _log.w('GoogleSignIn.signOut error: $e');
    }
    _currentUser = null;
    _deviceFlowAccessToken = null;
    _deviceFlowTokenExpiry = null;
    _deviceFlowRefreshToken = null;
    _deviceFlowEmail = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefRefreshToken);
    await prefs.remove(_prefEmail);
    _log.i('Signed out (all flows)');
  }

  Future<DeviceCodeResult?> requestDeviceCode() async {
    if (_clientId == null) {
      _log.e('Device flow: no client_id configured');
      return null;
    }
    final client = http.Client();
    try {
      final resp = await client.post(
        Uri.parse('https://oauth2.googleapis.com/device/code'),
        body: {'client_id': _clientId!, 'scope': _scopes},
      );
      if (resp.statusCode != 200) {
        _log.e('Device code request failed: ${resp.statusCode} ${resp.body}');
        return null;
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      return DeviceCodeResult(
        deviceCode: json['device_code'] as String,
        userCode: json['user_code'] as String,
        verificationUrl: json['verification_url'] as String,
        expiresIn: json['expires_in'] as int,
        interval: json['interval'] as int,
      );
    } catch (e) {
      _log.e('Device code request error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  Future<bool> pollForDeviceToken(
    DeviceCodeResult deviceCode, {
    void Function(String status)? onStatus,
  }) async {
    if (_clientId == null) return false;

    final client = http.Client();
    var interval = deviceCode.interval;
    final deadline =
        DateTime.now().add(Duration(seconds: deviceCode.expiresIn));

    try {
      while (DateTime.now().isBefore(deadline)) {
        await Future.delayed(Duration(seconds: interval));

        final resp = await client.post(
          Uri.parse('https://oauth2.googleapis.com/token'),
          body: {
            'client_id': _clientId!,
            'device_code': deviceCode.deviceCode,
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          },
        );

        if (resp.statusCode == 200) {
          final json = jsonDecode(resp.body) as Map<String, dynamic>;
          _deviceFlowAccessToken = json['access_token'] as String;
          _deviceFlowRefreshToken = json['refresh_token'] as String?;
          final expiresIn = json['expires_in'] as int? ?? 3600;
          _deviceFlowTokenExpiry =
              DateTime.now().add(Duration(seconds: expiresIn));

          if (_deviceFlowRefreshToken != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(
                _prefRefreshToken, _deviceFlowRefreshToken!);
          }

          await _fetchDeviceFlowUserInfo();

          _log.i('Device flow auth complete: $_deviceFlowEmail');
          onStatus?.call('authorized');
          return true;
        }

        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final error = json['error'] as String? ?? 'unknown';

        if (error == 'authorization_pending') {
          onStatus?.call('pending');
        } else if (error == 'slow_down') {
          interval += 5;
          onStatus?.call('slow_down');
        } else if (error == 'expired_token' || error == 'access_denied') {
          onStatus?.call(error);
          return false;
        } else {
          _log.w('Device flow poll unexpected error: $error');
          onStatus?.call(error);
          return false;
        }
      }
      onStatus?.call('expired_token');
      return false;
    } catch (e) {
      _log.e('Device flow poll error: $e');
      return false;
    } finally {
      client.close();
    }
  }

  Future<bool> _refreshDeviceFlowToken() async {
    if (_clientId == null || _deviceFlowRefreshToken == null) return false;
    final client = http.Client();
    try {
      final resp = await client.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        body: {
          'client_id': _clientId!,
          'refresh_token': _deviceFlowRefreshToken!,
          'grant_type': 'refresh_token',
        },
      );
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        _deviceFlowAccessToken = json['access_token'] as String;
        final expiresIn = json['expires_in'] as int? ?? 3600;
        _deviceFlowTokenExpiry =
            DateTime.now().add(Duration(seconds: expiresIn));
        _log.i('Device flow token refreshed');
        return true;
      }
      _log.w('Device flow refresh failed: ${resp.statusCode}');
      return false;
    } catch (e) {
      _log.e('Device flow refresh error: $e');
      return false;
    } finally {
      client.close();
    }
  }

  Future<void> _fetchDeviceFlowUserInfo() async {
    if (_deviceFlowAccessToken == null) return;
    final client = http.Client();
    try {
      final resp = await client.get(
        Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
        headers: {'Authorization': 'Bearer $_deviceFlowAccessToken'},
      );
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        _deviceFlowEmail = json['email'] as String?;
        if (_deviceFlowEmail != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefEmail, _deviceFlowEmail!);
        }
      }
    } catch (e) {
      _log.w('Failed to fetch device flow user info: $e');
    } finally {
      client.close();
    }
  }

  Future<http.Client?> get authenticatedClient async {

    if (_deviceFlowAccessToken != null) {

      if (_deviceFlowTokenExpiry != null &&
          DateTime.now()
              .isAfter(_deviceFlowTokenExpiry!.subtract(const Duration(minutes: 5)))) {
        await _refreshDeviceFlowToken();
      }
      if (_deviceFlowAccessToken != null) {
        final credentials = gauth.AccessCredentials(
          gauth.AccessToken(
            'Bearer',
            _deviceFlowAccessToken!,
            _deviceFlowTokenExpiry ?? DateTime.now().toUtc().add(const Duration(minutes: 55)),
          ),
          _deviceFlowRefreshToken,
          [drive.DriveApi.driveAppdataScope],
        );
        return gauth.authenticatedClient(http.Client(), credentials);
      }
    }

    final user = _currentUser;
    if (user == null) return null;

    try {
      // v7.2.0: accessToken is obtained via authorizationClient
      final authz = await user.authorizationClient
          .authorizationForScopes(_driveScopes);
      if (authz == null) return null;

      final credentials = gauth.AccessCredentials(
        gauth.AccessToken(
          'Bearer',
          authz.accessToken,
          DateTime.now().toUtc().add(const Duration(minutes: 55)),
        ),
        null,
        _driveScopes,
      );

      return gauth.authenticatedClient(http.Client(), credentials);
    } catch (e) {
      _log.e('Failed to build authenticated client: $e');
      return null;
    }
  }
}
