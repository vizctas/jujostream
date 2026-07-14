import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/computer_details.dart';
import '../auth/google_auth_service.dart';
import '../crypto/client_identity.dart';

class CloudSyncService {
  CloudSyncService._();
  static final instance = CloudSyncService._();

  http.Client Function(ComputerDetails computer)? _pairingClientFactoryForTest;

  @visibleForTesting
  set pairingClientFactoryForTest(
    http.Client Function(ComputerDetails computer)? factory,
  ) {
    _pairingClientFactoryForTest = factory;
  }

  String? lastError;

  static final _syncCompletedController = StreamController<void>.broadcast();
  static Stream<void> get onSyncCompleted => _syncCompletedController.stream;

  final _log = Logger(printer: SimplePrinter());

  /// Grace period timestamps for cloud-paired servers.
  /// Prevents the next poll from flipping pairState back to notPaired while
  /// the async _attemptCloudPairing POST is in flight or just completed.
  static const Duration _cloudPairingGrace = Duration(seconds: 60);
  final Map<String, DateTime> _cloudPairingGraceTimestamps = {};

  /// Returns true if the given server key (UUID or localAddress) is within
  /// the cloud-pairing grace window. Called by ComputerProvider to prevent
  /// polls from overwriting paired state immediately after cloud-sync.
  bool isInCloudPairingGrace(String key) {
    final stamp = _cloudPairingGraceTimestamps[key];
    if (stamp == null) return false;
    return DateTime.now().difference(stamp) < _cloudPairingGrace;
  }

  /// Returns the confighttp HTTPS port for cloud pairing calls.
  /// confighttp runs at base+1, nvhttp HTTPS at base-5 → offset is always 6.
  /// Uses the stored configHttpsPort when available (set from server_url in Supabase),
  /// falling back to httpsPort+6 for servers that were locally paired before cloud sync.
  static int _configPort(ComputerDetails c) =>
      c.configHttpsPort > 0 ? c.configHttpsPort : c.httpsPort + 6;

  static const _fileName = 'jujostream_config.json';
  static const _mimeType = 'application/json';

  static const _kStreamConfig = 'stream_config';

  static const _kTheme = 'app_theme';
  static const _kReduceEffects = 'reduce_effects';
  static const _kPerformanceMode = 'performance_mode';

  static const _kLocale = 'app_locale';

  static const _kPluginEnabledPrefix = 'plugin_enabled_';
  static const _kPluginApiKeyPrefix = 'plugin_apikey_';
  static const _kMicrotrailerMuted = 'microtrailer_muted';
  static const _kVideoDelaySecs = 'microtrailer_delay_secs';
  static const _kPluginSettingPrefix = 'plugin_setting_';

  static const _kSavedComputers = 'saved_computers';
  static const _kPrimaryServerKey = 'primary_server_uuid';
  static const _kCustomOrderKey = 'computer_custom_order';

  Future<bool> pushConfig() async {
    lastError = null;
    final client = await GoogleAuthService.instance.authenticatedClient;
    if (client == null) {
      _log.w('pushConfig: not authenticated');
      lastError = 'Not authenticated with Google.';
      return false;
    }

    try {
      final driveApi = drive.DriveApi(client);
      final payload = await _collectLocalConfig();
      final bytes = utf8.encode(jsonEncode(payload));

      final existingId = await _findConfigFileId(driveApi);

      final media = drive.Media(
        Stream.value(bytes),
        bytes.length,
        contentType: _mimeType,
      );

      if (existingId != null) {
        await driveApi.files.update(
          drive.File()..name = _fileName,
          existingId,
          uploadMedia: media,
        );
      } else {
        await driveApi.files.create(
          drive.File()
            ..name = _fileName
            ..parents = ['appDataFolder'],
          uploadMedia: media,
        );
      }

      _log.i('pushConfig OK (${bytes.length} bytes)');
      return true;
    } catch (e) {
      _log.e('pushConfig failed: $e');
      lastError = e.toString();
      return false;
    } finally {
      client.close();
    }
  }

  Future<bool> pullConfig() async {
    lastError = null;
    final client = await GoogleAuthService.instance.authenticatedClient;
    if (client == null) {
      _log.w('pullConfig: not authenticated');
      lastError = 'Not authenticated with Google.';
      return false;
    }

    try {
      final driveApi = drive.DriveApi(client);
      final fileId = await _findConfigFileId(driveApi);
      if (fileId == null) {
        _log.i('pullConfig: no cloud config found');
        return false;
      }

      final media =
          await driveApi.files.get(
                fileId,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;

      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }

      final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      await _applyCloudConfig(payload);
      _syncCompletedController.add(null);

      _log.i('pullConfig OK');
      return true;
    } catch (e) {
      _log.e('pullConfig failed: $e');
      lastError = e.toString();
      return false;
    } finally {
      client.close();
    }
  }

