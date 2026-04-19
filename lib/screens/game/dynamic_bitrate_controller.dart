import 'package:flutter/foundation.dart';

/// Callback invoked when the controller decides a bitrate reconnect is needed.
/// [newBitrateKbps] is null when fully recovered to the base bitrate.
typedef BitrateReconnectCallback = void Function(int? newBitrateKbps);

/// Pure-logic controller for dynamic bitrate adaptation.
///
/// Evaluates streaming stats each tick and decides whether to reduce or
/// recover the bitrate. The actual reconnect is delegated to the caller
/// via [onReconnectNeeded].
///
/// Extracted from `_GameStreamScreenState` to separate business
/// logic from UI state.
class DynamicBitrateController {
  DynamicBitrateController({required this.onReconnectNeeded});

  final BitrateReconnectCallback onReconnectNeeded;

  /// Current adjusted bitrate, or null if using the base config bitrate.
  int? currentBitrateKbps;

  int _congestCount = 0;
  int _stableCount = 0;
  bool reconnecting = false;

  DateTime? _lastReconnectTime;
  static const _reconnectMinInterval = Duration(seconds: 10);

  /// Returns the effective bitrate to use for the stream.
  int effectiveBitrate(int baseBitrate) => currentBitrateKbps ?? baseBitrate;

  /// Evaluate a stats tick and potentially trigger a bitrate change.
  ///
  /// [enabled] — master switch from config.
  /// [connected] — whether the stream is currently active.
  /// [baseBitrate] — the user-configured bitrate in Kbps.
  /// [fps] — configured FPS target.
  /// [sensitivity] — 1 (low), 2 (medium), 3 (high).
  /// [event] — raw stats map from the platform channel.
  void evaluate({
    required bool enabled,
    required bool connected,
    required int baseBitrate,
    required int fps,
    required int sensitivity,
    required Map<String, dynamic> event,
  }) {
    if (!enabled) return;
    if (reconnecting || !connected) return;

    final dropRate = event['dropRate'] as int? ?? 0;
    final decodeTimeMs = event['decodeTime'] as int? ?? 0;
    final pendingAudioMs = event['pendingAudioMs'] as int? ?? 0;
    final rttVarianceMs = event['rttVarianceMs'] as int? ?? 0;

    final sens = sensitivity;
    final dropThresh = const {1: 8, 2: 5, 3: 3}[sens] ?? 5;
    final hitsNeeded = const {1: 8, 2: 5, 3: 3}[sens] ?? 5;
    final reductionPct = const {1: 10, 2: 15, 3: 20}[sens] ?? 15;
    final targetFrameMs = (1000 / fps).clamp(1, 1000);
    final decodeThreshMs = const {1: 24, 2: 18, 3: 14}[sens] ?? 18;
    final pendingAudioThreshMs = const {1: 120, 2: 90, 3: 70}[sens] ?? 90;
    final rttVarianceThreshMs = const {1: 32, 2: 24, 3: 18}[sens] ?? 24;

    final floorKbps = (baseBitrate * 0.30).round().clamp(1000, baseBitrate);
    final currentKbps = currentBitrateKbps ?? baseBitrate;

    final decodePressure = decodeTimeMs >= decodeThreshMs;
    final audioPressure = pendingAudioMs >= pendingAudioThreshMs;
    final networkPressure = rttVarianceMs >= rttVarianceThreshMs;
    final pressureScore =
        (dropRate > dropThresh ? 2 : 0) +
        (decodePressure ? 1 : 0) +
        (audioPressure ? 1 : 0) +
        (networkPressure ? 1 : 0);

    if (pressureScore > 0) {
      _congestCount += pressureScore;
      _stableCount = 0;
      if (_congestCount >= hitsNeeded && currentKbps > floorKbps) {
        final steppedReduction = (reductionPct + ((pressureScore - 1) * 5))
            .clamp(reductionPct, 30);
        final reduced = (currentKbps * (1.0 - steppedReduction / 100.0))
            .round()
            .clamp(floorKbps, baseBitrate);
        if (reduced < currentKbps) {
          currentBitrateKbps = reduced;
          _congestCount = 0;
          _tryReconnect();
        }
      }
    } else if (dropRate == 0 &&
        decodeTimeMs <= (targetFrameMs * 0.5).round() &&
        pendingAudioMs <= (pendingAudioThreshMs ~/ 2) &&
        rttVarianceMs <= (rttVarianceThreshMs ~/ 2)) {
      _congestCount = 0;
      _stableCount++;
      if (_stableCount >= 30 && currentBitrateKbps != null) {
        final bumped = (currentKbps * 1.05).round().clamp(
          floorKbps,
          baseBitrate,
        );
        if (bumped >= baseBitrate) {
          currentBitrateKbps = null; // fully recovered
        } else if (bumped > currentKbps) {
          currentBitrateKbps = bumped;
        }
        _stableCount = 0;
        if (currentBitrateKbps != currentKbps) {
          _tryReconnect();
        }
      }
    } else {
      _congestCount = 0;
    }
  }

  void _tryReconnect() {
    if (reconnecting) return;
    final now = DateTime.now();
    if (_lastReconnectTime != null &&
        now.difference(_lastReconnectTime!) < _reconnectMinInterval) {
      debugPrint(
        '[M6] Dynamic bitrate reconnect throttled — '
        '${now.difference(_lastReconnectTime!).inSeconds}s since last',
      );
      return;
    }
    _lastReconnectTime = now;
    debugPrint(
      '[M6] Dynamic bitrate reconnect → ${currentBitrateKbps ?? "base"} Kbps',
    );
    onReconnectNeeded(currentBitrateKbps);
  }

  /// Reset all counters (e.g. on stream restart).
  void reset() {
    currentBitrateKbps = null;
    _congestCount = 0;
    _stableCount = 0;
    reconnecting = false;
    _lastReconnectTime = null;
  }
}
