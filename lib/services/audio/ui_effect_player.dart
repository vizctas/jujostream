import 'package:audioplayers/audioplayers.dart';

/// Serialized, low-latency player for short UI effects.
///
/// Low-latency Android playback has no position or completion support. Position
/// polling is therefore disabled, and callers must explicitly shut the player
/// down when UI audio leaves scope.
class UiEffectPlayer {
  UiEffectPlayer._(this._player);

  final AudioPlayer _player;
  Future<void> _operationTail = Future<void>.value();
  bool _acceptingPlayback = true;

  static Future<UiEffectPlayer> create({
    AudioContext? audioContext,
    double volume = 0.36,
  }) async {
    final player = AudioPlayer();
    player.positionUpdater = null;
    await player.setPlayerMode(PlayerMode.lowLatency);
    if (audioContext != null) {
      await player.setAudioContext(audioContext);
    }
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setVolume(volume);
    return UiEffectPlayer._(player);
  }

  Future<void> play(Source source) {
    if (!_acceptingPlayback) return Future<void>.value();

    final operation = _operationTail.then((_) async {
      if (!_acceptingPlayback) return;
      await _player.stop();
      if (!_acceptingPlayback) return;
      await _player.play(source);
    });
    _operationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> shutdown() {
    _acceptingPlayback = false;
    final operation = _operationTail.then((_) async {
      await _player.stop();
      await _player.dispose();
    });
    _operationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}
