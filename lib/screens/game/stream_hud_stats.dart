import 'package:flutter/foundation.dart';

@immutable
class StreamHudStats {
  const StreamHudStats({
    this.fps = '--',
    this.latency = '--',
    this.bitrate = '--',
    this.dropRate = '--',
    this.resolution = '--',
    this.codec = '--',
    this.queueDepth = '--',
    this.pendingAudioMs = '--',
    this.rttVariance = '--',
    this.renderPath = '--',
  });

  factory StreamHudStats.fromEvent(Map<String, dynamic> event) {
    final decodeTime = event['decodeTime'] is num
        ? event['decodeTime'] as num
        : null;
    final queueDepth = event['queueDepth'] is num
        ? (event['queueDepth'] as num).toInt()
        : null;
    final pendingAudio = event['pendingAudioMs'] is num
        ? (event['pendingAudioMs'] as num).toInt()
        : null;
    final rttVariance = event['rttVarianceMs'] is num
        ? (event['rttVarianceMs'] as num).toInt()
        : null;
    final resolutionValue = event['resolution']?.toString();
    final codecValue = event['codec']?.toString();
    final renderPathValue = event['renderPath']?.toString();
    final dropRateValue = event['dropRate'];

    return StreamHudStats(
      fps: '${event['fps'] ?? '--'} FPS',
      latency: decodeTime != null
          ? '${decodeTime.toStringAsFixed(2)} ms'
          : '--',
      bitrate: '${event['bitrate'] ?? '--'} Mbps',
      dropRate: dropRateValue != null ? '$dropRateValue%' : '--',
      resolution:
          resolutionValue != null &&
              resolutionValue != '0x0' &&
              resolutionValue.isNotEmpty
          ? resolutionValue
          : '--',
      codec:
          codecValue != null && codecValue != 'unknown' && codecValue.isNotEmpty
          ? codecValue
          : '--',
      queueDepth: queueDepth?.toString() ?? '--',
      pendingAudioMs: pendingAudio != null ? '$pendingAudio ms' : '--',
      rttVariance: rttVariance != null && rttVariance >= 0
          ? '$rttVariance ms'
          : '--',
      renderPath: renderPathValue != null && renderPathValue.isNotEmpty
          ? renderPathValue
          : '--',
    );
  }

  final String fps;
  final String latency;
  final String bitrate;
  final String dropRate;
  final String resolution;
  final String codec;
  final String queueDepth;
  final String pendingAudioMs;
  final String rttVariance;
  final String renderPath;
}

class StreamHudStatsNotifier extends ValueNotifier<StreamHudStats> {
  StreamHudStatsNotifier({
    this.publishInterval = const Duration(milliseconds: 250),
  }) : latest = const StreamHudStats(),
       _lastPublishedAt = DateTime.fromMillisecondsSinceEpoch(0),
       super(const StreamHudStats());

  final Duration publishInterval;
  StreamHudStats latest;
  DateTime _lastPublishedAt;

  void ingest(
    Map<String, dynamic> event, {
    required bool visible,
    DateTime? now,
  }) {
    latest = StreamHudStats.fromEvent(event);
    if (!visible) return;
    final timestamp = now ?? DateTime.now();
    if (timestamp.difference(_lastPublishedAt) < publishInterval) return;
    _lastPublishedAt = timestamp;
    value = latest;
  }
}
