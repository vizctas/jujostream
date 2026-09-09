import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/screens/cinematic_intro/cinematic_soundtrack.dart';

void main() {
  test('renders one valid mono PCM soundtrack containing every cue', () {
    final wav = CinematicSoundtrack.build();
    final data = ByteData.sublistView(wav);

    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint32(24, Endian.little), 44100);
    expect(data.getUint16(34, Endian.little), 16);
    expect(data.getUint32(40, Endian.little), wav.length - 44);

    final impactSample =
        44 +
        (CinematicSoundtrack.impactOffset.inMilliseconds * 44100 ~/ 1000) * 2;
    final revealSample =
        44 +
        (CinematicSoundtrack.revealOffset.inMilliseconds * 44100 ~/ 1000) * 2;
    expect(_hasSignal(wav, impactSample, 4410), isTrue);
    expect(_hasSignal(wav, revealSample, 4410), isTrue);
  });
}

bool _hasSignal(Uint8List wav, int byteOffset, int sampleCount) {
  final data = ByteData.sublistView(wav);
  for (var i = 0; i < sampleCount; i++) {
    if (data.getInt16(byteOffset + i * 2, Endian.little).abs() > 100) {
      return true;
    }
  }
  return false;
}
