import '../../models/stream_configuration.dart';

class HostPresetProfile {
  final String id;
  final String vendor;
  final String tierId;
  final String codec;
  final int bitrateMinKbps;
  final int bitrateMaxKbps;
  final String encoderSummary;

  const HostPresetProfile({
    required this.id,
    required this.vendor,
    required this.tierId,
    required this.codec,
    required this.bitrateMinKbps,
    required this.bitrateMaxKbps,
    required this.encoderSummary,
  });

  Map<String, Object> toCatalogEntry() => {
    'vendor': vendor,
    'tier': tierId,
    'codec': codec,
    'bitrateMinKbps': bitrateMinKbps,
    'bitrateMaxKbps': bitrateMaxKbps,
    'encoder': encoderSummary,
  };
}

class HostPresetSelection {
  final String recommendedTierId;
  final String reason;
  final HostPresetProfile recommendedNvidia;
  final HostPresetProfile recommendedAmd;
  final HostPresetProfile? overrideProfile;

  const HostPresetSelection({
    required this.recommendedTierId,
    required this.reason,
    required this.recommendedNvidia,
    required this.recommendedAmd,
    this.overrideProfile,
  });
}

const Map<String, HostPresetProfile> _hostPresetProfiles = {
  'nv_competitive_1080p60': HostPresetProfile(
    id: 'nv_competitive_1080p60',
    vendor: 'nvidia',
    tierId: 'competitive_1080p60',
    codec: 'h264',
    bitrateMinKbps: 25000,
    bitrateMaxKbps: 40000,
    encoderSummary:
        'preset p1/p2, tune ull, multipass off, bFrames 0, lookahead off, aq on, gop 60',
  ),
  'nv_balanced_1440p60': HostPresetProfile(
    id: 'nv_balanced_1440p60',
    vendor: 'nvidia',
    tierId: 'balanced_1440p60',
    codec: 'h265',
    bitrateMinKbps: 35000,
    bitrateMaxKbps: 65000,
    encoderSummary:
        'preset p3/p4, tune ll, multipass off, bFrames 1, lookahead off, aq on, gop 120',
  ),
  'nv_visual_4k60': HostPresetProfile(
    id: 'nv_visual_4k60',
    vendor: 'nvidia',
    tierId: 'visual_4k60',
    codec: 'av1-or-h265',
    bitrateMinKbps: 55000,
    bitrateMaxKbps: 90000,
    encoderSummary:
        'preset p5, tune llhq, multipass qres, bFrames 2, lookahead conditional, aq on, gop 120',
  ),
  'amd_competitive_1080p60': HostPresetProfile(
    id: 'amd_competitive_1080p60',
    vendor: 'amd',
    tierId: 'competitive_1080p60',
    codec: 'h264',
    bitrateMinKbps: 25000,
    bitrateMaxKbps: 40000,
    encoderSummary:
        'usage ultralowlatency, quality speed, bFrames 0, preanalysis off, vbaq off, gop 60',
  ),
  'amd_balanced_1440p60': HostPresetProfile(
    id: 'amd_balanced_1440p60',
    vendor: 'amd',
    tierId: 'balanced_1440p60',
    codec: 'h265',
    bitrateMinKbps: 35000,
    bitrateMaxKbps: 65000,
    encoderSummary:
        'usage lowlatency, quality balanced, bFrames 0-1, preanalysis off, vbaq on, gop 120',
  ),
  'amd_visual_4k60': HostPresetProfile(
    id: 'amd_visual_4k60',
    vendor: 'amd',
    tierId: 'visual_4k60',
    codec: 'av1-or-h265',
    bitrateMinKbps: 55000,
    bitrateMaxKbps: 90000,
    encoderSummary:
        'usage lowlatency_high_quality, quality quality, bFrames 2, preanalysis off, vbaq on, gop 120',
  ),
};

const List<Map<String, Object>> hostPresetSelectionRules = [
  {
    'tier': 'visual_4k60',
    'match': 'longEdge >= 3840 || hdr == true || bitrate >= 55000',
    'reason':
        'Prefer quality-first host presets for 4K, HDR, or very high bitrate sessions.',
  },
  {
    'tier': 'balanced_1440p60',
    'match':
        'longEdge >= 2560 || bitrate >= 35000 || fps > 60 || codec in {h265,av1}',
    'reason':
        'Use balanced presets for higher resolution or advanced codec sessions that are not 4K/HDR bound.',
  },
  {
    'tier': 'competitive_1080p60',
    'match': 'fallback',
    'reason':
        'Use the lowest-latency preset for 1080p-class or explicitly latency-first sessions.',
  },
];

HostPresetProfile? hostPresetProfileById(String? id) {
  if (id == null || id.isEmpty) {
    return null;
  }
  return _hostPresetProfiles[id];
}

Map<String, Map<String, Object>> buildHostPresetCatalogExport() {
  return _hostPresetProfiles.map(
    (key, value) => MapEntry(key, value.toCatalogEntry()),
  );
}

