import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/models/stream_configuration.dart';

void main() {
  test('blocked gamepad buttons round-trip through JSON', () {
    // keyCode << 32 | scanCode: past 32 bits, and the JSON key is a string.
    const mirroredA = (96 << 32) | 656;
    final config = const StreamConfiguration().copyWith(
      blockedGamepadButtons: const {mirroredA: 'BUTTON A · scan 656'},
    );

    final restored = StreamConfiguration.fromJson(config.toJson());

    expect(restored.blockedGamepadButtons, {mirroredA: 'BUTTON A · scan 656'});
  });

  test('no buttons are blocked by default, and junk fails safe to empty', () {
    expect(const StreamConfiguration().blockedGamepadButtons, isEmpty);
    expect(
      StreamConfiguration.fromJson({
        'blockedGamepadButtons': 'not-a-map',
      }).blockedGamepadButtons,
      isEmpty,
    );
  });
}