  Future<String?> _findConfigFileId(drive.DriveApi api) async {
    final list = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_fileName'",
      $fields: 'files(id)',
    );
    final files = list.files;
    if (files == null || files.isEmpty) return null;
    return files.first.id;
  }

  Future<Map<String, dynamic>> _collectLocalConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{
      'version': 1,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    final streamConfig = prefs.getString(_kStreamConfig);
    if (streamConfig != null) data[_kStreamConfig] = streamConfig;

    final theme = prefs.getString(_kTheme);
    if (theme != null) data[_kTheme] = theme;
    data[_kReduceEffects] = prefs.getBool(_kReduceEffects) ?? false;
    data[_kPerformanceMode] = prefs.getBool(_kPerformanceMode) ?? false;

    final locale = prefs.getString(_kLocale);
    if (locale != null) data[_kLocale] = locale;

    final pluginToggles = <String, bool>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_kPluginEnabledPrefix)) {
        pluginToggles[key] = prefs.getBool(key) ?? false;
      }
    }
    data['plugin_toggles'] = pluginToggles;

    final pluginSettings = <String, String>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_kPluginSettingPrefix)) {
        final val = prefs.getString(key);
        if (val != null) pluginSettings[key] = val;
      }
    }
    data['plugin_settings'] = pluginSettings;

    final pluginApiKeys = <String, String>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_kPluginApiKeyPrefix)) {
        final val = prefs.getString(key);
        if (val != null && val.isNotEmpty) pluginApiKeys[key] = val;
      }
    }
    data['plugin_api_keys'] = pluginApiKeys;

    data[_kMicrotrailerMuted] = prefs.getBool(_kMicrotrailerMuted) ?? true;
    data[_kVideoDelaySecs] = prefs.getInt(_kVideoDelaySecs) ?? 3;

    final savedComputers = prefs.getStringList(_kSavedComputers);
    if (savedComputers != null) data[_kSavedComputers] = savedComputers;

    final primaryServer = prefs.getString(_kPrimaryServerKey);
    if (primaryServer != null) data[_kPrimaryServerKey] = primaryServer;

    final customOrder = prefs.getStringList(_kCustomOrderKey);
    if (customOrder != null) data[_kCustomOrderKey] = customOrder;

    return data;
  }

  Future<void> _applyCloudConfig(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();

    if (data.containsKey(_kStreamConfig)) {
      await prefs.setString(_kStreamConfig, data[_kStreamConfig] as String);
    }

    if (data.containsKey(_kTheme)) {
      await prefs.setString(_kTheme, data[_kTheme] as String);
    }
    if (data.containsKey(_kReduceEffects)) {
      await prefs.setBool(_kReduceEffects, data[_kReduceEffects] as bool);
    }
    if (data.containsKey(_kPerformanceMode)) {
      await prefs.setBool(_kPerformanceMode, data[_kPerformanceMode] as bool);
    }

    if (data.containsKey(_kLocale)) {
      await prefs.setString(_kLocale, data[_kLocale] as String);
    }

    if (data.containsKey('plugin_toggles')) {
      final toggles = data['plugin_toggles'] as Map<String, dynamic>;
      for (final entry in toggles.entries) {
        await prefs.setBool(entry.key, entry.value as bool);
      }
    }

    if (data.containsKey('plugin_settings')) {
      final settings = data['plugin_settings'] as Map<String, dynamic>;
      for (final entry in settings.entries) {
        await prefs.setString(entry.key, entry.value as String);
      }
    }

    if (data.containsKey('plugin_api_keys')) {
      final apiKeys = data['plugin_api_keys'] as Map<String, dynamic>;
      for (final entry in apiKeys.entries) {
        await prefs.setString(entry.key, entry.value as String);
      }
    }

    if (data.containsKey(_kMicrotrailerMuted)) {
      await prefs.setBool(
        _kMicrotrailerMuted,
        data[_kMicrotrailerMuted] as bool,
      );
    }
    if (data.containsKey(_kVideoDelaySecs)) {
      await prefs.setInt(_kVideoDelaySecs, data[_kVideoDelaySecs] as int);
    }

    if (data.containsKey(_kSavedComputers)) {
      final list = (data[_kSavedComputers] as List).cast<String>();
      await prefs.setStringList(_kSavedComputers, list);
    }
    if (data.containsKey(_kPrimaryServerKey)) {
      await prefs.setString(
        _kPrimaryServerKey,
        data[_kPrimaryServerKey] as String,
      );
    }
    if (data.containsKey(_kCustomOrderKey)) {
      final list = (data[_kCustomOrderKey] as List).cast<String>();
      await prefs.setStringList(_kCustomOrderKey, list);
    }
  }

  Future<bool> pushConfigToSupabase() async {
    lastError = null;
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      _log.w('pushConfigToSupabase: not authenticated');
      lastError = 'Not authenticated with Supabase.';
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedComputers = prefs.getStringList(_kSavedComputers) ?? const [];
      final primaryServerUuid = prefs.getString(_kPrimaryServerKey);
      final customOrder = prefs.getStringList(_kCustomOrderKey) ?? const [];

      // Only the server's cloud agent creates/owns user_server_profiles rows.
      // The client only UPDATES preference fields (is_default, display_order)
      // on rows that already exist — never inserts, never touches server_url.
      final cloudProfilesResponse = await client
          .from('user_server_profiles')
          .select(
            'id, server_url, cert_fingerprint, local_addresses, server_uuid',
          )
          .eq('user_id', userId);
      final cloudProfiles = cloudProfilesResponse as List<dynamic>;

      int updated = 0;
      for (final entry in savedComputers) {
        try {
          final map = jsonDecode(entry) as Map<String, dynamic>;
          final computer = ComputerDetails.fromJson(map);

          Map<String, dynamic>? matchedRow;
          for (final row in cloudProfiles) {
            if (_doesMatch(computer, row as Map<String, dynamic>)) {
              matchedRow = row;
              break;
            }
          }
          if (matchedRow == null) continue;

          final rowId = matchedRow['id']?.toString();
          if (rowId == null || rowId.isEmpty) continue;

          final key = computer.uuid.isNotEmpty
              ? computer.uuid
              : computer.localAddress;
          final orderIndex = customOrder.indexOf(key);
          final displayOrder = orderIndex >= 0 ? orderIndex : 0;
          final isDefault =
              computer.uuid.isNotEmpty && computer.uuid == primaryServerUuid;

          await client
              .from('user_server_profiles')
              .update({'is_default': isDefault, 'display_order': displayOrder})
              .eq('id', rowId);
          updated++;
        } catch (e) {
          _log.w('pushConfigToSupabase: failed to process computer entry: $e');
        }
      }

      _log.i('pushConfigToSupabase OK ($updated profile updates)');
      return true;
    } catch (e, stack) {
      _log.e('pushConfigToSupabase failed: $e\n$stack');
      lastError = e is PostgrestException ? e.message : e.toString();
      return false;
    }
  }

  Future<bool> pullConfigFromSupabase() async {
    lastError = null;
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      _log.w('pullConfigFromSupabase: not authenticated');
      lastError = 'Not authenticated with Supabase.';
      return false;
    }

    try {
      final response = await client
          .from('user_server_profiles')
          .select()
          .eq('user_id', userId);

      final cloudProfiles = response as List<dynamic>;

      final prefs = await SharedPreferences.getInstance();
      final savedComputers = prefs.getStringList(_kSavedComputers) ?? const [];

      final List<ComputerDetails> localComputers = [];
      for (final entry in savedComputers) {
        try {
          final map = jsonDecode(entry) as Map<String, dynamic>;
          localComputers.add(ComputerDetails.fromJson(map));
        } catch (_) {}
      }

      String? primaryServerUuid = prefs.getString(_kPrimaryServerKey);

      for (final row in cloudProfiles) {
        final cloudMap = row as Map<String, dynamic>;
        final String serverUrl = cloudMap['server_url'] ?? '';
        if (serverUrl.isEmpty) continue;

        final cloudHost = _getHostFromUrl(serverUrl);
        final cloudPort = _getPortFromUrl(serverUrl);
        final String? cloudName = cloudMap['server_name'];
        final String? certFingerprint = cloudMap['cert_fingerprint'];
        final String? externalAddress = cloudMap['external_address'];
        final String? serverVersion = cloudMap['server_version'];
        final bool isDefault = cloudMap['is_default'] ?? false;

        // Rows without a cert fingerprint are not maintained by the server's
        // cloud agent (stale rows from older client versions, or localhost
        // registrations). They can never be cloud-paired — skip them so they
        // don't poison configHttpsPort, isCloud, or spawn ghost computers.
        final hasCert =
            certFingerprint != null && certFingerprint.trim().isNotEmpty;
        if (!hasCert) {
          _log.w(
            'pullConfigFromSupabase: skipping profile without cert: $serverUrl',
          );
          continue;
        }

        int matchIdx = -1;
        for (int i = 0; i < localComputers.length; i++) {
          if (_doesMatch(localComputers[i], cloudMap)) {
            matchIdx = i;
            break;
          }
        }

        if (matchIdx >= 0) {
          final local = localComputers[matchIdx];
          local.isCloud = true;
          if (cloudName != null && cloudName.isNotEmpty) {
            local.name = cloudName;
          }
          local.serverCert = certFingerprint;
          // Cloud ownership does not prove that this device certificate is
          // registered on the server. Preserve locally confirmed state and let
          // HTTPS polling or the cloud-pairing POST establish pairing.
          local.pairStatusFromHttps = false;
          if (externalAddress != null && externalAddress.isNotEmpty) {
            local.remoteAddress = externalAddress;
          }
          if (serverVersion != null && serverVersion.isNotEmpty) {
            local.serverVersion = serverVersion;
          }
          // Always update configHttpsPort from cloud so cloud-pairing POSTs
          // reach the confighttp server (port base+1) rather than nvhttp (base-5).
          if (cloudPort > 0) {
            local.configHttpsPort = cloudPort;
          }

          if (isDefault) {
            primaryServerUuid = local.uuid;
          }
        } else {
          final host = cloudHost;
          final isIp =
              RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host) ||
              host.contains(':');

          final localAddresses =
              cloudMap['local_addresses'] as List<dynamic>? ?? [];
          final String localIp = localAddresses.isNotEmpty
              ? localAddresses.first.toString()
              : host;

          // Prefer server_uuid (real Sunshine uniqueid) over Supabase row id.
          // Using the row id caused UUID mismatches during polling because
          // parseServerInfo sets uuid from the XML 'uniqueid' field.
          final serverUuid = (cloudMap['server_uuid'] as String?)?.trim() ?? '';
          final computer = ComputerDetails(
            uuid: serverUuid.isNotEmpty ? serverUuid : (cloudMap['id'] ?? ''),
            name: cloudName ?? host,
            localAddress: localIp,
            manualAddress: isIp ? '' : host,
            httpsPort: cloudPort,
            configHttpsPort: cloudPort,
            remoteAddress: externalAddress ?? '',
            serverCert: certFingerprint,
            state: ComputerState.unknown,
            pairState: PairState.notPaired,
            isCloud: true,
          );

          localComputers.add(computer);

          if (isDefault) {
            primaryServerUuid = computer.uuid;
          }
        }
      }

      // Only the server registers itself in the cloud (via its cloud agent).
      // The client must never create user_server_profiles rows — doing so made
      // every local server look cloud-registered (CLOUD chip everywhere) and
      // produced stale duplicate rows that cloud pairing could never satisfy.
      // Local computers that match no cloud profile are local-only: clear the
      // flag so the chip reflects genuine cloud registration.
      for (final local in localComputers) {
        bool matchedInCloud = false;
        for (final row in cloudProfiles) {
          final cloudMap = row as Map<String, dynamic>;
          final cert = cloudMap['cert_fingerprint']?.toString().trim() ?? '';
          if (cert.isEmpty) continue; // not a server-agent row
          if (_doesMatch(local, cloudMap)) {
            matchedInCloud = true;
            break;
          }
        }
        if (!matchedInCloud) {
          local.isCloud = false;
        }
      }

      final jsonList = localComputers
          .map((c) => jsonEncode(c.toJson()))
          .toList();
      await prefs.setStringList(_kSavedComputers, jsonList);

      if (primaryServerUuid != null && primaryServerUuid.isNotEmpty) {
        await prefs.setString(_kPrimaryServerKey, primaryServerUuid);
      }

      _syncCompletedController.add(null);
      _log.i(
        'pullConfigFromSupabase OK: merged ${cloudProfiles.length} servers',
      );

      // Asynchronously trigger cloud pairing with all synced servers.
      // IMPORTANT: stamp grace period immediately before firing the unawaited
      // request. Without this, the next poll (≤3s) fires before cloud-pairing
      // completes and flips pairState back to notPaired via _addOrUpdateComputer.
      final token = client.auth.currentSession?.accessToken;
      if (token != null) {
        final now = DateTime.now();
        for (final computer in localComputers) {
          if (!computer.isCloud) continue;
          final host = computer.manualAddress.isNotEmpty
              ? computer.manualAddress
              : computer.localAddress;
          if (host.isNotEmpty) {
            // Stamp grace period so polls don't overwrite paired state while
            // the async cloud-pairing POST is in flight.
            _cloudPairingGraceTimestamps[computer.uuid.isNotEmpty
                    ? computer.uuid
                    : host] =
                now;
            final port = _configPort(computer);
            final serverUrl = 'https://$host:$port';
            unawaited(_attemptCloudPairing(serverUrl, token, computer));
          }
        }
      }

      return true;
    } catch (e, stack) {
      _log.e('pullConfigFromSupabase failed: $e\n$stack');
      lastError = e is PostgrestException ? e.message : e.toString();
      return false;
    }
  }

  bool _doesMatch(ComputerDetails local, Map<String, dynamic> cloud) {
    final String? cloudCert = cloud['cert_fingerprint'];
    if (cloudCert != null &&
        cloudCert.isNotEmpty &&
        local.serverCert.isNotEmpty) {
      if (local.serverCert.toLowerCase() == cloudCert.toLowerCase()) {
        return true;
      }
    }

    final String? serverUrl = cloud['server_url'];
    if (serverUrl != null && serverUrl.isNotEmpty) {
      final cloudHost = _getHostFromUrl(serverUrl).toLowerCase();
      if (cloudHost.isNotEmpty) {
        if (local.localAddress.toLowerCase() == cloudHost ||
            local.activeAddress.toLowerCase() == cloudHost ||
            local.manualAddress.toLowerCase() == cloudHost) {
          return true;
        }
      }
    }

    final List<dynamic>? localAddrs =
        cloud['local_addresses'] as List<dynamic>?;
    if (localAddrs != null) {
      for (final addr in localAddrs) {
        final cloudHost = addr.toString().toLowerCase();
        if (cloudHost.isNotEmpty) {
          if (local.localAddress.toLowerCase() == cloudHost ||
              local.activeAddress.toLowerCase() == cloudHost ||
              local.manualAddress.toLowerCase() == cloudHost) {
            return true;
          }
        }
      }
    }

    return false;
  }

  String _getHostFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (_) {
      final clean = url
          .replaceFirst('https://', '')
          .replaceFirst('http://', '');
      final colonIdx = clean.indexOf(':');
      if (colonIdx >= 0) {
        return clean.substring(0, colonIdx);
      }
      return clean;
    }
  }

  int _getPortFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasPort ? uri.port : 47984;
    } catch (_) {
      final clean = url
          .replaceFirst('https://', '')
          .replaceFirst('http://', '');
      final colonIdx = clean.indexOf(':');
      if (colonIdx >= 0) {
        return int.tryParse(clean.substring(colonIdx + 1)) ?? 47984;
      }
      return 47984;
    }
  }

  Future<void> _attemptCloudPairing(
    String serverUrl,
    String token,
    ComputerDetails computer,
  ) async {
    try {
      final clientPem = ClientIdentity.certPem;
      if (clientPem.isEmpty) {
        _log.w('Cloud pairing: certPem empty, skipping $serverUrl');
        return;
      }
      if (computer.serverCert.isEmpty) {
        _log.w(
          'Cloud pairing: server certificate missing, skipping $serverUrl',
        );
        return;
      }

      final deviceName = Platform.localHostname;
      final body = jsonEncode({
        'token': token,
        'clientCert': clientPem,
        'deviceName': deviceName.isNotEmpty ? deviceName : 'Jujo.Stream Client',
      });

      final uri = Uri.parse('$serverUrl/api/pair/cloud');

      // Use a clean HttpClient without presenting an untrusted client certificate during the TLS handshake.
      // The server companion will register the certificate passed in the JSON request body.
      final client =
          _pairingClientFactoryForTest?.call(computer) ??
          IOClient(
            ClientIdentity.createHttpClient(
              expectedServerCert: computer.serverCert,
              includeClientIdentity: false,
            ),
          );

      try {
        const maxAttempts = 3;
        for (int attempt = 1; attempt <= maxAttempts; attempt++) {
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
                .timeout(const Duration(seconds: 10));

            if (response.statusCode == 200) {
              final resBody = jsonDecode(response.body) as Map<String, dynamic>;
              if (resBody['status'] == true) {
                _log.i('Cloud pairing succeeded with $serverUrl');
                // Update the computer object in-memory and persist so the UI
                // immediately reflects paired state without waiting for the next poll.
                computer.pairState = PairState.paired;
                computer.pairStatusFromHttps = true;
                _cloudPairingGraceTimestamps[computer.uuid.isNotEmpty
                        ? computer.uuid
                        : computer.localAddress] =
                    DateTime.now();
                // Re-persist all computers with updated state.
                final prefs = await SharedPreferences.getInstance();
                final saved = prefs.getStringList(_kSavedComputers) ?? [];
                final updatedList = <String>[];
                for (final entry in saved) {
                  try {
                    final map = jsonDecode(entry) as Map<String, dynamic>;
                    final c = ComputerDetails.fromJson(map);
                    if ((computer.uuid.isNotEmpty && c.uuid == computer.uuid) ||
                        (c.localAddress.isNotEmpty &&
                            c.localAddress == computer.localAddress)) {
                      c.pairState = PairState.paired;
                      updatedList.add(jsonEncode(c.toJson()));
                    } else {
                      updatedList.add(entry);
                    }
                  } catch (_) {
                    updatedList.add(entry);
                  }
                }
                await prefs.setStringList(_kSavedComputers, updatedList);
                // Fire sync-completed so ComputerProvider reloads.
                _syncCompletedController.add(null);
                return;
              } else {
                _log.w(
                  'Cloud pairing rejected by $serverUrl: ${resBody["error"]}',
                );
                return; // business rejection — don't retry
              }
            } else {
              _log.w(
                'Cloud pairing HTTP ${response.statusCode} from $serverUrl '
                '(attempt $attempt/$maxAttempts)',
              );
              // server error — retry after backoff
            }
          } catch (e) {
            _log.w(
              'Cloud pairing attempt $attempt/$maxAttempts failed for $serverUrl: $e',
            );
          }
          if (attempt < maxAttempts) {
            await Future.delayed(Duration(seconds: attempt * 3));
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      _log.w('Cloud pairing failed for $serverUrl: $e');
    }
  }

  /// Re-attempts cloud pairing for a single computer regardless of its local
  /// pairState. Used as a recovery path when the server rejects the client
  /// cert (e.g. applist 401) even though local state says paired — the cloud
  /// row exists but the cert never landed in the server's registry.
  Future<void> repairCloudPairing(ComputerDetails computer) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    final host = computer.activeAddress.isNotEmpty
        ? computer.activeAddress
        : computer.manualAddress.isNotEmpty
        ? computer.manualAddress
        : computer.localAddress;
    if (host.isEmpty) return;
    final graceKey = computer.uuid.isNotEmpty ? computer.uuid : host;
    _cloudPairingGraceTimestamps[graceKey] = DateTime.now();
    await _attemptCloudPairing(
      'https://$host:${_configPort(computer)}',
      session.accessToken,
      computer,
    );
  }

  /// Notifies listeners that cloud auth state changed (e.g. sign-out) so the
  /// computer list re-evaluates visibility. The `isCloud` flag is intentionally
  /// preserved: cloud-paired servers are HIDDEN while signed out (filtered by
  /// ComputerProvider) and reappear on the next sign-in — they are never
  /// silently demoted to local servers, which previously left them enterable
  /// via cloud pairing after logout.
  Future<void> refreshCloudVisibility() async {
    try {
      _syncCompletedController.add(null);
    } catch (e) {
      _log.w('refreshCloudVisibility failed: $e');
    }
  }

  /// Re-fires cloud pairing for any `isCloud` server not yet confirmed paired.
  /// Called on app resume so a failed login-time POST gets another chance.
  Future<void> retryUnpairedCloudServers(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_kSavedComputers) ?? [];
      final now = DateTime.now();
      for (final entry in saved) {
        try {
          final computer = ComputerDetails.fromJson(
            jsonDecode(entry) as Map<String, dynamic>,
          );
          if (!computer.isCloud) continue;
          if (computer.pairState == PairState.paired) continue;
          final host = computer.manualAddress.isNotEmpty
              ? computer.manualAddress
              : computer.localAddress;
          if (host.isEmpty) continue;
          final graceKey = computer.uuid.isNotEmpty ? computer.uuid : host;
          _cloudPairingGraceTimestamps[graceKey] = now;
          unawaited(
            _attemptCloudPairing(
              'https://$host:${_configPort(computer)}',
              token,
              computer,
            ),
          );
        } catch (_) {}
      }
    } catch (e) {
      _log.w('retryUnpairedCloudServers failed: $e');
    }
  }
}