HostPresetSelection resolveHostPresetSelection(StreamConfiguration config) {
  final longEdge = config.width >= config.height ? config.width : config.height;
  late final String tierId;
  late final String reason;

  if (longEdge >= 3840 || config.enableHdr || config.bitrate >= 55000) {
    tierId = 'visual_4k60';
    reason = '4K, HDR, or high-bitrate session';
  } else if (longEdge >= 2560 ||
      config.bitrate >= 35000 ||
      config.fps > 60 ||
      config.videoCodec == VideoCodec.h265 ||
      config.videoCodec == VideoCodec.av1) {
    tierId = 'balanced_1440p60';
    reason = 'higher-resolution or advanced-codec session';
  } else {
    tierId = 'competitive_1080p60';
    reason = 'latency-first 1080p-class session';
  }

  final overrideProfile = config.hostPresetOverrideEnabled
      ? hostPresetProfileById(config.hostPresetOverrideId)
      : null;

  return HostPresetSelection(
    recommendedTierId: tierId,
    reason: reason,
    recommendedNvidia: _hostPresetProfiles['nv_$tierId']!,
    recommendedAmd: _hostPresetProfiles['amd_$tierId']!,
    overrideProfile: overrideProfile,
  );
}

Map<String, String> buildHostPresetLaunchParams(StreamConfiguration config) {
  final selection = resolveHostPresetSelection(config);
  final params = <String, String>{
    'jujoHostPresetMode': selection.overrideProfile != null
        ? 'override'
        : 'auto',
    'jujoHostPresetTier': selection.recommendedTierId,
    'jujoHostPresetNvId': selection.recommendedNvidia.id,
    'jujoHostPresetAmdId': selection.recommendedAmd.id,
  };

  final overrideProfile = selection.overrideProfile;
  if (overrideProfile != null) {
    params['jujoHostPresetId'] = overrideProfile.id;
    params['jujoHostPresetVendor'] = overrideProfile.vendor;
    params['jujoHostPresetCodec'] = overrideProfile.codec;
  }

  return params;
}

Map<String, Object?> buildSunshineHostPresetPayload(
  StreamConfiguration config,
) {
  final selection = resolveHostPresetSelection(config);
  final overrideProfile = selection.overrideProfile;

  return {
    'jujoHostPreset': {
      'target': 'sunshine',
      'mode': overrideProfile != null ? 'override' : 'auto',
      'recommendedTier': selection.recommendedTierId,
      'recommendedProfiles': {
        'nvidia': selection.recommendedNvidia.toCatalogEntry(),
        'amd': selection.recommendedAmd.toCatalogEntry(),
      },
      if (overrideProfile != null)
        'selectedProfile': overrideProfile.toCatalogEntry(),
    },
  };
}

Map<String, Object?> buildApolloHostPresetPayload(StreamConfiguration config) {
  final selection = resolveHostPresetSelection(config);
  final overrideProfile = selection.overrideProfile;

  return {
    'clientHints': {
      'jujoHostPreset': {
        'target': 'apollo',
        'mode': overrideProfile != null ? 'override' : 'auto',
        'recommendedTier': selection.recommendedTierId,
        'recommendedProfiles': {
          'nvidia': selection.recommendedNvidia.id,
          'amd': selection.recommendedAmd.id,
        },
        if (overrideProfile != null) 'selectedProfileId': overrideProfile.id,
      },
    },
  };
}

Map<String, dynamic> buildHostPresetExport(StreamConfiguration config) {
  final selection = resolveHostPresetSelection(config);
  final overrideProfile = selection.overrideProfile;
  final codecLabel = switch (config.videoCodec) {
    VideoCodec.h264 => 'h264',
    VideoCodec.h265 => 'h265',
    VideoCodec.av1 => 'av1',
    VideoCodec.auto => 'auto',
  };

  final reason = overrideProfile != null
      ? 'manual override (${overrideProfile.id})'
      : selection.reason;

  return {
    'host_preset_override_enabled': overrideProfile != null,
    'host_preset_override_id':
        overrideProfile?.id ?? config.hostPresetOverrideId,
    'host_preset_selected_mode': overrideProfile != null ? 'override' : 'auto',
    'host_preset_tier': selection.recommendedTierId,
    'host_preset_nvidia_id': selection.recommendedNvidia.id,
    'host_preset_amd_id': selection.recommendedAmd.id,
    'host_preset_selected_id': overrideProfile?.id ?? '',
    'host_preset_selected_vendor': overrideProfile?.vendor ?? 'auto',
    'host_preset_reason':
        '$reason (${config.width}x${config.height} @ ${config.fps} fps, ${config.bitrate} kbps, $codecLabel, hdr=${config.enableHdr ? 'on' : 'off'})',
    'host_preset_selection_rules': hostPresetSelectionRules,
    'host_preset_catalog': buildHostPresetCatalogExport(),
    'host_preset_launch_query': buildHostPresetLaunchParams(config),
    'host_preset_sunshine_payload': buildSunshineHostPresetPayload(config),
    'host_preset_apollo_payload': buildApolloHostPresetPayload(config),
  };
}
