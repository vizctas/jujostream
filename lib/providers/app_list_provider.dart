import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/nv_app.dart';
import '../models/computer_details.dart';
import '../models/stream_configuration.dart';
import '../services/http_api/nv_http_client.dart';
import '../services/http_api/vibepollo_cfg_client.dart';
import '../services/stream/host_preset_profiles.dart';
import '../services/metadata/game_art_policy.dart';
import '../services/metadata/rawg_client.dart';
import '../services/metadata/steam_video_client.dart';
import '../services/database/app_override_service.dart';
import '../services/database/metadata_database.dart';
import '../services/database/session_history_service.dart';
import '../services/notifications/notification_service.dart';
import '../services/sync/cloud_sync_service.dart';
import 'plugins_provider.dart';

export '../services/http_api/nv_http_client.dart' show LaunchResult;
export '../services/http_api/vibepollo_cfg_client.dart'
    show PlayniteCategory, PlayniteStatus;

typedef ServerIdentityRecovery =
    Future<bool> Function(ComputerDetails computer);

@visibleForTesting
NvApp normalizeHostApp(NvApp app, {required int runningId}) {
  final cleanName = app.appName
      .replaceAll('\u200B', '')
      .replaceAll('\u200C', '');
  return app.copyWith(
    appName: cleanName,
    isRunning: app.isRunning || (runningId > 0 && app.appId == runningId),
  );
}

class AppListProvider extends ChangeNotifier {
  final NvHttpClient _httpClient;
  final ServerIdentityRecovery _recoverServerIdentity;
  final VibepolloCfgClient _cfgClient = VibepolloCfgClient();
  final RawgClient _rawgClient = RawgClient();
  final SteamVideoClient _steamClient = SteamVideoClient();
  final PluginsProvider _plugins;

  AppListProvider(
    this._plugins, {
    NvHttpClient? httpClient,
    ServerIdentityRecovery? recoverServerIdentity,
  }) : _httpClient = httpClient ?? NvHttpClient(),
       _recoverServerIdentity =
           recoverServerIdentity ??
           CloudSyncService
               .instance
               .recoverCloudPairingAfterServerIdentityChange;

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
  bool _cloudRepairAttempted = false;

  /// True when the last failed load was the server refusing this device's
  /// certificate, rather than a network problem. Drives the "Re-pair" action —
  /// "Retry" alone can never fix this.
  bool lastFailureWasCertRejected = false;
  bool _forceRawgRefreshPending = false;

  final Map<int, NvApp> _fullAppCache = {};

  String? _cfgUsername;
  String? _cfgPassword;

  List<NvApp>? _appsViewSource;
  UnmodifiableListView<NvApp>? _appsView;

  /// Read-only view of the library.
  ///
  /// This used to be `List.unmodifiable(_apps)`, which COPIES the whole list on
  /// every access — and the UI reads it several times per build, on a screen
  /// that rebuilds often. It also handed out a new object each time, so nothing
  /// downstream could cache on its identity. `_apps` is always reassigned,
  /// never mutated in place, so an identity check is enough to know when to
  /// rebuild the view.
  List<NvApp> get apps {
    if (!identical(_appsViewSource, _apps)) {
      _appsViewSource = _apps;
      _appsView = UnmodifiableListView<NvApp>(_apps);
    }
    return _appsView!;
  }

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

  Future<void> _recoverRotatedServerIdentity(ComputerDetails computer) async {
    final recovered = await _recoverServerIdentity(computer);
    if (_disposed || _currentComputer?.uuid != computer.uuid) return;
    if (!recovered) {
      notifyListeners();
      return;
    }

    // The failed load may still be merging its empty metadata result. Wait for
    // that load to settle so it cannot overwrite the successful retry.
    while (_isLoading &&
        !_disposed &&
        _currentComputer?.uuid == computer.uuid) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (_disposed || _currentComputer?.uuid != computer.uuid) return;

    _error = null;
    await loadApps(computer);
  }

