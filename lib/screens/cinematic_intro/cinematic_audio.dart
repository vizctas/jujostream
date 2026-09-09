import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'cinematic_soundtrack.dart';

Uint8List _renderCinematicSoundtrack(void _) => CinematicSoundtrack.build();

/// Owns one audio output for the complete intro soundtrack.
///
/// Fire OS grants audio focus per MediaPlayer. Keeping every cue in one PCM
/// stream prevents the impact and reveal from pausing the fall layer.
class CinematicAudio {
  AudioPlayer? _player;
  String? _soundtrackPath;
  bool _disposed = false;
  bool _jumpToImpactRequested = false;

  static AudioContext get _playbackContext => AudioContext(
    android: const AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: false,
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gainTransient,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.ambient,
      options: const <AVAudioSessionOptions>{},
    ),
  );

  Future<void> initialize() async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/cinematic_soundtrack_v2.wav');
    if (!await file.exists() || await file.length() <= 44) {
      final bytes = await compute(_renderCinematicSoundtrack, null);
      await file.writeAsBytes(bytes, flush: true);
    }
    _soundtrackPath = file.path;
  }

  Future<void> play() async {
    if (_disposed) return;
    final path = _soundtrackPath;
    if (path == null) throw StateError('CinematicAudio is not initialized');

    await _player?.dispose();
    final player = AudioPlayer();
    _player = player;
    await player.setPlayerMode(PlayerMode.mediaPlayer);
    await player.setAudioContext(_playbackContext);
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setVolume(1);
    await player.play(DeviceFileSource(path));
    if (_jumpToImpactRequested) {
      await player.seek(CinematicSoundtrack.impactOffset);
    }
  }

  Future<void> jumpToImpact() async {
    _jumpToImpactRequested = true;
    await _player?.seek(CinematicSoundtrack.impactOffset);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _player?.dispose();
    _player = null;
  }
}
