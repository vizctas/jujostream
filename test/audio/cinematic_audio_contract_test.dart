import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cinematic cues share one Fire OS audio-focus owner', () {
    final source = File(
      'lib/screens/cinematic_intro/cinematic_audio.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/screens/cinematic_intro/cinematic_intro_screen.dart',
    ).readAsStringSync();

    expect(source, contains('AudioPlayer? _player'));
    expect(source, isNot(contains('_fallPlayer')));
    expect(source, isNot(contains('_impactPlayer')));
    expect(source, isNot(contains('_chimePlayer')));
    expect(source, contains('AndroidAudioFocus.gainTransient'));
    expect(screen, contains('await _audio.play()'));
    expect(screen, isNot(contains('playImpact()')));
    expect(screen, isNot(contains('playRevealChime()')));
    expect(source, contains('setAudioContext'));
    expect(source, contains('ReleaseMode.stop'));
  });
}
