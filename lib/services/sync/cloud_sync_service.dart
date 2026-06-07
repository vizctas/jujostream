import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:googleapis/drive/v3.dart' as drive;
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

  String? lastError;

  static final _syncCompletedController = StreamController<void>.broadcast();
  static Stream<void> get onSyncCompleted => _syncCompletedController.stream;

  final _log = Logger(printer: SimplePrinter());

  /// Grace period timestamps for cloud-paired servers.
  /// Prevents the next poll from flipping pairState back to notPaired while
  /// the async _attemptCloudPairing POST is in flight or just completed.
  static const Duration _cloudPairingGrace = Duration(seconds: 20);
  final Map<String, DateTime> _cloudPairingGraceTimestamps = {};

  /// Returns true if the given server key (UUID or localAddress) is within
  /// the cloud-pairing grace window. Called by ComputerProvider to prevent
  /// polls from overwriting paired state immediately after cloud-sync.
  bool isInCloudPairingGrace(String key) {
    final stamp = _cloudPairingGraceTimestamps[key];
    if (stamp == null) return false;
    return DateTime.now().difference(stamp) < _cloudPairingGrace;
  }

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

      final media = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

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
          _kMicrotrailerMuted, data[_kMicrotrailerMuted] as bool);
    }
    if (data.containsKey(_kVideoDelaySecs)) {
      await prefs.setInt(_kVideoDelaySecs, data[_kVideoDelaySecs] as int);
    }

    if (data.containsKey(_kSavedComputers)) {
      final list = (data[_kSavedComputers] as List).cast<String>();
      await prefs.setStringList(_kSavedComputers, list);
    }
    if (data.containsKey(_kPrimaryServerKey)) {
      await prefs.setString(_kPrimaryServerKey, data[_kPrimaryServerKey] as String);
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

      // Fetch existing cloud profiles to detect conflicting server URLs for the same cert fingerprint
      final cloudProfilesResponse = await client
          .from('user_server_profiles')
          .select('id, server_url, cert_fingerprint')
          .eq('user_id', userId);
      final cloudProfiles = cloudProfilesResponse as List<dynamic>;

      final List<Map<String, dynamic>> rows = [];
      final Set<String> seenCerts = {};
      final List<String> idsToDelete = [];

      for (final entry in savedComputers) {
        try {
          final map = jsonDecode(entry) as Map<String, dynamic>;
          final computer = ComputerDetails.fromJson(map);

          final host = computer.manualAddress.isNotEmpty
              ? computer.manualAddress
              : computer.localAddress;
          if (host.isEmpty) continue;

          final cert = computer.serverCert.trim();
          final certValue = cert.isNotEmpty ? cert : null;

          if (certValue != null) {
            final certLower = certValue.toLowerCase();
            if (seenCerts.contains(certLower)) {
              _log.w('pushConfigToSupabase: skipping duplicate cert fingerprint: $certValue');
              continue;
            }
            seenCerts.add(certLower);

            // Detect conflict: cloud has this cert but under a different URL
            for (final row in cloudProfiles) {
              final cloudMap = row as Map<String, dynamic>;
              final cloudCert = cloudMap['cert_fingerprint']?.toString().trim();
              if (cloudCert != null && cloudCert.toLowerCase() == certLower) {
                final port = computer.httpsPort > 0 ? computer.httpsPort : 47984;
                final serverUrl = 'https://$host:$port';
                final cloudUrl = cloudMap['server_url']?.toString() ?? '';
                if (cloudUrl != serverUrl) {
                  _log.i('pushConfigToSupabase: URL changed for cert $certValue (cloud: $cloudUrl, local: $serverUrl). Scheduling delete.');
                  idsToDelete.add(cloudMap['id']?.toString() ?? '');
                }
              }
            }
          }

          final port = computer.httpsPort > 0 ? computer.httpsPort : 47984;
          final serverUrl = 'https://$host:$port';

          final localAddresses = <String>[];
          if (computer.localAddress.isNotEmpty) {
            localAddresses.add(computer.localAddress);
          }
          if (computer.activeAddress.isNotEmpty &&
              !localAddresses.contains(computer.activeAddress)) {
            localAddresses.add(computer.activeAddress);
          }
          if (computer.manualAddress.isNotEmpty &&
              !localAddresses.contains(computer.manualAddress)) {
            localAddresses.add(computer.manualAddress);
          }

          final key = computer.uuid.isNotEmpty ? computer.uuid : computer.localAddress;
          final orderIndex = customOrder.indexOf(key);
          final displayOrder = orderIndex >= 0 ? orderIndex : 0;

          final isDefault = computer.uuid.isNotEmpty && computer.uuid == primaryServerUuid;

          rows.add({
            'user_id': userId,
            'server_url': serverUrl,
            'server_name': computer.name,
            'local_addresses': localAddresses,
            'cert_fingerprint': certValue,
            'is_default': isDefault,
            'display_order': displayOrder,
            'external_address': computer.remoteAddress.isNotEmpty ? computer.remoteAddress : null,
            'server_version': computer.serverVersion,
          });
        } catch (e) {
          _log.w('pushConfigToSupabase: failed to parse computer entry: $e');
        }
      }

      // Delete conflicting cloud profiles first
      if (idsToDelete.isNotEmpty) {
        _log.i('pushConfigToSupabase: Deleting conflicting cloud profiles before upsert: $idsToDelete');
        await client
            .from('user_server_profiles')
            .delete()
            .inFilter('id', idsToDelete);
      }

      if (rows.isNotEmpty) {
        await client.from('user_server_profiles').upsert(
          rows,
          onConflict: 'user_id,server_url',
        );
      }

      _log.i('pushConfigToSupabase OK (${rows.length} servers)');
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
      final List<String> customOrder = prefs.getStringList(_kCustomOrderKey) ?? [];

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
          if (certFingerprint != null && certFingerprint.isNotEmpty) {
            local.serverCert = certFingerprint;
            local.pairState = PairState.paired;
            local.pairStatusFromHttps = true;
          }
          if (externalAddress != null && externalAddress.isNotEmpty) {
            local.remoteAddress = externalAddress;
          }
          if (serverVersion != null && serverVersion.isNotEmpty) {
            local.serverVersion = serverVersion;
          }
          
          if (isDefault) {
            primaryServerUuid = local.uuid;
          }
        } else {
          final host = cloudHost;
          final isIp = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host) || host.contains(':');
          
          final localAddresses = cloudMap['local_addresses'] as List<dynamic>? ?? [];
          final String localIp = localAddresses.isNotEmpty ? localAddresses.first.toString() : host;

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
            remoteAddress: externalAddress ?? '',
            serverCert: certFingerprint ?? '',
            state: ComputerState.unknown,
            pairState: (certFingerprint != null && certFingerprint.isNotEmpty)
                ? PairState.paired
                : PairState.notPaired,
            isCloud: true,
          );
          if (certFingerprint != null && certFingerprint.isNotEmpty) {
            computer.pairStatusFromHttps = true;
          }

          localComputers.add(computer);
          
          if (isDefault) {
            primaryServerUuid = computer.uuid;
          }
        }
      }

      final List<Map<String, dynamic>> localOnlyRows = [];
      final Set<String> seenCerts = {};
      for (final row in cloudProfiles) {
        final cloudMap = row as Map<String, dynamic>;
        final String? cert = cloudMap['cert_fingerprint']?.toString().trim();
        if (cert != null && cert.isNotEmpty) {
          seenCerts.add(cert.toLowerCase());
        }
      }

      for (final local in localComputers) {
        bool matchedInCloud = false;
        for (final row in cloudProfiles) {
          if (_doesMatch(local, row as Map<String, dynamic>)) {
            matchedInCloud = true;
            break;
          }
        }

        if (!matchedInCloud) {
          final host = local.manualAddress.isNotEmpty ? local.manualAddress : local.localAddress;
          if (host.isEmpty) continue;

          final cert = local.serverCert.trim();
          final certValue = cert.isNotEmpty ? cert : null;

          if (certValue != null) {
            if (seenCerts.contains(certValue.toLowerCase())) {
              _log.w('pullConfigFromSupabase: skipping local-only duplicate cert fingerprint: $certValue');
              continue;
            }
            seenCerts.add(certValue.toLowerCase());
          }

          final port = local.httpsPort > 0 ? local.httpsPort : 47984;
          final serverUrl = 'https://$host:$port';

          final localAddresses = <String>[];
          if (local.localAddress.isNotEmpty) {
            localAddresses.add(local.localAddress);
          }
          if (local.activeAddress.isNotEmpty &&
              !localAddresses.contains(local.activeAddress)) {
            localAddresses.add(local.activeAddress);
          }
          if (local.manualAddress.isNotEmpty &&
              !localAddresses.contains(local.manualAddress)) {
            localAddresses.add(local.manualAddress);
          }

          final key = local.uuid.isNotEmpty ? local.uuid : local.localAddress;
          final orderIndex = customOrder.indexOf(key);
          final displayOrder = orderIndex >= 0 ? orderIndex : 0;

          final isDefault = local.uuid.isNotEmpty && local.uuid == primaryServerUuid;

          localOnlyRows.add({
            'user_id': userId,
            'server_url': serverUrl,
            'server_name': local.name,
            'local_addresses': localAddresses,
            'cert_fingerprint': certValue,
            'is_default': isDefault,
            'display_order': displayOrder,
            'external_address': local.remoteAddress.isNotEmpty ? local.remoteAddress : null,
            'server_version': local.serverVersion,
            // Push the real Sunshine server uniqueid so other devices can use it
            if (local.uuid.isNotEmpty) 'server_uuid': local.uuid,
          });
        }
      }

      if (localOnlyRows.isNotEmpty) {
        _log.i('pullConfigFromSupabase: pushing ${localOnlyRows.length} local-only servers to cloud');
        await client.from('user_server_profiles').upsert(
          localOnlyRows,
          onConflict: 'user_id,server_url',
        );
      }

      final jsonList = localComputers.map((c) => jsonEncode(c.toJson())).toList();
      await prefs.setStringList(_kSavedComputers, jsonList);

      if (primaryServerUuid != null && primaryServerUuid.isNotEmpty) {
        await prefs.setString(_kPrimaryServerKey, primaryServerUuid);
      }

      _syncCompletedController.add(null);
      _log.i('pullConfigFromSupabase OK: merged ${cloudProfiles.length} servers');

      // Asynchronously trigger cloud pairing with all synced servers.
      // IMPORTANT: stamp grace period immediately before firing the unawaited
      // request. Without this, the next poll (≤3s) fires before cloud-pairing
      // completes and flips pairState back to notPaired via _addOrUpdateComputer.
      final token = client.auth.currentSession?.accessToken;
      if (token != null) {
        final now = DateTime.now();
        for (final computer in localComputers) {
          final host = computer.manualAddress.isNotEmpty ? computer.manualAddress : computer.localAddress;
          if (host.isNotEmpty) {
            // Stamp grace period so polls don't overwrite paired state while
            // the async cloud-pairing POST is in flight.
            _cloudPairingGraceTimestamps[computer.uuid.isNotEmpty ? computer.uuid : host] = now;
            final port = computer.httpsPort > 0 ? computer.httpsPort : 47984;
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
    if (cloudCert != null && cloudCert.isNotEmpty && local.serverCert.isNotEmpty) {
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

    final List<dynamic>? localAddrs = cloud['local_addresses'] as List<dynamic>?;
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
      final clean = url.replaceFirst('https://', '').replaceFirst('http://', '');
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
      final clean = url.replaceFirst('https://', '').replaceFirst('http://', '');
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

      final deviceName = Platform.localHostname;
      final body = jsonEncode({
        'token': token,
        'clientCert': clientPem,
        'deviceName': deviceName.isNotEmpty ? deviceName : 'Jujo.Stream Client',
      });

      final uri = Uri.parse('$serverUrl/api/pair/cloud');
      
      final ioClient = ClientIdentity.createHttpClient();
      final client = IOClient(ioClient);
      
      try {
        final response = await client.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: body,
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final resBody = jsonDecode(response.body) as Map<String, dynamic>;
          if (resBody['status'] == true) {
            _log.i('Cloud pairing succeeded with $serverUrl');
            // Update the computer object in-memory and persist so the UI
            // immediately reflects paired state without waiting for the next poll.
            computer.pairState = PairState.paired;
            computer.pairStatusFromHttps = true;
            _cloudPairingGraceTimestamps[
              computer.uuid.isNotEmpty ? computer.uuid : computer.localAddress
            ] = DateTime.now();
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
          } else {
            _log.w('Cloud pairing rejected by $serverUrl: ${resBody["error"]}');
          }
        } else {
          _log.w('Cloud pairing HTTP ${response.statusCode} from $serverUrl: ${response.body}');
        }
      } finally {
        client.close();
      }
    } catch (e) {
      _log.w('Cloud pairing failed for $serverUrl: $e');
    }
  }
}