  Future<void> loadApps(ComputerDetails computer, {bool silent = false}) async {
    if (silent && _silentRefreshInProgress) return;
    final isNewServer = _currentComputer?.uuid != computer.uuid;
    _currentComputer = computer;
    _cfgClient.expectedServerCert = computer.serverCert;
    if (!silent) {
      _isLoading = true;
      _isEnriching = false;
      _enrichedOnce = false;
      _error = null;
      _apps = [];
      if (isNewServer) {
        _fullAppCache.clear();
        _cloudRepairAttempted = false;
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
          .getAppList(
            address,
            httpsPort: httpsPort,
            expectedServerCert: computer.serverCert,
          )
          .timeout(const Duration(seconds: 12), onTimeout: () => const []);

      _httpClient
          .getServerInfoHttps(
            address,
            httpsPort: httpsPort,
            httpPort: computer.externalPort > 0
                ? computer.externalPort
                : NvHttpClient.defaultHttpPort,
            expectedServerCert: computer.serverCert,
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
          .map((app) => normalizeHostApp(app, runningId: runningId))
          .toList(growable: false);

      // A normal /applist response is authoritative. Keep historical entries
      // only for the known busy-session response containing the running app.
      final isBusySessionList =
          freshApps.length == 1 &&
          (runningId > 0 || freshApps.single.isRunning);
      if (freshApps.isNotEmpty && !isBusySessionList) {
        final freshIds = freshApps.map((app) => app.appId).toSet();
        _fullAppCache.removeWhere((appId, _) => !freshIds.contains(appId));
      }

      for (final app in freshApps) {
        final previous = _fullAppCache[app.appId];
        _fullAppCache[app.appId] = previous == null
            ? app
            : app.copyWith(
                posterUrl: previous.posterUrl,
                playniteId: previous.playniteId,
                playtimeMinutes: previous.playtimeMinutes,
                lastPlayed: previous.lastPlayed,
                description: previous.description,
                tags: previous.tags,
                metadataGenres: previous.metadataGenres,
                pluginName: previous.pluginName,
                steamVideoUrl: previous.steamVideoUrl,
                steamVideoThumb: previous.steamVideoThumb,
                steamBackgroundUrl: previous.steamBackgroundUrl,
                rawgClipUrl: previous.rawgClipUrl,
                rawgBackgroundUrl: previous.rawgBackgroundUrl,
              );
      }
      // persist so a crash/restart doesn't lose the full list
      unawaited(_persistAppCache(computer.uuid));
      final useCache =
          isBusySessionList &&
          _fullAppCache.length > freshApps.length &&
          _fullAppCache.isNotEmpty;

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
                posterUrl: prev.posterUrl,
                playniteId: prev.playniteId,
                playtimeMinutes: prev.playtimeMinutes,
                lastPlayed: prev.lastPlayed,
                description: prev.description,
                tags: prev.tags,
                metadataGenres: prev.metadataGenres,
                pluginName: prev.pluginName,
                steamVideoUrl: prev.steamVideoUrl,
                steamVideoThumb: prev.steamVideoThumb,
                steamBackgroundUrl: prev.steamBackgroundUrl,
                rawgClipUrl: prev.rawgClipUrl,
                rawgBackgroundUrl: prev.rawgBackgroundUrl,
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
        lastFailureWasCertRejected =
            _httpClient.lastAppListFailure ==
                AppListFailure.serverIdentityRejected ||
            _httpClient.lastAppListCertRejected;

        if (_httpClient.lastAppListFailure ==
            AppListFailure.serverIdentityRejected) {
          _error =
              'Server identity changed. Sign in to JUJO.Cloud to verify it, '
              'or pair this device again locally.';
          if (!silent && !_cloudRepairAttempted) {
            _cloudRepairAttempted = true;
            unawaited(_recoverRotatedServerIdentity(computer));
          }
        } else if (!silent &&
            _httpClient.lastAppListCertRejected &&
            computer.isCloud &&
            !_cloudRepairAttempted) {
          _error =
              'Server rejected this device. Restoring secure Cloud pairing…';
          // Server rejected our cert but this server is cloud-registered:
          // the cert never landed in the server's registry (e.g. the
          // cloud-pair POST failed earlier). Re-run cloud pairing for this
          // computer once, then reload.
          _cloudRepairAttempted = true;
          unawaited(
            CloudSyncService.instance.repairCloudPairing(computer).then((_) {
              if (!_disposed && _apps.isEmpty && _currentComputer != null) {
                loadApps(_currentComputer!);
              }
            }),
          );
        } else {
          _error =
              'No apps returned — server may not be paired or HTTPS failed.';
          if (isNewServer && !silent) {
            // Sunshine/Apollo can take a few seconds to persist the pairing
            // before /applist returns apps. Retry once after a short delay.
            Future.delayed(const Duration(seconds: 2), () {
              if (!_disposed && _apps.isEmpty && _currentComputer != null) {
                loadApps(_currentComputer!);
              }
            });
          }
        }
      } else {
        _error = null;
        lastFailureWasCertRejected = false;
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
          if (_forceRawgRefreshPending) {
            _forceRawgRefreshPending = false;
            await _refreshAllRawgArtwork(apiKey, generation);
          } else {
            await _enrichWithRawg(apiKey);
          }
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
    } catch (_) {
      // Playnite metadata is optional; RAWG/Steam enrichment can continue.
    }
  }

  static String _norm(String s) => s.toLowerCase().trim();

  static const int _kMaxConcurrent = 2;

  Future<void> _enrichWithRawg(String apiKey) async {
    final targets = _apps.where((a) {
      final needsDesc = a.description == null || a.description!.isEmpty;
      final needsBg =
          a.rawgBackgroundUrl == null || a.rawgBackgroundUrl!.isEmpty;
      final needsGallery = a.screenshotUrls.isEmpty;
      return needsDesc || needsBg || needsGallery;
    }).toList();
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
          final withArtwork = GameArtPolicy.applyProviderArtwork(
            app,
            primaryBackgroundUrl: rawg.backgroundUrl,
            screenshots: rawg.screenshotUrls,
          );
          return withArtwork.copyWith(
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
    // Screenshots remain gallery-only. The provider-designated primary
    // background is the only RAWG candidate for a hero.
    final screenshots = await _rawgClient.getScreenshots(detail.id, apiKey);
    return _RawgResult(
      appId: app.appId,
      rawgId: detail.id,
      description: detail.descriptionRaw ?? '',
      genres: detail.genres,
      clipUrl: detail.clipUrl,
      backgroundUrl: detail.backgroundImage,
      screenshotUrls: screenshots,
    );
  }

  Future<void> _enrichWithSteamStore() async {
    final targets = _apps.where((a) {
      final needsVideo = a.steamVideoUrl == null || a.steamVideoUrl!.isEmpty;
      final needsDesc = a.description == null || a.description!.isEmpty;
      final needsBackground =
          a.steamBackgroundUrl == null || a.steamBackgroundUrl!.isEmpty;
      return needsVideo || needsDesc || needsBackground;
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
            steamBackgroundUrl:
                (app.steamBackgroundUrl == null ||
                    app.steamBackgroundUrl!.isEmpty)
                ? store.backgroundImageUrl
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

  Future<void> triggerRawgArtworkRefresh() async {
    _forceRawgRefreshPending = true;
    if (_apps.isEmpty || _currentComputer == null) return;

    final apiKey = await _plugins.getApiKey('metadata');
    if (apiKey == null || apiKey.isEmpty) return;

    _forceRawgRefreshPending = false;
    _enrichGeneration++;
    final myGeneration = _enrichGeneration;
    _isEnriching = true;
    if (!_disposed) notifyListeners();

    unawaited(NotificationService.showEnrichment('Actualizando arte RAWG...'));
    unawaited(_runRawgArtworkRefreshBackground(apiKey, myGeneration));
  }

  Future<void> _runRawgArtworkRefreshBackground(
    String apiKey,
    int generation,
  ) async {
    try {
      await _refreshAllRawgArtwork(apiKey, generation);
      if (!_disposed && _enrichGeneration == generation) {
        await MetadataDatabase.saveAll(_apps);
        final computer = _currentComputer;
        if (computer != null) unawaited(_persistAppCache(computer.uuid));
      }
    } finally {
      if (!_disposed && _enrichGeneration == generation) {
        _applyUserOverrides();
        _isEnriching = false;
        unawaited(NotificationService.dismissEnrichment());
        notifyListeners();
      }
    }
  }

  Future<void> _refreshAllRawgArtwork(String apiKey, int generation) async {
    final targets = List<NvApp>.from(_apps);
    if (targets.isEmpty) return;

    var changedSinceSave = false;
    for (var i = 0; i < targets.length; i++) {
      if (_disposed || _enrichGeneration != generation) return;
      final rawg = await _fetchRawg(targets[i], apiKey);
      if (rawg == null) continue;

      final updated = _applyRawgResult(targets[i], rawg);

      _replaceApp(updated);
      changedSinceSave = true;

      // Notify promptly (coalesced) so art appears as it lands, but hit the
      // disk far less often: a full sqlite saveAll plus a jsonEncode of the
      // entire cache every 4 items was 20 writes per 40-game refresh on a
      // slow eMMC. The trailing block below still saves whatever remains.
      if (!_disposed && _enrichGeneration == generation) _notifyCoalesced();
      if (i % 12 == 11) {
        await MetadataDatabase.saveAll(_apps);
        final computer = _currentComputer;
        if (computer != null) unawaited(_persistAppCache(computer.uuid));
        changedSinceSave = false;
      }
    }

    if (changedSinceSave && !_disposed && _enrichGeneration == generation) {
      await MetadataDatabase.saveAll(_apps);
      final computer = _currentComputer;
      if (computer != null) unawaited(_persistAppCache(computer.uuid));
      notifyListeners();
    }
  }

  NvApp _applyRawgResult(NvApp app, _RawgResult rawg) {
    final withArtwork = GameArtPolicy.applyProviderArtwork(
      app,
      primaryBackgroundUrl: rawg.backgroundUrl,
      screenshots: rawg.screenshotUrls,
    );
    return withArtwork.copyWith(
      description: rawg.description.isNotEmpty ? rawg.description : null,
      metadataGenres: rawg.genres,
      rawgClipUrl: rawg.clipUrl,
    );
  }

  void _replaceApp(NvApp updated) {
    _apps = _apps
        .map((app) => app.appId == updated.appId ? updated : app)
        .toList(growable: false);
    final cached = _fullAppCache[updated.appId];
    if (cached != null) {
      _fullAppCache[updated.appId] = cached.copyWith(
        posterUrl: updated.posterUrl,
        description: updated.description,
        metadataGenres: updated.metadataGenres,
        rawgClipUrl: updated.rawgClipUrl,
        steamBackgroundUrl: updated.steamBackgroundUrl,
        rawgBackgroundUrl: updated.rawgBackgroundUrl,
        screenshotUrls: updated.screenshotUrls,
      );
    }
  }

  Future<void> refresh() async {
    if (_currentComputer != null) {
      await loadApps(_currentComputer!, silent: true);
    }
  }

  Future<LaunchResult> launchApp(
    NvApp app, {
    required StreamConfiguration streamConfig,
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

    final audioStr = switch (streamConfig.audioConfig) {
      AudioConfig.surround51 => '6',
      AudioConfig.surround71 => '8',
      _ => '1',
    };
    final hostPresetParams = buildHostPresetLaunchParams(streamConfig);

    if (runningApp != null) {
      if (runningApp.appId == app.appId) {
        return _httpClient.resumeApp(
          address,
          app.appId,
          port: httpsPort,
          width: streamConfig.width,
          height: streamConfig.height,
          fps: streamConfig.fps,
          bitrate: streamConfig.bitrate,
          sops: streamConfig.enableSops,
          enableHdr: streamConfig.enableHdr,
          localAudio: streamConfig.playLocalAudio,
          aspectRatio: streamConfig.aspectRatio,
          clientMic: streamConfig.clientMic,
          videoPacingMode: streamConfig.videoPacingMode,
          videoPacingSlackMs: streamConfig.videoPacingSlackMs,
          videoMaxFrameAgeMs: streamConfig.videoMaxFrameAgeMs,
          surroundAudioInfo: audioStr,
          extraLaunchParams: hostPresetParams,
          expectedServerCert: _currentComputer!.serverCert,
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
      width: streamConfig.width,
      height: streamConfig.height,
      fps: streamConfig.fps,
      bitrate: streamConfig.bitrate,
      sops: streamConfig.enableSops,
      enableHdr: streamConfig.enableHdr,
      localAudio: streamConfig.playLocalAudio,
      aspectRatio: streamConfig.aspectRatio,
      clientMic: streamConfig.clientMic,
      videoPacingMode: streamConfig.videoPacingMode,
      videoPacingSlackMs: streamConfig.videoPacingSlackMs,
      videoMaxFrameAgeMs: streamConfig.videoMaxFrameAgeMs,
      surroundAudioInfo: audioStr,
      extraLaunchParams: hostPresetParams,
      expectedServerCert: _currentComputer!.serverCert,
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
    final result = await _httpClient.quitApp(
      address,
      port: httpsPort,
      expectedServerCert: _currentComputer!.serverCert,
    );
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

  Future<GameLaunchState> getGameLaunchState(
    String token, {
    bool retryFocus = false,
  }) async {
    final computer = _currentComputer;
    if (computer == null) {
      return GameLaunchState.transportFailure('No computer selected');
    }
    final address = computer.activeAddress.isNotEmpty
        ? computer.activeAddress
        : computer.localAddress;
    final httpsPort = computer.httpsPort > 0
        ? computer.httpsPort
        : NvHttpClient.defaultHttpsPort;
    return _httpClient.getGameLaunchState(
      address,
      token,
      port: httpsPort,
      expectedServerCert: computer.serverCert,
      retryFocus: retryFocus,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _coalescedNotifyTimer?.cancel();
    _httpClient.dispose();
    super.dispose();
  }

  Timer? _coalescedNotifyTimer;

  /// Batches rapid-fire enrichment notifications to at most ~2 per second.
  ///
  /// The artwork refresh notified every few items — dozens of full library
  /// rebuilds in the half-minute right after entering a server, which is
  /// exactly when the user is browsing. The UI only needs to see the art
  /// appear, not every individual batch land.
  void _notifyCoalesced() {
    if (_disposed) return;
    _coalescedNotifyTimer ??= Timer(const Duration(milliseconds: 500), () {
      _coalescedNotifyTimer = null;
      if (!_disposed) notifyListeners();
    });
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
  final String? backgroundUrl;
  final List<String> screenshotUrls;

  const _RawgResult({
    required this.appId,
    required this.rawgId,
    required this.description,
    required this.genres,
    this.clipUrl,
    this.backgroundUrl,
    this.screenshotUrls = const [],
  });
}
