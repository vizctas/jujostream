import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class UiSoundService {
  UiSoundService._();

  static AudioPlayer? _player;
  static AudioPlayer? _ambiencePlayer;
  static AudioPlayer? _initPlayer;
  static Uint8List? _clickWav;
  static bool _configured = false;
  static bool _ambiencePlaying = false;
  static bool _isStreaming = false;
  static Future<void>? _ambiencePlayFuture;

  /// Monotonically increasing generation counter.  Every call to
  /// [stopAmbience] or [restartAmbience] bumps this value.  Stale
  /// `whenComplete` callbacks from a previous stop compare their captured
  /// generation against the current one and become no-ops when they differ.
  static int _stopGeneration = 0;

  /// Resolved path to the app-support audio cache directory.
  /// On macOS this lives inside the sandbox container and is always readable.
  static String? _audioCacheDir;

  /// Path of the last written ambience file (for manual loop replay).
  static String? _lastAmbienceFilePath;

  // ------------------------------------------------------------------
  // Stream session guards
  // ------------------------------------------------------------------

  static void enterStreamSession() {
    _isStreaming = true;
    stopAmbience();
  }

  static void exitStreamSession() {
    _isStreaming = false;
  }

  /// Forces ambience to (re)start regardless of the current play state.
  ///
  /// Explicitly clears [_isStreaming] before playing so that timing races
  /// (where GameStreamScreen.dispose has not yet fired) cannot silently
  /// block playback.  Safe to call even while GameStreamScreen is still
  /// tearing down its route animation.
  static void restartAmbience() {
    _isStreaming = false; // force-clear before the guard in playAmbience()
    _ambiencePlaying = false;
    _ambiencePlayFuture = null;
    _lastAmbienceFilePath = null;
    // Bump generation so any pending whenComplete from a prior stopAmbience()
    // becomes a no-op and cannot kill the playback we are about to start.
    final gen = ++_stopGeneration;
    if (_ambiencePlayer != null) {
      _ambiencePlayer!.stop().whenComplete(() {
        if (_stopGeneration == gen) playAmbience();
      });
    } else {
      playAmbience();
    }
  }

  // ------------------------------------------------------------------
  // Ensure the audio cache directory exists
  // ------------------------------------------------------------------

  static Future<String> _ensureAudioCacheDir() async {
    if (_audioCacheDir != null) return _audioCacheDir!;
    final dir = await getApplicationSupportDirectory();
    final audioDir = io.Directory(p.join(dir.path, 'audio_cache'));
    if (!audioDir.existsSync()) {
      audioDir.createSync(recursive: true);
    }
    _audioCacheDir = audioDir.path;
    return _audioCacheDir!;
  }

  /// Writes [bytes] to a file inside the app-support audio cache and returns
  /// the absolute path.  On macOS this avoids the sandbox issue where
  /// audioplayers_darwin writes to Caches/ which AVPlayer cannot read.
  static Future<String> _writeToAudioCache(
    String fileName,
    Uint8List bytes,
  ) async {
    final dir = await _ensureAudioCacheDir();
    final filePath = p.join(dir, fileName);
    final file = io.File(filePath);
    // Only write if the file doesn't exist or has a different size.
    if (!file.existsSync() || file.lengthSync() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return filePath;
  }

  // ------------------------------------------------------------------
  // Player factories
  // ------------------------------------------------------------------

  static AudioPlayer _getInitPlayer() {
    if (_initPlayer == null) {
      final p = AudioPlayer();
      p.setAudioContext(_ambientContext());
      p.setReleaseMode(ReleaseMode.stop);
      p.setVolume(0.7);
      _initPlayer = p;
    }
    return _initPlayer!;
  }

  static AudioPlayer _getAmbiencePlayer() {
    if (_ambiencePlayer == null) {
      final p = AudioPlayer();
      p.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.none,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: const <AVAudioSessionOptions>{},
          ),
        ),
      );
      p.setReleaseMode(ReleaseMode.stop);
      p.setVolume(0.25);
      // Manual loop: when the track finishes, replay from the cached file.
      p.onPlayerComplete.listen((_) {
        if (_ambiencePlaying && _lastAmbienceFilePath != null) {
          p.play(DeviceFileSource(_lastAmbienceFilePath!)).catchError((_) {});
        }
      });
      _ambiencePlayer = p;
    }
    return _ambiencePlayer!;
  }

  static AudioPlayer _getPlayer() {
    if (_player == null) {
      final p = AudioPlayer();
      p.setAudioContext(_ambientContext());
      p.setReleaseMode(ReleaseMode.stop);
      p.setVolume(0.36);
      _player = p;
    }
    return _player!;
  }

  static AudioContext _ambientContext() => AudioContext(
    android: const AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: false,
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.notificationEvent,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.ambient,
      options: const <AVAudioSessionOptions>{},
    ),
  );

  // ------------------------------------------------------------------
  // Initialization
  // ------------------------------------------------------------------

  static Future<void> ensureInitialized() async {
    if (_configured) return;
    final player = _getPlayer();
    await player.setAudioContext(_ambientContext());
    _configured = true;
    // Pre-warm the audio cache directory so first playback is fast.
    _ensureAudioCacheDir();
  }

  // ------------------------------------------------------------------
  // Click sound (generated WAV)
  // ------------------------------------------------------------------

  static Uint8List _buildClickWav() {
    const sampleRate = 8000;
    const hz = 1200.0;
    const durationMs = 35;
    final numSamples = (sampleRate * durationMs) ~/ 1000;
    final pcm = Int16List(numSamples);

    for (var i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final envelope = exp(-t * 120.0) * 0.6;
      final sample = sin(2 * pi * hz * t) * envelope;
      pcm[i] = (sample * 28000).round().clamp(-32768, 32767);
    }

    final byteCount = numSamples * 2;
    final header = ByteData(44);
    _setFourCC(header, 0, 'RIFF');
    header.setUint32(4, 36 + byteCount, Endian.little);
    _setFourCC(header, 8, 'WAVE');
    _setFourCC(header, 12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    _setFourCC(header, 36, 'data');
    header.setUint32(40, byteCount, Endian.little);

    final result = Uint8List(44 + byteCount);
    result.setRange(0, 44, header.buffer.asUint8List());
    for (var i = 0; i < numSamples; i++) {
      result[44 + i * 2] = pcm[i] & 0xFF;
      result[44 + i * 2 + 1] = (pcm[i] >> 8) & 0xFF;
    }
    return result;
  }

  static void _setFourCC(ByteData bd, int offset, String fourCC) {
    for (var i = 0; i < 4; i++) {
      bd.setUint8(offset + i, fourCC.codeUnitAt(i));
    }
  }

  /// Cached path for the click WAV inside app-support.
  static String? _clickWavPath;

  static void playClick() {
    _playClickAsync();
  }

  static Future<void> _playClickAsync() async {
    try {
      _clickWav ??= _buildClickWav();
      _clickWavPath ??= await _writeToAudioCache('click.wav', _clickWav!);
      final player = _getPlayer();
      player.stop();
      await player.play(DeviceFileSource(_clickWavPath!));
    } catch (_) {
      SystemSound.play(SystemSoundType.click);
    }
  }

  // ------------------------------------------------------------------
  // Favorite sound (generated WAV)
  // ------------------------------------------------------------------

  static Uint8List? _favWav;
  static String? _favWavPath;

  static Uint8List _buildFavoriteWav() {
    const sampleRate = 8000;
    const durationMs = 80;
    final numSamples = (sampleRate * durationMs) ~/ 1000;
    final pcm = Int16List(numSamples);
    final half = numSamples ~/ 2;

    for (var i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final hz = i < half ? 880.0 : 1320.0;
      final envelope = exp(-t * 50.0) * 0.5;
      final sample = sin(2 * pi * hz * t) * envelope;
      pcm[i] = (sample * 26000).round().clamp(-32768, 32767);
    }

    final byteCount = numSamples * 2;
    final header = ByteData(44);
    _setFourCC(header, 0, 'RIFF');
    header.setUint32(4, 36 + byteCount, Endian.little);
    _setFourCC(header, 8, 'WAVE');
    _setFourCC(header, 12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    _setFourCC(header, 36, 'data');
    header.setUint32(40, byteCount, Endian.little);

    final result = Uint8List(44 + byteCount);
    result.setRange(0, 44, header.buffer.asUint8List());
    for (var i = 0; i < numSamples; i++) {
      result[44 + i * 2] = pcm[i] & 0xFF;
      result[44 + i * 2 + 1] = (pcm[i] >> 8) & 0xFF;
    }
    return result;
  }

  static void playFavorite() {
    _playFavoriteAsync();
  }

  static Future<void> _playFavoriteAsync() async {
    try {
      _favWav ??= _buildFavoriteWav();
      _favWavPath ??= await _writeToAudioCache('favorite.wav', _favWav!);
      final player = _getPlayer();
      player.stop();
      await player.play(DeviceFileSource(_favWavPath!));
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Asset loader — writes to app-support so DeviceFileSource works
  // ------------------------------------------------------------------

  /// Loads a Flutter asset and writes it to the audio cache directory.
  /// Returns the absolute file path, or null on failure.
  static Future<String?> _loadAssetToFile(String assetPath) async {
    try {
      final data = await rootBundle.load('assets/$assetPath');
      final bytes = data.buffer.asUint8List();
      // Use the asset filename as the cache filename.
      final fileName = assetPath.replaceAll('/', '_');
      return await _writeToAudioCache(fileName, bytes);
    } catch (e) {
      debugPrint('[UiSound] Failed to load asset $assetPath: $e');
      return null;
    }
  }

  // ------------------------------------------------------------------
  // Ambience sound
  // ------------------------------------------------------------------

  static void playAmbience() {
    if (_ambiencePlaying) return;
    if (_isStreaming) return;
    _ambiencePlaying = true;
    _ambiencePlayFuture = _playAmbienceAsync();
  }

  static Future<void> _playAmbienceAsync() async {
    try {
      if (!_ambiencePlaying) return;

      final prefs = await SharedPreferences.getInstance();
      final soundKey = prefs.getString('standby_sound') ?? 'Alone';

      String assetName;
      switch (soundKey) {
        case 'Lost':
          assetName = 'startup_loop_sound_003.mp3';
          break;
        case 'Room':
          assetName = 'startup_loop_sound_002.mp3';
          break;
        case 'Stars':
          assetName = 'startup_loop_sound_001.mp3';
          break;
        case 'Alone':
        default:
          assetName = 'startup_loop_sound.mp3';
          break;
      }

      final player = _getAmbiencePlayer();

      // Write asset to app-support directory, then play via DeviceFileSource.
      // This avoids the macOS sandbox issue where audioplayers_darwin's
      // internal BytesSource→cache conversion fails (AVPlayerItem.Status.failed).
      String? filePath = await _loadAssetToFile('sound/ambience/$assetName');

      // Fallback to default sound if the selected file is missing.
      if (filePath == null && assetName != 'startup_loop_sound.mp3') {
        debugPrint('[UiSound] $assetName not found, falling back to default');
        filePath = await _loadAssetToFile(
          'sound/ambience/startup_loop_sound.mp3',
        );
      }

      if (filePath == null || !_ambiencePlaying) return;
      _lastAmbienceFilePath = filePath;
      await player.play(DeviceFileSource(filePath));
    } catch (e) {
      debugPrint('[UiSound] playAmbience error: $e');
    }
  }

  static void stopAmbience() {
    _ambiencePlaying = false;
    _lastAmbienceFilePath = null;
    final gen = ++_stopGeneration;
    final pending = _ambiencePlayFuture;
    _ambiencePlayFuture = null;
    if (pending != null) {
      // Only stop the player if no newer play/stop has occurred since this
      // call.  Without the generation check, a slow-completing future from
      // a previous stop can kill playback started by a later restartAmbience().
      pending.whenComplete(() {
        if (_stopGeneration == gen) {
          _ambiencePlayer?.stop();
        }
      });
    } else {
      _ambiencePlayer?.stop();
    }
  }

  // ------------------------------------------------------------------
  // Click-to-init sound
  // ------------------------------------------------------------------

  static String? _clickToInitPath;

  static void playClickToInit() {
    _playClickToInitAsync();
  }

  static Future<void> _playClickToInitAsync() async {
    try {
      _clickToInitPath ??= await _loadAssetToFile('sound/ui/click_to_init.mp3');
      if (_clickToInitPath == null) return;
      final player = _getInitPlayer();
      player.stop();
      await player.play(DeviceFileSource(_clickToInitPath!));
    } catch (e) {
      debugPrint('[UiSound] playClickToInit error: $e');
    }
  }

  // ------------------------------------------------------------------
  // Server enter sound (cv_server.mp3)
  // ------------------------------------------------------------------

  static String? _serverEnterPath;

  static void playServerEnter() {
    _playServerEnterAsync();
  }

  static Future<void> _playServerEnterAsync() async {
    try {
      _serverEnterPath ??= await _loadAssetToFile('sound/ui/cv_server.mp3');
      if (_serverEnterPath == null) return;
      final player = _getInitPlayer();
      player.stop();
      await player.play(DeviceFileSource(_serverEnterPath!));
    } catch (e) {
      debugPrint('[UiSound] playServerEnter error: $e');
    }
  }

  // ------------------------------------------------------------------
  // UI move sound (ui_move.mp3) — lightweight navigation feedback
  // ------------------------------------------------------------------

  static String? _uiMovePath;

  static void playUiMove() {
    _playUiMoveAsync();
  }

  static Future<void> _playUiMoveAsync() async {
    try {
      _uiMovePath ??= await _loadAssetToFile('sound/ui/ui_move.mp3');
      if (_uiMovePath == null) return;
      final player = _getPlayer();
      player.stop();
      await player.play(DeviceFileSource(_uiMovePath!));
    } catch (e) {
      debugPrint('[UiSound] playUiMove error: $e');
    }
  }
}
