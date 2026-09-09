import 'dart:math';
import 'dart:typed_data';

/// Deterministically renders every cinematic cue into one PCM stream.
///
/// A single stream is required on Fire OS: independent MediaPlayers compete
/// for audio focus and pause one another when the impact and reveal overlap.
class CinematicSoundtrack {
  static const sampleRate = 44100;
  static const impactOffset = Duration(milliseconds: 4500);
  static const revealOffset = Duration(milliseconds: 4650);

  static Uint8List build() {
    final fall = _fallSamples();
    final impact = _impactSamples();
    final reveal = _revealSamples();
    final impactStart = _sampleOffset(impactOffset);
    final revealStart = _sampleOffset(revealOffset);
    final length = max(
      fall.length,
      max(impactStart + impact.length, revealStart + reveal.length),
    );
    final mix = Float64List(length);

    _mixInto(mix, fall, offset: 0, gain: 0.48);
    _mixInto(mix, impact, offset: impactStart, gain: 0.70);
    _mixInto(mix, reveal, offset: revealStart, gain: 0.48);
    return _encodeWav(mix);
  }

  static int _sampleOffset(Duration duration) =>
      (duration.inMicroseconds * sampleRate / Duration.microsecondsPerSecond)
          .round();

  static void _mixInto(
    Float64List destination,
    Float64List source, {
    required int offset,
    required double gain,
  }) {
    for (var i = 0; i < source.length; i++) {
      destination[offset + i] += source[i] * gain;
    }
  }

  static Float64List _fallSamples() {
    const duration = 4.5;
    const phase2Start = 2.5;
    final samples = Float64List((sampleRate * duration).toInt());

    for (var i = 0; i < samples.length; i++) {
      final t = i / sampleRate;
      double gain;
      if (t < phase2Start) {
        final frequency = 400.0 * pow(200.0 / 400.0, t / phase2Start);
        final vibrato = sin(2 * pi * 5.0 * t) * 0.02;
        final phase = 2 * pi * frequency * t + vibrato;
        gain = t < 0.5 ? (t / 0.5) * 0.2 : 0.2;
        samples[i] = sin(phase) * gain * 0.7;
      } else {
        final phaseTime = t - phase2Start;
        const phaseDuration = duration - phase2Start;
        final frequency = 200.0 * pow(60.0 / 200.0, phaseTime / phaseDuration);
        final vibrato = sin(2 * pi * 7.0 * t) * 0.035;
        final phase = 2 * pi * frequency * t + vibrato;
        if (phaseTime < 0.3) {
          gain = 0.2 + (phaseTime / 0.3) * 0.35;
        } else if (phaseTime < phaseDuration - 0.3) {
          gain = 0.55;
        } else {
          gain = 0.55 * (1.0 - (phaseTime - (phaseDuration - 0.3)) / 0.3);
        }
        samples[i] = sin(phase) * gain * 0.7;
      }
    }
    return samples;
  }

  static Float64List _impactSamples() {
    const duration = 0.8;
    final samples = Float64List((sampleRate * duration).toInt());
    for (var i = 0; i < samples.length; i++) {
      final t = i / sampleRate;
      final thump = sin(2 * pi * 60.0 * t) * exp(-t / 0.12) * 0.9;
      final ping = sin(2 * pi * 520.0 * t) * exp(-t / 0.35) * 0.35;
      final overtone = sin(2 * pi * 1040.0 * t) * exp(-t / 0.18) * 0.12;
      samples[i] = ((thump + ping + overtone).clamp(-1.0, 1.0)) * 0.8;
    }
    return samples;
  }

  static Float64List _revealSamples() {
    const duration = 1.5;
    final samples = Float64List((sampleRate * duration).toInt());
    for (var i = 0; i < samples.length; i++) {
      final t = i / sampleRate;
      final vibrato = sin(2 * pi * 6.0 * t) * 0.03;
      final tone = sin(2 * pi * 880.0 * t + vibrato);
      final gain = t < 0.08 ? (t / 0.08) * 0.35 : 0.35 * exp(-(t - 0.08) / 0.7);
      samples[i] = tone * gain * 0.6;
    }
    return samples;
  }

  static Uint8List _encodeWav(Float64List samples) {
    const bytesPerSample = 2;
    final dataSize = samples.length * bytesPerSample;
    final buffer = _WaveBuffer(44 + dataSize)
      ..writeString('RIFF')
      ..writeUint32(36 + dataSize)
      ..writeString('WAVE')
      ..writeString('fmt ')
      ..writeUint32(16)
      ..writeUint16(1)
      ..writeUint16(1)
      ..writeUint32(sampleRate)
      ..writeUint32(sampleRate * bytesPerSample)
      ..writeUint16(bytesPerSample)
      ..writeUint16(16)
      ..writeString('data')
      ..writeUint32(dataSize);

    for (final sample in samples) {
      buffer.writeInt16(
        (sample.clamp(-1.0, 1.0) * 32767).round().clamp(-32768, 32767),
      );
    }
    return buffer.bytes;
  }
}

class _WaveBuffer {
  _WaveBuffer(int size) : _data = ByteData(size);

  final ByteData _data;
  int _offset = 0;

  void writeString(String value) {
    for (var i = 0; i < value.length; i++) {
      _data.setUint8(_offset++, value.codeUnitAt(i));
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

  Uint8List get bytes => _data.buffer.asUint8List();
}
