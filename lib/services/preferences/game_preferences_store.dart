import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/stream_configuration.dart';

class GamePreferencesProfile {
  final int appId;
  final int? bitrate;
  final int? fps;
  final VideoCodec? videoCodec;
  final bool? enableHdr;
  final bool? showOnscreenControls;
  final bool? ultraLowLatency;
  final bool? enablePerfOverlay;
  final int? lastSessionAtMs;
  final int launchCount;

  const GamePreferencesProfile({
    required this.appId,
    this.bitrate,
    this.fps,
    this.videoCodec,
    this.enableHdr,
    this.showOnscreenControls,
    this.ultraLowLatency,
    this.enablePerfOverlay,
    this.lastSessionAtMs,
    this.launchCount = 0,
  });

  bool get hasOverrides =>
      bitrate != null ||
      fps != null ||
      videoCodec != null ||
      enableHdr != null ||
      showOnscreenControls != null ||
      ultraLowLatency != null ||
      enablePerfOverlay != null;

  DateTime? get lastSessionAt =>
      lastSessionAtMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lastSessionAtMs!);

  StreamConfiguration resolve(StreamConfiguration base) {
    return base.copyWith(
      bitrate: bitrate ?? base.bitrate,
      fps: fps ?? base.fps,
      videoCodec: videoCodec ?? base.videoCodec,
      enableHdr: enableHdr ?? base.enableHdr,
      showOnscreenControls: showOnscreenControls ?? base.showOnscreenControls,
      ultraLowLatency: ultraLowLatency ?? base.ultraLowLatency,
      enablePerfOverlay: enablePerfOverlay ?? base.enablePerfOverlay,
    );
  }

  GamePreferencesProfile copyWith({
    int? appId,
    int? bitrate,
    int? fps,
    VideoCodec? videoCodec,
    bool? enableHdr,
    bool? showOnscreenControls,
    bool? ultraLowLatency,
    bool? enablePerfOverlay,
    int? lastSessionAtMs,
    int? launchCount,
    bool clearOverrides = false,
  }) {
    return GamePreferencesProfile(
      appId: appId ?? this.appId,
      bitrate: clearOverrides ? null : bitrate ?? this.bitrate,
      fps: clearOverrides ? null : fps ?? this.fps,
      videoCodec: clearOverrides ? null : videoCodec ?? this.videoCodec,
      enableHdr: clearOverrides ? null : enableHdr ?? this.enableHdr,
      showOnscreenControls:
          clearOverrides ? null : showOnscreenControls ?? this.showOnscreenControls,
      ultraLowLatency:
          clearOverrides ? null : ultraLowLatency ?? this.ultraLowLatency,
      enablePerfOverlay:
          clearOverrides ? null : enablePerfOverlay ?? this.enablePerfOverlay,
      lastSessionAtMs: lastSessionAtMs ?? this.lastSessionAtMs,
      launchCount: launchCount ?? this.launchCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'appId': appId,
        'bitrate': bitrate,
        'fps': fps,
        'videoCodec': videoCodec?.index,
        'enableHdr': enableHdr,
        'showOnscreenControls': showOnscreenControls,
        'ultraLowLatency': ultraLowLatency,
        'enablePerfOverlay': enablePerfOverlay,
        'lastSessionAtMs': lastSessionAtMs,
        'launchCount': launchCount,
      };

  factory GamePreferencesProfile.fromJson(Map<String, dynamic> json) {
    return GamePreferencesProfile(
      appId: json['appId'] ?? 0,
      bitrate: json['bitrate'],
      fps: json['fps'],
      videoCodec: json['videoCodec'] == null
          ? null
          : VideoCodec.values[json['videoCodec'] as int],
      enableHdr: json['enableHdr'],
      showOnscreenControls: json['showOnscreenControls'],
      ultraLowLatency: json['ultraLowLatency'],
      enablePerfOverlay: json['enablePerfOverlay'],
      lastSessionAtMs: json['lastSessionAtMs'],
      launchCount: json['launchCount'] ?? 0,
    );
  }
}

class GamePreferencesStore {
  const GamePreferencesStore();

  String _keyFor(String hostId, int appId) => 'game_profile_${hostId}_$appId';

  Future<GamePreferencesProfile> loadProfile(String hostId, int appId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(hostId, appId));
    if (raw == null || raw.isEmpty) {
      return GamePreferencesProfile(appId: appId);
    }
    return GamePreferencesProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<Map<int, GamePreferencesProfile>> loadProfiles(
    String hostId,
    List<int> appIds,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final result = <int, GamePreferencesProfile>{};
    for (final appId in appIds) {
      final raw = prefs.getString(_keyFor(hostId, appId));
      if (raw != null && raw.isNotEmpty) {
        result[appId] =
            GamePreferencesProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    }
    return result;
  }

  Future<void> saveProfile(String hostId, GamePreferencesProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(hostId, profile.appId), jsonEncode(profile.toJson()));
  }

  Future<GamePreferencesProfile> recordLaunch(String hostId, int appId) async {
    final current = await loadProfile(hostId, appId);
    final updated = current.copyWith(
      lastSessionAtMs: DateTime.now().millisecondsSinceEpoch,
      launchCount: current.launchCount + 1,
    );
    await saveProfile(hostId, updated);
    return updated;
  }

  Future<GamePreferencesProfile> clearOverrides(String hostId, int appId) async {
    final current = await loadProfile(hostId, appId);
    final updated = current.copyWith(clearOverrides: true);
    await saveProfile(hostId, updated);
    return updated;
  }
}
