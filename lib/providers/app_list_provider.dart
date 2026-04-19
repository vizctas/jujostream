import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/nv_app.dart';
import '../models/computer_details.dart';
import '../models/stream_configuration.dart';
import '../services/http_api/nv_http_client.dart';
import '../services/http_api/vibepollo_cfg_client.dart';
import '../services/stream/host_preset_profiles.dart';
import '../services/metadata/rawg_client.dart';
import '../services/metadata/steam_video_client.dart';
import '../services/database/app_override_service.dart';
import '../services/database/metadata_database.dart';
import '../services/database/session_history_service.dart';
import '../services/notifications/notification_service.dart';
import 'plugins_provider.dart';

export '../services/http_api/nv_http_client.dart' show LaunchResult;
export '../services/http_api/vibepollo_cfg_client.dart'
    show PlayniteCategory, PlayniteStatus;

class AppListProvider extends ChangeNotifier {
  final NvHttpClient _httpClient = NvHttpClient();
  final VibepolloCfgClient _cfgClient = VibepolloCfgClient();
  final RawgClient _rawgClient = RawgClient();
  final SteamVideoClient _steamClient = SteamVideoClient();
  final PluginsProvider _plugins;

  AppListProvider(this._plugins);

  List<NvApp> _apps = [];
  List<PlayniteCategory> _playniteCategories = const [];
  bool _isLoading = false;
  bool _isEnriching = false;
  bool _cfgAuthRequired = false;
  bool _playniteActive = false;
  String? _error;
  ComputerDetails? _currentComputer;
  bool _disposed = false;
  int _enrichGeneration = 0;
  bool _enrichedOnce = false;
  bool _silentRefreshInProgress = false;

  final Map<int, NvApp> _fullAppCache = {};

  String? _cfgUsername;
  String? _cfgPassword;

  List<NvApp> get apps => List.unmodifiable(_apps);
  List<PlayniteCategory> get playniteCategories => _playniteCategories;
  bool get isLoading => _isLoading;
  bool get isEnriching => _isEnriching;
  bool get cfgAuthRequired => _cfgAuthRequired;
  bool get playniteActive => _playniteActive;
  String? get error => _error;
  ComputerDetails? get currentComputer => _currentComputer;

