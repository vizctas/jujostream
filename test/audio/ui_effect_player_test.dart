import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
// ignore: depend_on_referenced_packages
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/services/audio/ui_effect_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAudioplayersPlatform platform;
  late _FakeGlobalAudioplayersPlatform globalPlatform;

  setUp(() {
    platform = _FakeAudioplayersPlatform();
    globalPlatform = _FakeGlobalAudioplayersPlatform();
    AudioplayersPlatformInterface.instance = platform;
    GlobalAudioplayersPlatformInterface.instance = globalPlatform;
  });

  test('UI effect playback never polls position', () async {
    final player = await UiEffectPlayer.create().timeout(
      const Duration(seconds: 5),
    );

    await player
        .play(DeviceFileSource('ui.wav'))
        .timeout(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);

    expect(
      platform.calls.where((call) => call.method == 'getCurrentPosition'),
      isEmpty,
    );

    await player.shutdown().timeout(const Duration(seconds: 5));
  });

  test('shutdown rejects queued and future UI effects', () async {
    final player = await UiEffectPlayer.create().timeout(
      const Duration(seconds: 5),
    );
    final firstPlay = player.play(DeviceFileSource('first.wav'));
    final queuedPlay = player.play(DeviceFileSource('queued.wav'));

    await player.shutdown().timeout(const Duration(seconds: 5));
    await Future.wait([firstPlay, queuedPlay]);
    platform.calls.clear();

    await player.play(DeviceFileSource('after-shutdown.wav'));
    await Future<void>.delayed(Duration.zero);

    expect(platform.calls.where((call) => call.method == 'resume'), isEmpty);
  });
}

class _FakeCall {
  const _FakeCall(this.method);

  final String method;
}

class _FakeAudioplayersPlatform extends AudioplayersPlatformInterface {
  final calls = <_FakeCall>[];
  final _events = <String, StreamController<AudioEvent>>{};

  void _record(String method) => calls.add(_FakeCall(method));

  @override
  Future<void> create(String playerId) async {
    _record('create');
    _events[playerId] = StreamController<AudioEvent>.broadcast();
  }

  @override
  Future<void> dispose(String playerId) async {
    _record('dispose');
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> emitError(String playerId, String code, String message) async {}

  @override
  Future<void> emitLog(String playerId, String message) async {}

  @override
  Future<int?> getCurrentPosition(String playerId) async {
    _record('getCurrentPosition');
    return null;
  }

  @override
  Future<int?> getDuration(String playerId) async => null;

  @override
  Stream<AudioEvent> getEventStream(String playerId) =>
      _events[playerId]!.stream;

  @override
  Future<void> pause(String playerId) async => _record('pause');

  @override
  Future<void> release(String playerId) async => _record('release');

  @override
  Future<void> resume(String playerId) async => _record('resume');

  @override
  Future<void> seek(String playerId, Duration position) async =>
      _record('seek');

  @override
  Future<void> setAudioContext(
    String playerId,
    AudioContext audioContext,
  ) async => _record('setAudioContext');

  @override
  Future<void> setBalance(String playerId, double balance) async =>
      _record('setBalance');

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async =>
      _record('setPlaybackRate');

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async =>
      _record('setPlayerMode');

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async =>
      _record('setReleaseMode');

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    _record('setSourceBytes');
    _events[playerId]!.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {
    _record('setSourceUrl');
    _events[playerId]!.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Future<void> setVolume(String playerId, double volume) async =>
      _record('setVolume');

  @override
  Future<void> stop(String playerId) async => _record('stop');
}

class _FakeGlobalAudioplayersPlatform
    extends GlobalAudioplayersPlatformInterface {
  final _events = StreamController<GlobalAudioEvent>.broadcast();

  @override
  Future<void> emitGlobalError(String code, String message) async {}

  @override
  Future<void> emitGlobalLog(String message) async {}

  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => _events.stream;

  @override
  Future<void> init() async {}

  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async {}
}
