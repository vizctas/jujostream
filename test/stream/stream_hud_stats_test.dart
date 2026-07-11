import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/screens/game/stream_hud_stats.dart';

void main() {
  test('formats native stream statistics without UI state', () {
    final stats = StreamHudStats.fromEvent({
      'fps': 60,
      'decodeTime': 3.456,
      'bitrate': 42,
      'dropRate': 1,
      'resolution': '1920x1080',
      'codec': 'H265',
      'queueDepth': 2,
      'pendingAudioMs': 8,
      'rttVarianceMs': 4,
      'renderPath': 'direct-submit',
    });

    expect(stats.fps, '60 FPS');
    expect(stats.latency, '3.46 ms');
    expect(stats.codec, 'H265');
    expect(stats.pendingAudioMs, '8 ms');
    expect(stats.renderPath, 'direct-submit');
  });

  test('normalizes invalid optional values', () {
    final stats = StreamHudStats.fromEvent({
      'resolution': '0x0',
      'codec': 'unknown',
      'rttVarianceMs': -1,
    });

    expect(stats.resolution, '--');
    expect(stats.codec, '--');
    expect(stats.rttVariance, '--');
  });

  test('publishes HUD updates at a bounded cadence only when visible', () {
    final notifier = StreamHudStatsNotifier();
    var notifications = 0;
    notifier.addListener(() => notifications++);
    final start = DateTime.utc(2026, 7, 10);

    notifier.ingest({'fps': 30}, visible: false, now: start);
    expect(notifier.latest.fps, '30 FPS');
    expect(notifications, 0);

    notifier.ingest({'fps': 60}, visible: true, now: start);
    notifier.ingest(
      {'fps': 59},
      visible: true,
      now: start.add(const Duration(milliseconds: 100)),
    );
    expect(notifications, 1);
    expect(notifier.value.fps, '60 FPS');
    expect(notifier.latest.fps, '59 FPS');

    notifier.ingest(
      {'fps': 58},
      visible: true,
      now: start.add(const Duration(milliseconds: 300)),
    );
    expect(notifications, 2);
    expect(notifier.value.fps, '58 FPS');
    notifier.dispose();
  });
}
