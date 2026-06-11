import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CinematicAudio {
  static const _sampleRate = 44100;
  AudioPlayer? _fallPlayer;
  AudioPlayer? _impactPlayer;
  AudioPlayer? _chimePlayer;
  String? _cacheDir;
  bool _disposed = false;

  Future<void> initialize() async {
    final dir = await getTemporaryDirectory();
    _cacheDir = dir.path;
  }

  Future<void> playFall() async {
    if (_disposed) return;
    final wav = _generateFallWav();
    final path = '$_cacheDir/cinematic_fall.wav';
    await File(path).writeAsBytes(wav);
    _fallPlayer?.dispose();
    _fallPlayer = AudioPlayer();
    await _fallPlayer!.setVolume(0.23);
    await _fallPlayer!.play(DeviceFileSource(path));
  }

  Future<void> playImpact() async {
    if (_disposed) return;
    final wav = _generateImpactWav();
    final path = '$_cacheDir/cinematic_impact.wav';
    await File(path).writeAsBytes(wav);
    _impactPlayer?.dispose();
    _impactPlayer = AudioPlayer();
    await _impactPlayer!.setVolume(0.7);
    await _impactPlayer!.play(DeviceFileSource(path));
  }

  Future<void> playRevealChime() async {
    if (_disposed) return;
    final wav = _generateRevealWav();
    final path = '$_cacheDir/cinematic_reveal.wav';
    await File(path).writeAsBytes(wav);
    _chimePlayer?.dispose();
    _chimePlayer = AudioPlayer();
    await _chimePlayer!.setVolume(0.4);
    await _chimePlayer!.play(DeviceFileSource(path));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _fallPlayer?.dispose();
    _impactPlayer?.dispose();
    _chimePlayer?.dispose();
  }

  // ── Clean Tuned Sound Design ─────────────────────────────────

  // Fall: Two-phase clean sine-wave sweep.
  // Phase 1 (0-2.5s): Quiet 400Hz -> 200Hz sweep, building tension.
  // Phase 2 (2.5-4.5s): Intensifying 200Hz -> 60Hz sweep with louder gain.
  // Pure sine, no noise. Matches the two-phase visual deformation kick.
  Uint8List _generateFallWav() {
    const duration = 4.5;
    const phase2Start = 2.5;
    final numSamples = (_sampleRate * duration).toInt();
    final samples = Float64List(numSamples);

    for (int i = 0; i < numSamples; i++) {
      final t = i / _sampleRate;
      double freq;
      double gain;

      if (t < phase2Start) {
        // Phase 1: quiet, subtle sweep 400Hz -> 200Hz
        freq = 400.0 * pow(200.0 / 400.0, t / phase2Start);
        final vibrato = sin(2 * pi * 5.0 * t) * 0.02;
        final phase = 2 * pi * freq * t + vibrato;
        final sine = sin(phase);
        // Slow attack, moderate sustain
        if (t < 0.5) {
          gain = (t / 0.5) * 0.2;
        } else {
          gain = 0.2;
        }
        samples[i] = sine * gain * 0.7;
      } else {
        // Phase 2: intensifying sweep 200Hz -> 60Hz, louder
        final t2 = t - phase2Start;
        final phase2Duration = duration - phase2Start;
        freq = 200.0 * pow(60.0 / 200.0, t2 / phase2Duration);
        final vibrato = sin(2 * pi * 7.0 * t) * 0.035;
        final phase = 2 * pi * freq * t + vibrato;
        final sine = sin(phase);
        // Quick ramp up, then sustain, fade at end
        if (t2 < 0.3) {
          gain = 0.2 + (t2 / 0.3) * 0.35;
        } else if (t2 < phase2Duration - 0.3) {
          gain = 0.55;
        } else {
          gain = 0.55 * (1.0 - (t2 - (phase2Duration - 0.3)) / 0.3);
        }
        samples[i] = sine * gain * 0.7;
      }
    }

    return _encodeWav(samples, 1);
  }

  // Impact: Two pure tones.
  // 1. Sub-bass thump: 60Hz sine, fast attack, exponential decay (~0.15s)
  // 2. Metallic ping: 520Hz sine, fast attack, slower decay (~0.4s)
  // 3. Harmonic overtone: 1040Hz, very quiet, fast decay
  Uint8List _generateImpactWav() {
    const duration = 0.8;
    final numSamples = (_sampleRate * duration).toInt();
    final samples = Float64List(numSamples);

    for (int i = 0; i < numSamples; i++) {
      final t = i / _sampleRate;
      double s = 0;

      // 1. Sub-bass thump: 60Hz
      final thumpPhase = 2 * pi * 60.0 * t;
      final thumpGain = exp(-t / 0.12);
      s += sin(thumpPhase) * thumpGain * 0.9;

      // 2. Metallic ping: 520Hz
      final pingPhase = 2 * pi * 520.0 * t;
      final pingGain = exp(-t / 0.35);
      s += sin(pingPhase) * pingGain * 0.35;

      // 3. Harmonic overtone: 1040Hz
      final overtonePhase = 2 * pi * 1040.0 * t;
      final overtoneGain = exp(-t / 0.18);
      s += sin(overtonePhase) * overtoneGain * 0.12;

      samples[i] = s.clamp(-1.0, 1.0) * 0.8;
    }

    return _encodeWav(samples, 1);
  }

  // Reveal: A single bright, clean bell.
  // 880Hz sine with slight vibrato. Slow attack, long exponential decay.
  Uint8List _generateRevealWav() {
    const duration = 1.5;
    final numSamples = (_sampleRate * duration).toInt();
    final samples = Float64List(numSamples);

    for (int i = 0; i < numSamples; i++) {
      final t = i / _sampleRate;
      // Bright bell with slight vibrato
      final vibrato = sin(2 * pi * 6.0 * t) * 0.03;
      final phase = 2 * pi * 880.0 * t + vibrato;
      final tone = sin(phase);

      // Gain envelope: slow attack, long sustain, exponential decay
      double gain;
      if (t < 0.08) {
        gain = (t / 0.08) * 0.35;
      } else {
        gain = 0.35 * exp(-(t - 0.08) / 0.7);
      }

      samples[i] = tone * gain * 0.6;
    }

    return _encodeWav(samples, 1);
  }

  Uint8List _encodeWav(Float64List samples, int numChannels) {
    const bitsPerSample = 16;
    const bytesPerSample = bitsPerSample ~/ 8;
    final dataSize = samples.length * bytesPerSample;
    final chunkSize = 36 + dataSize;
    final byteRate = _sampleRate * numChannels * bytesPerSample;

    final buffer = DataBuffer(44 + dataSize);

    buffer.writeString('RIFF');
    buffer.writeUint32(chunkSize);
    buffer.writeString('WAVE');

    buffer.writeString('fmt ');
    buffer.writeUint32(16);
    buffer.writeUint16(1);
    buffer.writeUint16(numChannels);
    buffer.writeUint32(_sampleRate);
    buffer.writeUint32(byteRate);
    buffer.writeUint16(numChannels * bytesPerSample);
    buffer.writeUint16(bitsPerSample);

    buffer.writeString('data');
    buffer.writeUint32(dataSize);

    for (final sample in samples) {
      final clamped = (sample * 32767).clamp(-32768, 32767).toInt();
      buffer.writeInt16(clamped);
    }

    return buffer.toUint8List();
  }
}

class DataBuffer {
  final ByteData _data;
  int _offset = 0;

  DataBuffer(int size) : _data = ByteData(size);

  void writeString(String s) {
    for (int i = 0; i < s.length; i++) {
      _data.setUint8(_offset++, s.codeUnitAt(i));
    }
  }

  void writeUint32(int value) {
    _data.setUint32(_offset, value, Endian.little);
    _offset += 4;
  }

  void writeUint16(int value) {
    _data.setUint16(_offset, value, Endian.little);
    _offset += 2;
  }

  void writeInt16(int value) {
    _data.setInt16(_offset, value, Endian.little);
    _offset += 2;
  }

  Uint8List toUint8List() => _data.buffer.asUint8List();
}