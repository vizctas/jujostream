import 'stream_configuration.dart';

/// Per-server configuration profile that can either inherit the global
/// [StreamConfiguration] & launcher preferences (`overrideEnabled == false`)
/// or apply server-specific overrides (`overrideEnabled == true`).
class ServerSettingsProfile {
  final String hostId;
  final String serverName;
  final bool overrideEnabled;
  final StreamConfiguration streamConfig;
  final String? launcherThemeName;

  const ServerSettingsProfile({
    required this.hostId,
    this.serverName = '',
    this.overrideEnabled = false,
    this.streamConfig = const StreamConfiguration(),
    this.launcherThemeName,
  });

  ServerSettingsProfile copyWith({
    String? hostId,
    String? serverName,
    bool? overrideEnabled,
    StreamConfiguration? streamConfig,
    String? launcherThemeName,
    bool clearLauncherThemeName = false,
  }) {
    return ServerSettingsProfile(
      hostId: hostId ?? this.hostId,
      serverName: serverName ?? this.serverName,
      overrideEnabled: overrideEnabled ?? this.overrideEnabled,
      streamConfig: streamConfig ?? this.streamConfig,
      launcherThemeName: clearLauncherThemeName
          ? null
          : (launcherThemeName ?? this.launcherThemeName),
    );
  }

  Map<String, dynamic> toJson() => {
    'hostId': hostId,
    'serverName': serverName,
    'overrideEnabled': overrideEnabled,
    'streamConfig': streamConfig.toJson(),
    if (launcherThemeName != null && launcherThemeName!.isNotEmpty)
      'launcherThemeName': launcherThemeName,
  };

  factory ServerSettingsProfile.fromJson(
    Map<String, dynamic> json, {
    StreamConfiguration fallbackGlobal = const StreamConfiguration(),
  }) {
    final rawConfig = json['streamConfig'];
    StreamConfiguration parsedConfig = fallbackGlobal;
    if (rawConfig is Map<String, dynamic>) {
      try {
        parsedConfig = StreamConfiguration.fromJson(rawConfig);
      } catch (_) {
        parsedConfig = fallbackGlobal;
      }
    } else if (rawConfig is Map) {
      try {
        parsedConfig = StreamConfiguration.fromJson(
          Map<String, dynamic>.from(rawConfig),
        );
      } catch (_) {
        parsedConfig = fallbackGlobal;
      }
    }
    final rawTheme = json['launcherThemeName'];
    return ServerSettingsProfile(
      hostId: (json['hostId'] as String?) ?? '',
      serverName: (json['serverName'] as String?) ?? '',
      overrideEnabled: (json['overrideEnabled'] as bool?) ?? false,
      streamConfig: parsedConfig,
      launcherThemeName: rawTheme is String && rawTheme.isNotEmpty
          ? rawTheme
          : null,
    );
  }

  /// Concise badges describing how this server's override differs from [global].
  List<String> diffBadges(
    StreamConfiguration global, {
    String? globalLauncherThemeName,
    bool isEs = false,
    bool hasCustomLauncherPrefs = false,
  }) {
    if (!overrideEnabled) return const [];
    final badges = <String>[];
    final s = streamConfig;

    if (launcherThemeName != null &&
        launcherThemeName!.isNotEmpty &&
        launcherThemeName != globalLauncherThemeName) {
      badges.add(
        '${isEs ? "Launcher" : "Launcher"}: ${_formatLauncherName(launcherThemeName!)}',
      );
    } else if (hasCustomLauncherPrefs) {
      badges.add(isEs ? 'Launcher personalizado' : 'Custom Launcher');
    }

    if (s.width != global.width || s.height != global.height) {
      badges.add(_formatResolution(s, isEs: isEs));
    }

    if (s.fps != global.fps) {
      badges.add('${s.fps} FPS');
    }

    if (s.smartBitrateEnabled != global.smartBitrateEnabled ||
        (s.smartBitrateEnabled &&
            (s.smartBitrateMin != global.smartBitrateMin ||
                s.smartBitrateMax != global.smartBitrateMax)) ||
        (!s.smartBitrateEnabled && s.bitrate != global.bitrate)) {
      if (s.smartBitrateEnabled) {
        badges.add(
          'Smart ${s.smartBitrateMin ~/ 1000}–${s.smartBitrateMax ~/ 1000} Mbps',
        );
      } else {
        badges.add('${s.bitrate ~/ 1000} Mbps');
      }
    }

    if (s.videoCodec != global.videoCodec) {
      badges.add(_formatCodec(s.videoCodec, isEs: isEs));
    }

    if (s.enableHdr != global.enableHdr) {
      badges.add(s.enableHdr ? 'HDR ON' : 'HDR OFF');
    }

    if (s.ultraLowLatency != global.ultraLowLatency) {
      badges.add(
        s.ultraLowLatency
            ? (isEs ? 'Ultra Baja Latencia' : 'Ultra Low Latency')
            : (isEs ? 'Latencia estándar' : 'Standard Latency'),
      );
    }

    if (s.framePacing != global.framePacing) {
      badges.add('Pacing: ${s.framePacing.name}');
    }

    if (s.audioConfig != global.audioConfig ||
        s.playLocalAudio != global.playLocalAudio) {
      badges.add(isEs ? 'Audio propio' : 'Custom Audio');
    }

    if (s.enableSops != global.enableSops ||
        s.hostPresetOverrideEnabled != global.hostPresetOverrideEnabled ||
        s.hostPresetOverrideId != global.hostPresetOverrideId) {
      badges.add(isEs ? 'Optimización Host' : 'Host Optimization');
    }

    if (badges.isEmpty) {
      badges.add(isEs ? 'Igual a Global' : 'Same as Global');
    }
    return badges;
  }

  static String _formatResolution(StreamConfiguration c, {required bool isEs}) {
    if (c.isMatchDisplay) {
      return isEs ? 'Igualar pantalla' : 'Match Display';
    }
    if (c.height == 720) return '720p';
    if (c.height == 1080) return '1080p';
    if (c.height == 1440) return '1440p';
    if (c.height == 2160) return '4K';
    return '${c.width}×${c.height}';
  }

  static String _formatCodec(VideoCodec codec, {required bool isEs}) {
    return switch (codec) {
      VideoCodec.auto => isEs ? 'Codec Auto' : 'Auto Codec',
      VideoCodec.h264 => 'H.264',
      VideoCodec.h265 => 'HEVC',
      VideoCodec.av1 => 'AV1',
    };
  }

  static String _formatLauncherName(String raw) {
    return switch (raw) {
      'classic' => 'Classic',
      'ps5' => 'PS5',
      'hero' => 'Hero',
      'bigScreen' => 'Big Screen',
      'backbone' => 'Backbone',
      _ => raw,
    };
  }
}

