import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

class SmartBitrateService {
  SmartBitrateService._();
  static final instance = SmartBitrateService._();

  // visual quality at significantly lower bitrates than H.264.
  // H.264: 0.115 (baseline), H.265: ~30% less, AV1: ~43% less.
  static double _bitsPerPixelForCodec(String codec) => switch (codec) {
    'AV1'  => 0.065,
    'H265' => 0.080,
    _      => 0.115, // H.264 or unknown
  };

  double? _lastThroughputMbps;
  double? get lastThroughputMbps => _lastThroughputMbps;

  double? _lastRttMs;
  double? get lastRttMs => _lastRttMs;

  int? _lastRecommendedKbps;
  int? get lastRecommendedKbps => _lastRecommendedKbps;

  double? _lastRttSpreadMs;
  double? get lastRttSpreadMs => _lastRttSpreadMs;

  // when reconnecting to the same server within the TTL window.
  static const _cacheTtl = Duration(minutes: 5);
  final Map<String, _CachedMeasurement> _hostCache = {};

  /// Clears the measurement cache for all hosts or a specific host.
  void clearCache([String? host]) {
    if (host != null) {
      _hostCache.remove(host);
    } else {
      _hostCache.clear();
    }
  }

  /// [videoCodec] should be the resolved codec name: 'H264', 'H265', or 'AV1'.
  /// Used to select codec-appropriate bits-per-pixel target.
  Future<int> measureAndRecommend({
    required String host,
    required int httpsPort,
    required int minKbps,
    required int maxKbps,
    String? posterProbeUrl,
    int width = 1920,
    int height = 1080,
    int fps = 60,
    bool enableHdr = false,
    String videoCodec = 'H264',
  }) async {
    final cacheKey = '$host:$httpsPort';
    final cached = _hostCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.timestamp) < _cacheTtl) {
      debugPrint(
        '[SmartBitrate] Cache HIT for $cacheKey '
        '(age=${DateTime.now().difference(cached.timestamp).inSeconds}s)',
      );
      _lastThroughputMbps = cached.throughputMbps;
      _lastRttMs = cached.rttMs;
      _lastRttSpreadMs = cached.rttSpreadMs;

      final recommended = _calculateOptimalBitrate(
        throughputMbps: cached.throughputMbps,
        minKbps: minKbps,
        maxKbps: maxKbps,
        width: width,
        height: height,
        fps: fps,
        enableHdr: enableHdr,
        videoCodec: videoCodec,
        rttMs: cached.rttMs,
        rttSpreadMs: cached.rttSpreadMs,
      );
      _lastRecommendedKbps = recommended;
      debugPrint(
        '[SmartBitrate] CACHED RESULT: ${recommended ~/ 1000} Mbps '
        '(range: ${minKbps ~/ 1000}-${maxKbps ~/ 1000})',
      );
      return recommended;
    }

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4)
        ..badCertificateCallback = (_, _, _) => true;

      try {
        final rttProfile = await _measureRtt(client, host, httpsPort);
        _lastRttMs = rttProfile.medianMs;
        _lastRttSpreadMs = rttProfile.spreadMs;

        final rttBandwidthMbps = _rttToBandwidthEstimate(rttProfile.medianMs);
        var rttSafeMbps =
            rttBandwidthMbps *
            _rttSafetyFactor(rttProfile.medianMs, rttProfile.spreadMs);

        debugPrint(
          '[SmartBitrate] RTT median=${rttProfile.medianMs.toStringAsFixed(1)}ms '
          'spread=${rttProfile.spreadMs.toStringAsFixed(1)}ms '
          '→ raw=${rttBandwidthMbps.toStringAsFixed(1)} Mbps safe=${rttSafeMbps.toStringAsFixed(1)} Mbps',
        );

        double? probeMbps;
        if (posterProbeUrl != null && posterProbeUrl.isNotEmpty) {
          probeMbps = await _probePoster(client, posterProbeUrl);
          if (probeMbps != null && probeMbps > 0) {
            debugPrint(
              '[SmartBitrate] Poster throughput: ${probeMbps.toStringAsFixed(1)} Mbps',
            );
          }
        }

        final throughputMbps = probeMbps != null && probeMbps > 0
            ? min(rttSafeMbps, probeMbps * 0.92)
            : rttSafeMbps;

        _lastThroughputMbps = throughputMbps;

        _hostCache[cacheKey] = _CachedMeasurement(
          throughputMbps: throughputMbps,
          rttMs: rttProfile.medianMs,
          rttSpreadMs: rttProfile.spreadMs,
          timestamp: DateTime.now(),
        );

        final recommended = _calculateOptimalBitrate(
          throughputMbps: throughputMbps,
          minKbps: minKbps,
          maxKbps: maxKbps,
          width: width,
          height: height,
          fps: fps,
          enableHdr: enableHdr,
          videoCodec: videoCodec,
          rttMs: rttProfile.medianMs,
          rttSpreadMs: rttProfile.spreadMs,
        );

        _lastRecommendedKbps = recommended;
        debugPrint(
          '[SmartBitrate] RESULT: throughput=${throughputMbps.toStringAsFixed(1)} Mbps '
          '→ recommended=${recommended ~/ 1000} Mbps (range: ${minKbps ~/ 1000}-${maxKbps ~/ 1000})',
        );
        return recommended;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      debugPrint('[SmartBitrate] measurement failed: $e — using midpoint');
      final fallback = ((minKbps + maxKbps) / 2).round();
      _lastRecommendedKbps = fallback;
      return fallback;
    }
  }

  Future<_RttProfile> _measureRtt(
    HttpClient client,
    String host,
    int httpsPort,
  ) async {
    final uri = Uri.parse('https://$host:$httpsPort/serverinfo');
    final rtts = <double>[];

    try {
      final warmReq = await client.getUrl(uri);
      final warmResp = await warmReq.close().timeout(
        const Duration(seconds: 3),
      );
      await warmResp.drain<void>();
    } catch (_) {}

    for (var i = 0; i < 5; i++) {
      try {
        final sw = Stopwatch()..start();
        final req = await client.getUrl(uri);
        final resp = await req.close().timeout(const Duration(seconds: 2));

        await resp.drain<void>();
        sw.stop();
        final rttMs = sw.elapsedMicroseconds / 1000.0;
        rtts.add(rttMs);
        debugPrint('[SmartBitrate]   rtt[$i]: ${rttMs.toStringAsFixed(1)}ms');
      } catch (e) {
        debugPrint('[SmartBitrate]   rtt[$i]: FAILED — $e');
      }
    }

    if (rtts.isEmpty) {
      throw Exception('No successful RTT samples');
    }

    rtts.sort();

    final median = rtts[rtts.length ~/ 2];
    final spread = ((rtts.last - rtts.first).clamp(0, 9999)).toDouble();
    return _RttProfile(medianMs: median, spreadMs: spread);
  }

  double _rttSafetyFactor(double rttMs, double spreadMs) {
    var factor = switch (rttMs) {
      < 8 => 0.84,
      < 20 => 0.76,
      < 40 => 0.68,
      < 70 => 0.58,
      < 100 => 0.50,
      _ => 0.42,
    };

    if (spreadMs > 40) {
      factor -= 0.12;
    } else if (spreadMs > 20) {
      factor -= 0.07;
    } else if (spreadMs > 10) {
      factor -= 0.03;
    }

    return (factor.clamp(0.30, 0.90) as num).toDouble();
  }

  double _rttToBandwidthEstimate(double rttMs) {
    if (rttMs < 3) return 500.0;
    if (rttMs < 8) return 200.0;
    if (rttMs < 15) return 100.0;
    if (rttMs < 30) return 50.0;
    if (rttMs < 60) return 30.0;
    if (rttMs < 100) return 15.0;
    return 8.0;
  }

  Future<double?> _probePoster(HttpClient client, String url) async {
    final uri = Uri.parse(url);
    debugPrint('[SmartBitrate] Poster probe: $url');

    try {
      final warmReq = await client.getUrl(uri);
      final warmResp = await warmReq.close().timeout(
        const Duration(seconds: 3),
      );
      int warmBytes = 0;
      await for (final chunk in warmResp) {
        warmBytes += chunk.length;
      }
      if (warmBytes < 1000) {
        debugPrint('[SmartBitrate]   warm-up: only ${warmBytes}B — too small');
        return null;
      }
      debugPrint('[SmartBitrate]   warm-up: ${warmBytes}B');

      final stopwatch = Stopwatch()..start();
      final measReq = await client.getUrl(uri);
      final measResp = await measReq.close().timeout(
        const Duration(seconds: 3),
      );
      int totalBytes = 0;
      await for (final chunk in measResp) {
        totalBytes += chunk.length;
      }
      stopwatch.stop();

      if (totalBytes > 5000 && stopwatch.elapsedMilliseconds > 0) {
        final mbps =
            (totalBytes * 8.0) / (stopwatch.elapsedMilliseconds * 1000.0);
        debugPrint(
          '[SmartBitrate]   measure: ${totalBytes}B in '
          '${stopwatch.elapsedMilliseconds}ms → ${mbps.toStringAsFixed(1)} Mbps',
        );
        return mbps;
      }
    } catch (e) {
      debugPrint('[SmartBitrate]   poster probe error: $e');
    }
    return null;
  }

  int _calculateOptimalBitrate({
    required double throughputMbps,
    required int minKbps,
    required int maxKbps,
    required int width,
    required int height,
    required int fps,
    required bool enableHdr,
    required String videoCodec,
    required double rttMs,
    required double rttSpreadMs,
  }) {
    final bpp = _bitsPerPixelForCodec(videoCodec);
    final megapixelsPerSecond = (width * height * fps) / 1000000.0;
    var qualityTargetKbps = (megapixelsPerSecond * bpp * 1000).round();

    if (fps >= 120) {
      qualityTargetKbps = (qualityTargetKbps * 1.12).round();
    } else if (fps >= 90) {
      qualityTargetKbps = (qualityTargetKbps * 1.08).round();
    }

    if (enableHdr) {
      qualityTargetKbps = (qualityTargetKbps * 1.08).round();
    }

    var networkMargin = switch (fps) {
      >= 120 => 0.44,
      >= 90 => 0.48,
      >= 60 => 0.54,
      _ => 0.60,
    };

    if (rttMs > 60) {
      networkMargin -= 0.06;
    }
    if (rttSpreadMs > 20) {
      networkMargin -= 0.05;
    }

    final throughputCapKbps =
        (throughputMbps * 1000 * networkMargin.clamp(0.35, 0.70)).round();
    final optimalKbps = min(qualityTargetKbps, throughputCapKbps);

    debugPrint(
      '[SmartBitrate] Quality target=${qualityTargetKbps ~/ 1000} Mbps '
      '(mpps=${megapixelsPerSecond.toStringAsFixed(1)} hdr=$enableHdr), '
      'network cap=${throughputCapKbps ~/ 1000} Mbps, '
      'optimal=${optimalKbps ~/ 1000} Mbps, '
      'range=${minKbps ~/ 1000}-${maxKbps ~/ 1000} Mbps',
    );

    return optimalKbps.clamp(minKbps, maxKbps);
  }
}

class _RttProfile {
  final double medianMs;
  final double spreadMs;

  const _RttProfile({required this.medianMs, required this.spreadMs});
}

/// Cached network measurement for a specific host.
class _CachedMeasurement {
  final double throughputMbps;
  final double rttMs;
  final double rttSpreadMs;
  final DateTime timestamp;

  const _CachedMeasurement({
    required this.throughputMbps,
    required this.rttMs,
    required this.rttSpreadMs,
    required this.timestamp,
  });
}