  bool _appsContentEqual(List<NvApp> a, List<NvApp> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!a[i].contentEquals(b[i])) return false;
    }
    return true;
  }

  void reapplyUserOverrides() {
    _applyUserOverrides();
    if (!_disposed) notifyListeners();
  }

  void _applyUserOverrides() {
    final serverId = _currentComputer?.uuid ?? 'default';
    final svc = AppOverrideService.instance;
    _apps = _apps
        .map((app) {
          final customName = svc.getCustomName(serverId, app.appId);
          final customPoster = svc.getCustomPosterUrl(serverId, app.appId);
          if (customName == null && customPoster == null) return app;
          return app.copyWith(appName: customName, posterUrl: customPoster);
        })
        .toList(growable: false);
  }

  static const _cachePrefix = 'appCacheV1_';

  Future<void> _persistAppCache(String serverUuid) async {
    if (serverUuid.isEmpty || _fullAppCache.isEmpty) return;
    try {
      final encoded = jsonEncode(
        _fullAppCache.values.map((a) => a.toJson()).toList(growable: false),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_cachePrefix$serverUuid', encoded);
    } catch (_) {}
  }

  Future<void> _restoreAppCache(String serverUuid) async {
    if (serverUuid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cachePrefix$serverUuid');
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(
        NvApp.fromJson,
      );
      for (final app in list) {
        _fullAppCache.putIfAbsent(app.appId, () => app);
      }
    } catch (_) {}
  }

  Future<void> loadStoredCfgCredentials(String serverUuid) async {
    if (serverUuid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    _cfgUsername = prefs.getString('vibepollo_cfg_user_$serverUuid');
    _cfgPassword = prefs.getString('vibepollo_cfg_pass_$serverUuid');
  }

  Future<void> saveCfgCredentials(
    String serverUuid,
    String username,
    String password,
  ) async {
    _cfgUsername = username;
    _cfgPassword = password;
    _cfgClient.clearSession();
    _cfgAuthRequired = false;
    if (serverUuid.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('vibepollo_cfg_user_$serverUuid', username);
      await prefs.setString('vibepollo_cfg_pass_$serverUuid', password);
    }
    notifyListeners();
  }

  Future<void> loadApps(ComputerDetails computer, {bool silent = false}) async {
    if (silent && _silentRefreshInProgress) return;
    final isNewServer = _currentComputer?.uuid != computer.uuid;
    _currentComputer = computer;
    if (!silent) {
      _isLoading = true;
      _isEnriching = false;
      _enrichedOnce = false;
      _error = null;
      _apps = [];
      if (isNewServer) {
        _fullAppCache.clear();
        // reload persisted cache so we don't lose apps after crash/restart
        await _restoreAppCache(computer.uuid);
      }
      if (!_disposed) notifyListeners();
    } else {
      _silentRefreshInProgress = true;
    }

    try {
      final address = computer.activeAddress.isNotEmpty
          ? computer.activeAddress
          : computer.localAddress;

      final httpsPort = computer.httpsPort > 0
          ? computer.httpsPort
          : NvHttpClient.defaultHttpsPort;

      final result = await _httpClient
          .getAppList(address, httpsPort: httpsPort)
          .timeout(const Duration(seconds: 12), onTimeout: () => const []);

      _httpClient
          .getServerInfoHttps(
            address,
            httpsPort: httpsPort,
            httpPort: computer.externalPort > 0
                ? computer.externalPort
                : NvHttpClient.defaultHttpPort,
          )
          .timeout(const Duration(seconds: 5), onTimeout: () => null)
          .then((serverInfo) {
            if (serverInfo != null && _currentComputer?.uuid == computer.uuid) {
              final newRunningId = serverInfo.runningGameId;
              computer.runningGameId = newRunningId;

              if (newRunningId > 0 && !_disposed) {
                final needsUpdate = !_apps.any(
                  (a) => a.appId == newRunningId && a.isRunning,
                );
                if (needsUpdate) {
                  _apps = _apps
                      .map((a) {
                        final shouldRun = a.appId == newRunningId;
                        if (a.isRunning == shouldRun) return a;
                        return a.copyWith(isRunning: shouldRun);
                      })
                      .toList(growable: false);
                  notifyListeners();
                }
              }
            }
          })
          .catchError((_) {});
      final runningId = computer.runningGameId;

      final prevById = silent
          ? <int, NvApp>{for (final a in _apps) a.appId: a}
          : const <int, NvApp>{};
      final freshApps = result
          .map((app) {
            final cleanName = app.appName
                .replaceAll('\u200B', '')
                .replaceAll('\u200C', '');
            return NvApp(
              appId: app.appId,
              appName: cleanName,
              isRunning:
                  app.isRunning || (runningId > 0 && app.appId == runningId),
              isHdrSupported: app.isHdrSupported,
              posterUrl: app.posterUrl,
              serverUuid: app.serverUuid,
            );
          })
          .toList(growable: false);

      // always merge — never discard previously discovered apps
      // (some servers return only the running app during active sessions)
      for (final app in freshApps) {
        _fullAppCache[app.appId] = app;
      }
      // persist so a crash/restart doesn't lose the full list
      unawaited(_persistAppCache(computer.uuid));
      final useCache =
          _fullAppCache.length > freshApps.length && _fullAppCache.isNotEmpty;

      if (useCache) {
        int effectiveRunningId = runningId;
        if (effectiveRunningId <= 0 && freshApps.isNotEmpty) {
          final runningFresh = freshApps.firstWhere(
            (a) => a.isRunning,
            orElse: () => freshApps.first,
          );
          if (freshApps.length == 1 || runningFresh.isRunning) {
            effectiveRunningId = runningFresh.appId;
          }
        }
        _apps = _fullAppCache.values
            .map((cached) {
              final isNowRunning =
                  effectiveRunningId > 0 && cached.appId == effectiveRunningId;
              final prev = prevById[cached.appId];
              if (prev != null) return prev.copyWith(isRunning: isNowRunning);
              return cached.copyWith(isRunning: isNowRunning);
            })
            .toList(growable: false);
      } else if (silent && prevById.isNotEmpty) {
        _apps = freshApps
            .map((app) {
              final prev = prevById[app.appId];
              if (prev == null) return app;
              return app.copyWith(
                playniteId: prev.playniteId,
                playtimeMinutes: prev.playtimeMinutes,
                lastPlayed: prev.lastPlayed,
                description: prev.description,
                tags: prev.tags,
                metadataGenres: prev.metadataGenres,
                pluginName: prev.pluginName,
                steamVideoUrl: prev.steamVideoUrl,
                steamVideoThumb: prev.steamVideoThumb,
                rawgClipUrl: prev.rawgClipUrl,
              );
            })
            .toList(growable: false);
      } else {
        _apps = freshApps;
      }
      if (_apps.isEmpty) {
        if (silent && prevById.isNotEmpty) {
          _apps = prevById.values.toList(growable: false);
          _silentRefreshInProgress = false;
          return;
        }
        _error = 'No apps returned — server may not be paired or HTTPS failed.';
      } else {
        _error = null;
      }

      if (_cfgUsername == null && computer.uuid.isNotEmpty) {
        await loadStoredCfgCredentials(computer.uuid);
      }

      if (!silent) {
        _apps = await MetadataDatabase.mergeInto(_apps);
      }

      _applyUserOverrides();

      _isLoading = false;
      _silentRefreshInProgress = false;
      if (!_disposed) notifyListeners();

      if (!_enrichedOnce) {
        _enrichGeneration++;
        final myGeneration = _enrichGeneration;
        _isEnriching = true;
        _enrichedOnce = true;
        unawaited(_runEnrichmentBackground(computer, myGeneration));
      }
    } catch (e) {
      if (!silent) {
        _error = 'Failed to load apps: $e';
      }
      _isLoading = false;
      _isEnriching = false;
      _silentRefreshInProgress = false;
      if (!_disposed) notifyListeners();

      if (!silent && !_disposed) {
        Future.delayed(const Duration(seconds: 2), () {
          if (!_disposed && _apps.isEmpty && _currentComputer != null) {
            loadApps(_currentComputer!);
          }
        });
      }
    }
  }

  Future<void> _runEnrichmentBackground(
    ComputerDetails computer,
    int generation,
  ) async {
    await Future.delayed(const Duration(seconds: 3));
    if (_disposed || _enrichGeneration != generation) return;

    final topIds = await SessionHistoryService.topPlayedAppIds(limit: 20);
    if (topIds.isNotEmpty && _apps.isNotEmpty) {
      final idSet = topIds.toSet();
      final priority = _apps.where((a) => idSet.contains(a.appId)).toList();
      final rest = _apps.where((a) => !idSet.contains(a.appId)).toList();

      _apps = [...priority, ...rest];
    }

    if (_cfgUsername != null && _cfgUsername!.isNotEmpty) {
      try {
        await _enrichWithPlaynite(computer);
      } catch (_) {}
    }

    await Future.delayed(const Duration(seconds: 1));

    if (!_disposed &&
        _enrichGeneration == generation &&
        _plugins.isEnabled('metadata')) {
      try {
        final apiKey = await _plugins.getApiKey('metadata');
        if (apiKey != null && apiKey.isNotEmpty) {
          unawaited(
            NotificationService.showEnrichment(
              'Obteniendo metadata de juegos…',
            ),
          );
          final preRawg = _apps;
          await _enrichWithRawg(apiKey);
          unawaited(MetadataDatabase.saveAll(_apps));
          if (!_disposed &&
              _enrichGeneration == generation &&
              !_appsContentEqual(preRawg, _apps)) {
            notifyListeners();
          }
        }
      } catch (_) {}
    }

    await Future.delayed(const Duration(seconds: 1));

    if (!_disposed && _enrichGeneration == generation) {
      try {
        unawaited(
          NotificationService.showEnrichment('Obteniendo datos de Steam…'),
        );
        final preSteam = _apps;
        await _enrichWithSteamStore();
        unawaited(MetadataDatabase.saveAll(_apps));
        final withVideo = _apps
            .where(
              (a) => a.steamVideoUrl != null && a.steamVideoUrl!.isNotEmpty,
            )
            .length;
        debugPrint(
          '[JUJO][enrich] Steam done — ${_apps.length} apps, $withVideo with video URL',
        );
        if (!_disposed &&
            _enrichGeneration == generation &&
            !_appsContentEqual(preSteam, _apps)) {
          notifyListeners();
        }
      } catch (e) {
        debugPrint('[JUJO][enrich] Steam enrichment error: $e');
      }
    }
    if (!_disposed && _enrichGeneration == generation) {
      _applyUserOverrides();
      _isEnriching = false;
      unawaited(NotificationService.dismissEnrichment());
      notifyListeners();
    }
  }

  Future<void> _enrichWithPlaynite(ComputerDetails computer) async {
    final username = _cfgUsername;
    final password = _cfgPassword;
    if (username == null || password == null || username.isEmpty) return;

    final address = computer.activeAddress.isNotEmpty
        ? computer.activeAddress
        : computer.localAddress;

    final httpPort = computer.externalPort > 0
        ? computer.externalPort
        : NvHttpClient.defaultHttpPort;
    final cfgPort = httpPort + 1;

    try {
      final playniteGames = await _cfgClient
          .getPlayniteGames(address, username, password, port: cfgPort)
          .timeout(const Duration(seconds: 10), onTimeout: () => const []);
      final playniteCategories = await _cfgClient
          .getPlayniteCategories(address, username, password, port: cfgPort)
          .timeout(const Duration(seconds: 10), onTimeout: () => const []);

      if (playniteGames.isEmpty && playniteCategories.isEmpty) {
        _cfgAuthRequired = true;
        _playniteActive = false;
        return;
      }

      _cfgAuthRequired = false;
      _playniteActive = true;
      _playniteCategories = playniteCategories;

      final byName = <String, PlayniteGame>{};
      for (final g in playniteGames) {
        byName[_norm(g.name)] = g;
      }

      _apps = _apps
          .map((app) {
            final pg = byName[_norm(app.appName)];
            if (pg == null) return app;
            return app.copyWith(
              playniteId: pg.id,
              pluginName: pg.pluginName,

              tags: pg.categories,
            );
          })
          .toList(growable: false);
    } catch (e) {}
  }

  static String _norm(String s) => s.toLowerCase().trim();

  static const int _kMaxConcurrent = 2;

  Future<void> _enrichWithRawg(String apiKey) async {
    final targets = _apps
        .where((a) => a.description == null || a.description!.isEmpty)
        .toList();
    if (targets.isEmpty) return;

    final semaphore = _Semaphore(_kMaxConcurrent);
    final results = await Future.wait(
      targets.map((app) => semaphore.run(() => _fetchRawg(app, apiKey))),
    );

    _apps = _apps
        .map((app) {
          final idx = targets.indexWhere((t) => t.appId == app.appId);
          if (idx < 0) return app;
          final rawg = results[idx];
          if (rawg == null) return app;
          return app.copyWith(
            description: rawg.description.isNotEmpty ? rawg.description : null,
            metadataGenres: rawg.genres,
            rawgClipUrl: rawg.clipUrl,
          );
        })
        .toList(growable: false);
  }

  Future<_RawgResult?> _fetchRawg(NvApp app, String apiKey) async {
    final detail = await _rawgClient.lookupGame(app.appName, apiKey);
    if (detail == null) return null;
    return _RawgResult(
      appId: app.appId,
      rawgId: detail.id,
      description: detail.descriptionRaw ?? '',
      genres: detail.genres,
      clipUrl: detail.clipUrl,
    );
  }

  Future<void> _enrichWithSteamStore() async {
    final targets = _apps.where((a) {
      final needsVideo = a.steamVideoUrl == null || a.steamVideoUrl!.isEmpty;
      final needsDesc = a.description == null || a.description!.isEmpty;
      return needsVideo || needsDesc;
    }).toList();
    if (targets.isEmpty) return;

    final resolvedIds = <int, int?>{};
    final nameLookupSemaphore = _Semaphore(_kMaxConcurrent);
    final needsNameLookup = targets.where((a) => a.steamAppId == null).toList();
    debugPrint(
      '[JUJO][enrich] Steam Phase 1: ${targets.length} targets, '
      '${needsNameLookup.length} need name lookup',
    );
    if (needsNameLookup.isNotEmpty) {
      final ids = await Future.wait(
        needsNameLookup.map(
          (app) => nameLookupSemaphore.run(
            () => _steamClient.searchAppId(app.appName),
          ),
        ),
      );
      for (var i = 0; i < needsNameLookup.length; i++) {
        resolvedIds[needsNameLookup[i].appId] = ids[i];
        debugPrint(
          '[JUJO][enrich]   "${needsNameLookup[i].appName}" → steamId=${ids[i]}',
        );
      }
    }

    final semaphore = _Semaphore(_kMaxConcurrent);
    final validTargets = <NvApp>[];
    final futures = <Future<SteamStoreDetails>>[];
    for (final app in targets) {
      final steamId = app.steamAppId ?? resolvedIds[app.appId];
      if (steamId == null) continue;
      validTargets.add(app);
      futures.add(semaphore.run(() => _steamClient.getStoreData(steamId)));
    }
    debugPrint(
      '[JUJO][enrich] Steam Phase 2: ${validTargets.length} apps with Steam ID',
    );
    if (validTargets.isEmpty) return;
    final results = await Future.wait(futures);

    _apps = _apps
        .map((app) {
          final idx = validTargets.indexWhere((t) => t.appId == app.appId);
          if (idx < 0) return app;
          final store = results[idx];

          final bestMovie = store.movies.isNotEmpty ? store.movies.first : null;
          final newVideoUrl =
              (app.steamVideoUrl == null || app.steamVideoUrl!.isEmpty)
              ? bestMovie?.bestUrl
              : null;
          if (newVideoUrl != null) {
            debugPrint('[JUJO][enrich]   "${app.appName}" video=$newVideoUrl');
          } else if (bestMovie == null) {
            debugPrint(
              '[JUJO][enrich]   "${app.appName}" no trailers on Steam',
            );
          }
          return app.copyWith(
            steamVideoUrl: newVideoUrl,
            steamVideoThumb:
                (app.steamVideoThumb == null || app.steamVideoThumb!.isEmpty)
                ? bestMovie?.thumbnail
                : null,
            description:
                (app.description == null || app.description!.isEmpty) &&
                    store.description != null &&
                    store.description!.isNotEmpty
                ? store.description
                : null,
            metadataGenres:
                app.metadataGenres.isEmpty && store.genres.isNotEmpty
                ? store.genres
                : null,
          );
        })
        .toList(growable: false);
  }

  Future<void> triggerMetadataEnrichment() async {
    if (_apps.isEmpty || _currentComputer == null) return;
    _enrichGeneration++;
    final myGeneration = _enrichGeneration;
    _isEnriching = true;
    if (!_disposed) notifyListeners();

    if (_plugins.isEnabled('metadata')) {
      try {
        final apiKey = await _plugins.getApiKey('metadata');
        if (apiKey != null && apiKey.isNotEmpty) {
          unawaited(
            NotificationService.showEnrichment(
              'Actualizando metadata de juegos…',
            ),
          );
          final preRawg = _apps;
          await _enrichWithRawg(apiKey);
          unawaited(MetadataDatabase.saveAll(_apps));
          if (!_disposed &&
              _enrichGeneration == myGeneration &&
              !_appsContentEqual(preRawg, _apps)) {
            notifyListeners();
          }
        }
      } catch (_) {}
    }

    if (!_disposed && _enrichGeneration == myGeneration) {
      try {
        unawaited(
          NotificationService.showEnrichment('Obteniendo datos de Steam…'),
        );
        final preSteam = _apps;
        await _enrichWithSteamStore();
        unawaited(MetadataDatabase.saveAll(_apps));
        if (!_disposed &&
            _enrichGeneration == myGeneration &&
            !_appsContentEqual(preSteam, _apps)) {
          notifyListeners();
        }
      } catch (_) {}
    }
    if (!_disposed && _enrichGeneration == myGeneration) {
      _isEnriching = false;
      unawaited(NotificationService.dismissEnrichment());
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_currentComputer != null) {
      await loadApps(_currentComputer!, silent: true);
    }
  }

  Future<LaunchResult> launchApp(
    NvApp app, {
    StreamConfiguration? streamConfig,
  }) async {
    if (_currentComputer == null) {
      return LaunchResult.fail('No computer selected');
    }

    final address = _currentComputer!.activeAddress.isNotEmpty
        ? _currentComputer!.activeAddress
        : _currentComputer!.localAddress;

    final httpsPort = _currentComputer!.httpsPort > 0
        ? _currentComputer!.httpsPort
        : NvHttpClient.defaultHttpsPort;

    NvApp? runningApp;
    for (final a in _apps) {
      if (a.isRunning) {
        runningApp = a;
        break;
      }
    }

    final audioStr = streamConfig != null
        ? switch (streamConfig.audioConfig) {
            AudioConfig.surround51 => '6',
            AudioConfig.surround71 => '8',
            _ => '1',
          }
        : '1';
    final hostPresetParams = streamConfig != null
        ? buildHostPresetLaunchParams(streamConfig)
        : const <String, String>{};

    if (runningApp != null) {
      if (runningApp.appId == app.appId) {
        return _httpClient.resumeApp(
          address,
          app.appId,
          port: httpsPort,
          width: streamConfig?.width ?? 1920,
          height: streamConfig?.height ?? 1080,
          fps: streamConfig?.fps ?? 60,
          bitrate: streamConfig?.bitrate ?? 20000,
          extraLaunchParams: hostPresetParams,
        );
      } else {
        return LaunchResult.fail(
          'There is already an app running (${runningApp.appName}). Quit it before launching another one.',
        );
      }
    }

    return _httpClient.launchApp(
      address,
      app.appId,
      port: httpsPort,
      width: streamConfig?.width ?? 1920,
      height: streamConfig?.height ?? 1080,
      fps: streamConfig?.fps ?? 60,
      bitrate: streamConfig?.bitrate ?? 20000,
      sops: streamConfig?.enableSops ?? true,
      enableHdr: streamConfig?.enableHdr ?? false,
      localAudio: streamConfig?.playLocalAudio ?? false,
      surroundAudioInfo: audioStr,
      extraLaunchParams: hostPresetParams,
    );
  }

  Future<bool> quitApp() async {
    if (_currentComputer == null) return false;

    final address = _currentComputer!.activeAddress.isNotEmpty
        ? _currentComputer!.activeAddress
        : _currentComputer!.localAddress;

    final httpsPort = _currentComputer!.httpsPort > 0
        ? _currentComputer!.httpsPort
        : NvHttpClient.defaultHttpsPort;

    debugPrint('[JUJO][quit] Sending /cancel to $address:$httpsPort');
    final result = await _httpClient.quitApp(address, port: httpsPort);
    debugPrint('[JUJO][quit] /cancel result=$result');

    _apps = _apps
        .map((a) => a.isRunning ? a.copyWith(isRunning: false) : a)
        .toList(growable: false);

    _currentComputer?.runningGameId = 0;
    if (!_disposed) notifyListeners();

    await Future.delayed(const Duration(milliseconds: 500));
    await refresh();
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    _httpClient.dispose();
    super.dispose();
  }
}

class _Semaphore {
  _Semaphore(int maxCount) : _available = maxCount;
  int _available;
  final _queue = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() task) async {
    if (_available > 0) {
      _available--;
    } else {
      final c = Completer<void>();
      _queue.add(c);
      await c.future;
    }
    try {
      return await task();
    } finally {
      if (_queue.isNotEmpty) {
        _queue.removeAt(0).complete();
      } else {
        _available++;
      }
    }
  }
}

class _RawgResult {
  final int appId;
  final int rawgId;
  final String description;
  final List<String> genres;
  final String? clipUrl;

  const _RawgResult({
    required this.appId,
    required this.rawgId,
    required this.description,
    required this.genres,
    this.clipUrl,
  });
}
