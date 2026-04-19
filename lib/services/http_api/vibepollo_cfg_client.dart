import 'dart:convert';
import 'dart:io' as io;

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:logger/logger.dart';

class PlayniteGame {
  final String id;
  final String name;
  final List<String> categories;
  final bool installed;
  final String? pluginId;
  final String? pluginName;

  const PlayniteGame({
    required this.id,
    required this.name,
    required this.categories,
    required this.installed,
    this.pluginId,
    this.pluginName,
  });

  factory PlayniteGame.fromJson(Map<String, dynamic> j) => PlayniteGame(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        categories: (j['categories'] as List?)
                ?.map((c) => c.toString())
                .toList(growable: false) ??
            const [],
        installed: j['installed'] as bool? ?? true,
        pluginId: j['pluginId'] as String?,
        pluginName: j['pluginName'] as String?,
      );
}

class PlayniteCategory {
  final String id;
  final String name;

  const PlayniteCategory({required this.id, required this.name});

  factory PlayniteCategory.fromJson(Map<String, dynamic> j) => PlayniteCategory(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
      );
}

class PlayniteStatus {
  final bool active;
  final bool installed;
  final String? version;

  const PlayniteStatus({
    required this.active,
    required this.installed,
    this.version,
  });

  factory PlayniteStatus.fromJson(Map<String, dynamic> j) => PlayniteStatus(
        active: j['active'] as bool? ?? false,
        installed: j['installed'] as bool? ?? false,
        version: j['installed_version'] as String?,
      );
}

class VibepolloCfgClient {
  static const int defaultConfigPort = 47990;

  final Logger _log = Logger();

  String? _sessionCookie;

  http.Client _makeClient() {
    final ctx = io.SecurityContext(withTrustedRoots: false);
    final ioClient = io.HttpClient(context: ctx)
      ..badCertificateCallback = (cert, host, port) => true;
    return IOClient(ioClient);
  }

  String _base(String address, int port) => 'https://$address:$port';

  Future<bool> login(
    String address,
    String username,
    String password, {
    int port = defaultConfigPort,
  }) async {
    final client = _makeClient();
    try {
      final url = Uri.parse('${_base(address, port)}/api/auth/login');
      final body = jsonEncode({'username': username, 'password': password});
      final response = await client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _sessionCookie = _extractSessionCookie(response);
        _log.d('VibepolloCfg: login OK session=${_sessionCookie != null}');
        return true;
      }
      _log.w('VibepolloCfg: login failed ${response.statusCode}');
      return false;
    } catch (e) {
      _log.e('VibepolloCfg: login error $e');
      return false;
    } finally {
      client.close();
    }
  }

  String? _extractSessionCookie(http.Response response) {
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null) return null;

    final match =
        RegExp(r'__Host-apollo_session=([^;]+)').firstMatch(setCookie);
    return match?.group(1);
  }

  Map<String, String> get _authHeaders => _sessionCookie != null
      ? {'Cookie': '__Host-apollo_session=$_sessionCookie'}
      : {};

  Future<http.Response?> _get(
    String address,
    int port,
    String path,
    String username,
    String password, {
    bool retryOnUnauth = true,
  }) async {
    final client = _makeClient();
    try {
      final url = Uri.parse('${_base(address, port)}$path');
      var response = await client
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 401 && retryOnUnauth) {
        _log.d('VibepolloCfg: 401 on $path — re-authenticating');
        _sessionCookie = null;
        final ok = await login(address, username, password, port: port);
        if (!ok) return null;

        response = await client
            .get(url, headers: _authHeaders)
            .timeout(const Duration(seconds: 10));
      }

      if (response.statusCode != 200) {
        _log.w('VibepolloCfg: GET $path → ${response.statusCode}');
        return null;
      }
      return response;
    } catch (e) {
      _log.e('VibepolloCfg: GET $path error $e');
      return null;
    } finally {
      client.close();
    }
  }

  Future<List<PlayniteGame>> getPlayniteGames(
    String address,
    String username,
    String password, {
    int port = defaultConfigPort,
  }) async {
    final resp = await _get(address, port, '/api/playnite/games', username, password);
    if (resp == null) return const [];
    try {
      final list = jsonDecode(resp.body) as List;
      return list
          .cast<Map<String, dynamic>>()
          .map(PlayniteGame.fromJson)
          .toList(growable: false);
    } catch (e) {
      _log.e('VibepolloCfg: parse playnite games error $e');
      return const [];
    }
  }

  Future<List<PlayniteCategory>> getPlayniteCategories(
    String address,
    String username,
    String password, {
    int port = defaultConfigPort,
  }) async {
    final resp =
        await _get(address, port, '/api/playnite/categories', username, password);
    if (resp == null) return const [];
    try {
      final list = jsonDecode(resp.body) as List;
      return list
          .cast<Map<String, dynamic>>()
          .map(PlayniteCategory.fromJson)
          .toList(growable: false);
    } catch (e) {
      _log.e('VibepolloCfg: parse playnite categories error $e');
      return const [];
    }
  }

  Future<PlayniteStatus?> getPlayniteStatus(
    String address,
    String username,
    String password, {
    int port = defaultConfigPort,
  }) async {
    final resp =
        await _get(address, port, '/api/playnite/status', username, password);
    if (resp == null) return null;
    try {
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      return PlayniteStatus.fromJson(j);
    } catch (e) {
      _log.e('VibepolloCfg: parse playnite status error $e');
      return null;
    }
  }

  Future<bool> forceSync(
    String address,
    String username,
    String password, {
    int port = defaultConfigPort,
  }) async {
    if (_sessionCookie == null) {
      final ok = await login(address, username, password, port: port);
      if (!ok) return false;
    }
    final client = _makeClient();
    try {
      final url = Uri.parse('${_base(address, port)}/api/playnite/force_sync');
      final response = await client
          .post(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (e) {
      _log.e('VibepolloCfg: force_sync error $e');
      return false;
    } finally {
      client.close();
    }
  }

  void clearSession() => _sessionCookie = null;
}
