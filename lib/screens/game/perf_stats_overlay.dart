import 'package:flutter/material.dart';

/// Compact perf overlay for non-Pro users.
///
/// Shows FPS, latency, bitrate, and optional drop/resolution/audio stats.
Widget buildBasicPerfOverlay({
  required String fps,
  required String latency,
  required String bitrate,
  required String dropRate,
  required String resolution,
  required String pendingAudioMs,
}) {
  return Positioned(
    top: 8,
    left: 8,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fps,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            latency,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            bitrate,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (dropRate != '--')
            Text(
              'Drop: $dropRate',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          if (resolution != '--')
            Text(
              resolution,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          if (pendingAudioMs != '--')
            Text(
              'Audio: $pendingAudioMs',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
        ],
      ),
    ),
  );
}

/// Rich perf HUD for Pro users.
///
/// Shows all streaming metrics in a compact right-aligned overlay.
class StreamHud extends StatelessWidget {
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

  const StreamHud({
    super.key,
    required this.fps,
    required this.latency,
    required this.bitrate,
    this.dropRate = '--',
    this.resolution = '--',
    this.codec = '--',
    this.queueDepth = '--',
    this.pendingAudioMs = '--',
    this.rttVariance = '--',
    this.renderPath = '--',
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 16,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatRow(Icons.speed_outlined, 'FPS: $fps'),
              const SizedBox(height: 3),
              _StatRow(Icons.timer_outlined, 'Decode: $latency'),
              const SizedBox(height: 3),
              _StatRow(Icons.swap_vert, 'Bitrate: $bitrate'),
              if (dropRate != '--') ...[
                const SizedBox(height: 3),
                _StatRow(
                  Icons.warning_amber_rounded,
                  'Drop: $dropRate',
                  color: dropRate != '0%' ? Colors.white54 : Colors.white38,
                ),
              ],
              if (resolution != '--') ...[
                const SizedBox(height: 3),
                _StatRow(Icons.monitor_outlined, 'Resolution: $resolution'),
              ],
              if (codec != '--') ...[
                const SizedBox(height: 3),
                _StatRow(Icons.videocam_outlined, codec),
              ],
              if (queueDepth != '--') ...[
                const SizedBox(height: 3),
                _StatRow(Icons.queue_outlined, 'Buffer: $queueDepth'),
              ],
              if (pendingAudioMs != '--') ...[
                const SizedBox(height: 3),
                _StatRow(Icons.graphic_eq_outlined, 'Audio: $pendingAudioMs'),
              ],
              if (rttVariance != '--') ...[
                const SizedBox(height: 3),
                _StatRow(Icons.network_ping_outlined, 'Jitter: $rttVariance'),
              ],
              if (renderPath != '--') ...[
                const SizedBox(height: 3),
                _StatRow(Icons.layers_outlined, renderPath),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _StatRow(this.icon, this.value, {this.color = Colors.white54});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 5),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
