import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/screens/game/game_launch_privacy_gate.dart';

void main() {
  test('non-Desktop video stays hidden after transport connects', () {
    final gate = GameLaunchPrivacyGate(required: true);

    gate.markTransportConnected();

    expect(gate.transportConnected, isTrue);
    expect(gate.revealEligible, isFalse);
    expect(gate.videoVisible, isFalse);
  });

  test('host readiness still requires a newer rendered frame', () {
    final gate = GameLaunchPrivacyGate(required: true)
      ..markTransportConnected();

    expect(gate.markHostReady(generation: 4, framesRendered: 120), isTrue);
    expect(gate.observeFramesRendered(120), isFalse);
    expect(gate.completeReveal(), isFalse);
    expect(gate.observeFramesRendered(121), isTrue);
    expect(
      gate.observeFramesRendered(122),
      isFalse,
      reason: 'the safe-frame edge must be emitted exactly once',
    );
    expect(gate.completeReveal(), isTrue);
    expect(gate.videoVisible, isTrue);
  });

  test('new ready generation closes the gate and needs another frame', () {
    final gate = GameLaunchPrivacyGate(required: true)
      ..markTransportConnected()
      ..markHostReady(generation: 4, framesRendered: 10)
      ..observeFramesRendered(11)
      ..completeReveal();
    expect(gate.videoVisible, isTrue);

    expect(gate.markHostReady(generation: 5, framesRendered: 20), isTrue);
    expect(gate.videoVisible, isFalse);
    expect(gate.observeFramesRendered(20), isFalse);
    expect(gate.observeFramesRendered(21), isTrue);
  });

  test('Desktop remains compatible without host readiness capability', () {
    final gate = GameLaunchPrivacyGate(required: false)
      ..markTransportConnected();

    expect(gate.revealEligible, isTrue);
    expect(gate.completeReveal(), isTrue);
    expect(gate.videoVisible, isTrue);
  });

  test('reconnect always hides video again', () {
    final gate = GameLaunchPrivacyGate(required: false)
      ..markTransportConnected()
      ..completeReveal();
    expect(gate.videoVisible, isTrue);

    gate.resetTransport();

    expect(gate.videoVisible, isFalse);
    expect(gate.transportConnected, isFalse);
  });
}
