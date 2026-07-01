class NvApp {
  final int appId;
  final String appName;
  final bool isRunning;
  final bool isHdrSupported;
  final String? posterUrl;

  final String? playniteId;

  final int playtimeMinutes;

  final String? lastPlayed;

  final String? description;

  final List<String> tags;

  final List<String> metadataGenres;

  final String? pluginName;

  final String? serverUuid;

  final String? steamVideoUrl;
  final String? steamVideoThumb;
  final String? rawgClipUrl;

  /// Crisp 16:9 background/hero served by the host (/appasset AssetType=3).
  /// Null when the host advertises no hero — callers fall back to [posterUrl].
  final String? heroImageUrl;

  /// Extra gallery images (screenshots/artwork) served by the host
  /// (/appasset AssetType=4&AssetIdx=i).
  final List<String> screenshotUrls;

  /// RAWG landscape background (metadata plugin). Fallback hero when the host
  /// doesn't advertise one.
  final String? rawgBackgroundUrl;

  NvApp({
    required this.appId,
    required this.appName,
    this.isRunning = false,
    this.isHdrSupported = false,
    this.posterUrl,

    this.playniteId,
    this.playtimeMinutes = 0,
    this.lastPlayed,
    this.description,
    this.tags = const [],
    this.metadataGenres = const [],
    this.pluginName,
    this.serverUuid,
    this.steamVideoUrl,
    this.steamVideoThumb,
    this.rawgClipUrl,
    this.heroImageUrl,
    this.screenshotUrls = const [],
    this.rawgBackgroundUrl,
  });

  /// Stable, server-independent disk-cache key for this app's art. Host
  /// /appasset URLs embed address:port, so caching by URL duplicates the same
  /// game's art per server; the normalized app name is the only cross-server
  /// identity (same criterion as Playnite matching in AppListProvider).
  String artCacheKey(String kind, [int idx = 0]) {
    final norm = appName.trim().toLowerCase();
    return 'nvart_${norm}_${kind}_$idx';
  }

  /// Best large background: host hero → RAWG background → poster.
  String? get backgroundUrl => heroImageUrl ?? rawgBackgroundUrl ?? posterUrl;

  /// Cache key matching whichever source [backgroundUrl] resolved to.
  String get backgroundCacheKey => heroImageUrl != null
      ? artCacheKey('hero')
      : rawgBackgroundUrl != null
      ? artCacheKey('rawgbg')
      : artCacheKey('poster');

  NvApp copyWith({
    int? appId,
    String? appName,
    bool? isRunning,
    bool? isHdrSupported,
    String? posterUrl,
    String? playniteId,
    int? playtimeMinutes,
    String? lastPlayed,
    String? description,
    List<String>? tags,
    List<String>? metadataGenres,
    String? pluginName,
    String? serverUuid,
    String? steamVideoUrl,
    String? steamVideoThumb,
    String? rawgClipUrl,
    String? heroImageUrl,
    List<String>? screenshotUrls,
    String? rawgBackgroundUrl,
  }) {
    return NvApp(
      appId: appId ?? this.appId,
      appName: appName ?? this.appName,
      isRunning: isRunning ?? this.isRunning,
      isHdrSupported: isHdrSupported ?? this.isHdrSupported,
      posterUrl: posterUrl ?? this.posterUrl,
      playniteId: playniteId ?? this.playniteId,
      playtimeMinutes: playtimeMinutes ?? this.playtimeMinutes,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      metadataGenres: metadataGenres ?? this.metadataGenres,
      pluginName: pluginName ?? this.pluginName,
      serverUuid: serverUuid ?? this.serverUuid,
      steamVideoUrl: steamVideoUrl ?? this.steamVideoUrl,
      steamVideoThumb: steamVideoThumb ?? this.steamVideoThumb,
      rawgClipUrl: rawgClipUrl ?? this.rawgClipUrl,
      heroImageUrl: heroImageUrl ?? this.heroImageUrl,
      screenshotUrls: screenshotUrls ?? this.screenshotUrls,
      rawgBackgroundUrl: rawgBackgroundUrl ?? this.rawgBackgroundUrl,
    );
  }

  static final _steamIdRegex = RegExp(r'/steam/apps/(\d+)/');
  int? _cachedSteamAppId;
  bool _steamAppIdCached = false;

  int? get steamAppId {
    if (_steamAppIdCached) return _cachedSteamAppId;
    _steamAppIdCached = true;
    if (posterUrl == null) return null;
    final match = _steamIdRegex.firstMatch(posterUrl!);
    _cachedSteamAppId = match != null ? int.tryParse(match.group(1)!) : null;
    return _cachedSteamAppId;
  }

  String get playtimeLabel {
    if (playtimeMinutes <= 0) return '';
    if (playtimeMinutes < 60) return '${playtimeMinutes}m';
    final h = playtimeMinutes ~/ 60;
    final m = playtimeMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  Map<String, dynamic> toJson() => {
        'appId': appId,
        'appName': appName,
        'isRunning': isRunning,
        'isHdrSupported': isHdrSupported,
        'posterUrl': posterUrl,
        if (playniteId != null) 'playniteId': playniteId,
        if (playtimeMinutes > 0) 'playtimeMinutes': playtimeMinutes,
        if (lastPlayed != null) 'lastPlayed': lastPlayed,
        if (description != null) 'description': description,
        if (tags.isNotEmpty) 'tags': tags,
        if (metadataGenres.isNotEmpty) 'metadataGenres': metadataGenres,
        if (pluginName != null) 'pluginName': pluginName,
        if (serverUuid != null) 'serverUuid': serverUuid,
        if (steamVideoUrl != null) 'steamVideoUrl': steamVideoUrl,
        if (steamVideoThumb != null) 'steamVideoThumb': steamVideoThumb,
        if (rawgClipUrl != null) 'rawgClipUrl': rawgClipUrl,
        if (heroImageUrl != null) 'heroImageUrl': heroImageUrl,
        if (screenshotUrls.isNotEmpty) 'screenshotUrls': screenshotUrls,
        if (rawgBackgroundUrl != null) 'rawgBackgroundUrl': rawgBackgroundUrl,
      };

  factory NvApp.fromJson(Map<String, dynamic> json) {
    return NvApp(
      appId: json['appId'] ?? 0,
      appName: json['appName'] ?? '',
      isRunning: json['isRunning'] ?? false,
      isHdrSupported: json['isHdrSupported'] ?? false,
      posterUrl: json['posterUrl'],
      playniteId: json['playniteId'],
      playtimeMinutes: json['playtimeMinutes'] ?? 0,
      lastPlayed: json['lastPlayed'],
      description: json['description'],
      tags: (json['tags'] as List?)?.cast<String>() ?? const [],
        metadataGenres:
          (json['metadataGenres'] as List?)?.cast<String>() ?? const [],
      pluginName: json['pluginName'],
      serverUuid: json['serverUuid'],
      steamVideoUrl: json['steamVideoUrl'],
      steamVideoThumb: json['steamVideoThumb'],
      rawgClipUrl: json['rawgClipUrl'],
      heroImageUrl: json['heroImageUrl'],
      screenshotUrls:
          (json['screenshotUrls'] as List?)?.cast<String>() ?? const [],
      rawgBackgroundUrl: json['rawgBackgroundUrl'],
    );
  }

  bool contentEquals(NvApp other) {
    if (appId != other.appId) return false;
    if (appName != other.appName) return false;
    if (isRunning != other.isRunning) return false;
    if (isHdrSupported != other.isHdrSupported) return false;
    if (posterUrl != other.posterUrl) return false;
    if (playniteId != other.playniteId) return false;
    if (playtimeMinutes != other.playtimeMinutes) return false;
    if (lastPlayed != other.lastPlayed) return false;
    if (description != other.description) return false;
    if (pluginName != other.pluginName) return false;
    if (serverUuid != other.serverUuid) return false;
    if (steamVideoUrl != other.steamVideoUrl) return false;
    if (steamVideoThumb != other.steamVideoThumb) return false;
    if (rawgClipUrl != other.rawgClipUrl) return false;
    if (rawgBackgroundUrl != other.rawgBackgroundUrl) return false;
    if (tags.length != other.tags.length) return false;
    if (metadataGenres.length != other.metadataGenres.length) return false;
    for (var i = 0; i < tags.length; i++) {
      if (tags[i] != other.tags[i]) return false;
    }
    for (var i = 0; i < metadataGenres.length; i++) {
      if (metadataGenres[i] != other.metadataGenres[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'NvApp($appId: $appName)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NvApp &&
          runtimeType == other.runtimeType &&
          appId == other.appId;

  @override
  int get hashCode => appId.hashCode;
}
